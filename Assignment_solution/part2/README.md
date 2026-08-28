# Part 2 — Feature Engineering for a Churn Model

**Section:** Pipeline & Modelling · **Status:** Complete

**The ask.** Member-level feature table, at least 8 features for 90-day churn. Show the code, state how at least 3 Part 1 issues were handled and why, and flag anything risky to ship.

## How to run

```bash
python Assignment_solution/part2/code/build_features.py
```

Produces `output/member_features.csv` — **31,690 members × 40 columns** (37 features +
`member_id`, `cutoff_date`, `churned_90d`) — plus 12 validation artefacts.

## Architecture

| File | Role |
|---|---|
| `common/clean.sql` | Implements the fixes Part 1 prescribed. Shared, so Parts 2 and 6–8 agree on what "clean" means instead of each re-deciding |
| `part2/code/features.sql` | Label design + 37 features + validation views |
| `part2/code/build_features.py` | Runner only — no analysis logic |

Part 1 deliberately audits the **raw** data; this part consumes the **cleaned** output.
Every repair carries a flag column, so nothing is silently altered and an auditor can
count what was touched.

---

## The label is the load-bearing decision

### Why `status` cannot be the label

Part 1 (DQ-01) measured it: 90-day activity is **52.3% / 52.0% / 51.6%** across
`active` / `inactive` / `churned` — a **0.7 percentage point** spread. The column that
looks like a ready-made churn label carries no behavioural signal. A model trained on it
learns noise and ships with respectable offline metrics, which is the worst failure mode
because nothing breaks loudly.

So the label must be derived from behaviour — and that forces a time split.

### The time split

```
   ... history .................|   cutoff   |...... outcome 90d ......|
   features computed here                     label observed here
                             2026-04-01                       2026-06-30
```

- **Features** use transactions **on or before** `2026-04-01`
- **Label** `churned_90d = 1` if the member made **no transaction after** the cutoff

The tempting shortcut is to aggregate "lifetime" features across the whole file. That
leaks the outcome into the inputs and yields a model that scores near-perfectly offline
and fails in production. So it is **asserted, not assumed**:

```sql
CREATE OR REPLACE VIEW leakage_check AS
SELECT ...
       CASE WHEN (SELECT max(...) FROM tx_pre)  <= cutoff_date
             AND (SELECT min(...) FROM tx_post) >  cutoff_date
            THEN 'PASS -- no feature reads past the cutoff'
            ELSE 'FAIL -- LEAKAGE' END AS verdict;
```

| max_feature_txn_date | cutoff_date | min_outcome_txn_date | verdict |
|---|---|---|---|
| 2026-04-01 | 2026-04-01 | 2026-04-02 | **PASS** |

**The scope of that check matters, and it is narrower than "leakage-free".** It covers
**transaction-derived** features only. It cannot cover the profile attributes: `members.csv`
is a current-state export with no SCD history, so `tier`, `tier_rank`, `country` and
`home_brand` are as-of-export, not as-of-cutoff — a member scored at the April cutoff may
carry a tier they only reached in June. That is unverifiable with this data, so those four
are labelled exploratory in `snapshot_attribute_risk` and excluded from
**`member_features_modelling`**, the view intended for training. `member_features` remains
the full table for exploration.

### Scoring population

The 31,690 members with at least one transaction in the **365 days before the cutoff** —
the active base a retention team could actually act on. Including members dormant for
years would inflate the churn rate with people who left long ago, flattering the model
while telling the business nothing. Orphan members (DQ-06) are absent by construction:
they have no profile row.

## Assumptions

1. **Time anchor is the data's own maximum transaction date (2026-06-30)**, not the wall
   clock — so the cutoff, the label and every feature reproduce identically on any run.
2. **A member with no post-cutoff transaction has churned.** This is the assignment's
   definition. It is also the assumption I trust least — see *What the results say*.
3. **Absence of a transaction means absence of engagement.** There is no app-open, email
   or web data, so "engagement trend" can only be purchase-derived.
4. **Points earn rates are stable per brand over time** (1.75 / 2.00 / 2.30). Verified as
   deterministic constants in Part 1, but the file carries no rate-change history, so a
   historical promotion would be invisible.
5. **`tier` is current-as-of-export, not as-of-cutoff** — no SCD history exists. Treated
   as a known risk rather than a solved problem.
6. **Redemptions are only visible inside purchase rows.** `transaction_type` has one
   value, so a member who redeemed without buying is invisible to every redemption feature.

---

## The feature table — 37 features

| Group | Features | Why it predicts churn |
|---|---|---|
| **Recency** (3) | `r_days_since_last_txn`, `r_days_since_first_txn`, `r_days_since_last_redemption` | The strongest churn signal in almost every retail model — how long since we last saw them |
| **Frequency** (6) | `f_txn_lifetime`, `f_txn_90d`, `f_txn_180d`, `f_txn_365d`, `f_active_months_12m`, `f_avg_days_between_txn` | Habit strength. `f_avg_days_between_txn` gives each member their *own* baseline rhythm rather than a global one |
| **Monetary** (5) | `m_spend_lifetime`, `m_spend_90d`, `m_spend_365d`, `m_avg_basket`, `m_max_basket` | Value at risk, and a proxy for how embedded the brand is in their routine |
| **Engagement trend** (2) | `t_txn_trend_90_vs_prior`, `t_spend_trend_90_vs_prior` | Direction, not level. A member at 4 purchases/quarter falling to 1 is churning; a steady 1 is not |
| **Redemption** (5) | `rd_points_earned`, `rd_points_redeemed`, `rd_points_balance`, `rd_redemption_rate`, `rd_has_ever_redeemed` | Redeeming is the act of *choosing* the programme. A large unredeemed balance is also a retention lever |
| **Breadth** (5) | `c_distinct_channels`, `c_distinct_brands`, `c_pct_app`, `c_pct_online`, `c_pct_in_store` | Multi-channel and multi-brand members are structurally harder to lose |
| **Profile** (6) | `tier`, `tier_rank`, `country`, `home_brand`, `p_age`, `p_tenure_days` | Segment context and lifecycle stage |
| **DQ exposure** (5) | `dq_profile_conflicted`, `dq_join_date_unusable`, `dq_sign_error_txns`, `dq_points_imputed_txns`, `dq_amount_recovered_txns` | Part 1's issues carried forward as *features*, so the model can learn to discount repaired rows instead of trusting them equally |

The trend features are Laplace-smoothed so a member with no prior-window activity gives a
finite ratio instead of a divide-by-zero the model has to special-case:

```sql
round((a.f_txn_90d + 1.0) / (a.f_txn_prior_90d + 1.0), 3) AS t_txn_trend_90_vs_prior
```

---

## Data quality issues handled (7 — the brief asked for 3)

| # | Issue | Decision | Why, and what I rejected |
|---|---|---|---|
| **DQ-01** | `status` meaningless | **Dropped entirely** — not label, not feature | Using it as the label was the obvious move and would have invalidated the whole model. Not kept as a feature either: at 0.7pp separation it adds only variance |
| **DQ-04 / 05** | 1,995 duplicate ids | **Dedup on `(transaction_id, row_fp)`**, not on `transaction_id` | Deduplicating on id alone is the reflex fix and would have silently deleted the **59 genuine transactions** that merely share a corrupted id. Fingerprinting removes exactly the 1,936 byte-identical replays and keeps both sides of every collision, re-keyed on a surrogate. *Rejected:* `GROUP BY transaction_id` (deletes real events); keeping all duplicates (inflates frequency/monetary features unevenly across members) |
| **DQ-02** | 15 corrupt amounts | **Recovered** `amount = points_earned / earn_rate`, flagged | Only `amount` is junk — the points survived intact, and points are deterministic, so the true basket is reconstructable. *Rejected:* dropping the rows (deletes 15 real purchase events from recency and frequency); keeping the sentinel values (one row of 999,999.99 destroys every monetary aggregate it touches) |
| **DQ-07** | 2,012 negative amounts | **`abs()` + flag** | Part 1 proved these are sign errors, not refunds: no clawback, points computed on the magnitude, and 0 of 1,995 have a paired original. *Rejected:* netting them as refunds (double-penalises members for purchases they actually made); dropping (discards ~1% of real spend) |
| **DQ-11** | 1,514 null points | **Imputed** `round(rate × amount)`, flagged | Justified by measurement, not convenience — determinism is 100.0% within one point. *Rejected:* dropping (loses real events); zero-filling (understates balances and corrupts `rd_redemption_rate`) |
| **DQ-03** | 150 conflicting profiles | **Deterministic pick (highest tier) + `dq_profile_conflicted` flag** | There is no `updated_at`, so **no rule can recover the truth** — any choice is arbitrary. The flag is the honest part: it lets the model discount those members instead of being handed a fiction with false confidence. *Rejected:* dropping 150 members (loses valuable, mostly high-tier records); random pick (non-reproducible) |
| **DQ-06** | 2,988 orphan transactions | **Quarantined** to `quarantined_orphan_tx.csv`, excluded from features | No profile row ⇒ no member-level features, and they cannot be scored anyway. *Rejected:* silent inner join — the default behaviour, and it makes $192,331 of spend disappear with no trace |
| **DQ-09** | `join_date` defects | **NULL where not credible + `dq_join_date_unusable` flag** — all three defects tested: blank, future-dated, **and later than the member's own first transaction** | *Rejected:* back-filling with first-transaction date. Tenure is the strongest feature in the table, and a fabricated value there is far worse than a missing one the model can route around |

Cleaning audit (`clean_audit.csv`) reconciles every row:

| metric | value |
|---|---|
| tx rows in raw | 194,311 |
| replay rows removed | 1,936 |
| sign errors repaired | 1,996 |
| corrupt amounts recovered | 15 |
| null points imputed | 1,497 |
| orphan tx quarantined | 2,988 |
| members after conflict resolution | 50,010 (150 flagged) |

*(Repair counts differ slightly from Part 1's raw counts — 1,996 vs 2,012 sign errors,
1,497 vs 1,514 null points — because deduplication runs first and removes replayed copies
of affected rows. The two numbers agreeing would actually indicate a bug.)*

---

## What the results say

### 1. The label is directionally valid

Churn falls monotonically as recency improves — the cheapest possible test that the label
means something:

| recency band | members | churn rate |
|---|---|---|
| 0–30d | 6,869 | **45.5%** |
| 31–90d | 8,514 | 55.0% |
| 91–180d | 7,936 | 64.2% |
| 181–365d | 8,371 | **68.6%** |

### 2. But a 90-day window is the wrong definition of churn for this population

This is the most important finding in Part 2, and no amount of feature engineering fixes it:

| | |
|---|---|
| Churn window | 90 days |
| **Median days between purchases** | **204** |
| Median purchases in the last year | **2** |
| Members whose normal gap already exceeds 90 days | **82.7%** |
| **"Churned" members who are merely mid-gap** | **90.8%** |

The median member buys about **twice a year**. "No purchase in 90 days" is *ordinary
behaviour* for most of them, so the label is largely Poisson timing noise wearing the word
churn — which is why the base rate is an implausibly high **58.83%**.

I built the 90-day table as specified and shipped `label_window_sanity` beside it. **With
more time I would recommend a 180- or 365-day window, or an inter-purchase-time / BTYD
model that predicts each member against their own rhythm** rather than a fixed calendar
window. That is a definition change, and a definition change is the stakeholder's call —
so the evidence goes in the deliverable rather than being silently substituted.

### 3. The signal is real but modest, and it is about *purchase rate*, not recency

| feature | corr with churn |
|---|---|
| `p_tenure_days` | **+0.382** |
| `r_days_since_first_txn` | +0.354 |
| `f_txn_90d` | −0.206 |
| `f_txn_lifetime` | +0.202 |
| `f_avg_days_between_txn` | +0.195 |
| `r_days_since_last_txn` | +0.162 |
| `t_txn_trend_90_vs_prior` | −0.146 |

Two things worth reading carefully:

- **`r_days_since_last_txn` is only the 12th strongest feature**, despite the recency
  table above being cleanly monotonic. That is not a contradiction — correlation measures
  *linear* association and the true relationship saturates. It is a reminder that this
  table wants a tree-based model, not a linear one.
- **Tenure leads because it proxies purchase rate.** For a given lifetime transaction
  count, longer tenure means the same purchases spread thinner, so longer gaps, so a
  higher chance of no purchase in the next 90 days. Legitimate signal — but see below.

### 4. `tier` is inert in this dataset

| tier | members | churn rate | avg lifetime spend |
|---|---|---|---|
| Bronze | 12,496 | 58.6% | 285.7 |
| Silver | 9,468 | 58.9% | 282.1 |
| Gold | 7,073 | 58.7% | 282.4 |
| Platinum | 2,653 | 60.0% | 283.9 |

Churn and spend are flat across the whole ladder (`tier_rank` correlation: **+0.005**).
Tier is assigned independently of behaviour here. In real loyalty data tier is usually
*earned* from spend, so this is a property of this dataset rather than of tiering — but
it means tier contributes nothing and invites false confidence.

### 5. The DQ flags carry almost no signal — which is the good news

`dq_profile_conflicted` (−0.010), `dq_join_date_unusable` (+0.003),
`dq_amount_recovered_txns` (+0.001). The repairs did not introduce a spurious pattern
correlated with the outcome. Had any flag shown strong correlation, it would have meant
the *repair itself* was leaking — a real risk with imputation, and the reason the flags
exist at all.

---

## Features I would be nervous shipping as-is

**`p_tenure_days` — and it is the strongest feature in the table.** It is derived from
`join_date`, the least trustworthy column in the file: 999 blank, 30 future-dated, 205
later than the member's own first transaction. A feature that is simultaneously the top
predictor *and* built on the worst-quality source is exactly what fails silently in
production — if the upstream fix in Part 3 changes how `join_date` is populated, the
model's most important input shifts underneath it with no error raised. It is `NULL`-where-
not-credible and flagged, but I would want a monitored distribution check before trusting it.

**`tier` and `tier_rank` — two independent reasons, and they are now enforced rather than
just noted.** *Temporal leakage:* current tier as of export with no SCD history, so a
member scored at an April cutoff may carry a tier they only reached in June — unverifiable
with this data, which is precisely why it is risky. *And it is empirically inert*
(correlation +0.005). Excluded from `member_features_modelling`; retained in
`member_features` for exploration only.

**`rd_redemption_rate` and `r_days_since_last_redemption`.** Redemptions exist only inside
purchase rows — `transaction_type` has a single value — so a member who redeemed without
buying is invisible. `r_days_since_last_redemption` is NULL for **54.7%** of members, and
that NULL conflates "never redeemed" with "redeemed outside a purchase". Directionally
useful, not reliable.

**`rd_points_balance`** assumes points never expire. No expiry field exists in the data.
The same assumption is load-bearing for Part 8's liability figure.

---

## Output index

| File | Contents |
|---|---|
| `member_features.csv` | The deliverable — 31,690 members × 40 columns |
| `feature_dictionary.csv` | Every column: dtype, null count, distinct, min/max/mean |
| `feature_signal.csv` | Point-biserial correlation of each feature with the label |
| `leakage_check.csv` | The train/label time-split assertion |
| `label_balance.csv`, `churn_by_recency.csv`, `churn_by_tier.csv` | Label validity checks |
| `label_window_sanity.csv` | Evidence the 90-day window mismatches this population |
| `clean_audit.csv` | Row-level reconciliation of every repair |
| `brand_rate.csv` | Derived earn rates used for imputation and recovery |
| `feature_nulls.csv` | Features NULL by design, with rates |
| `quarantined_orphan_tx.csv` | The 2,988 orphan transactions — excluded, not lost |
| `build_summary.txt` | Full console output |

See `decision_log.md` for decisions, rejected alternatives, and the errors I caught.
