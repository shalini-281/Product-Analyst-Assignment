# Part 2 — Decision Log

_Feature Engineering for a Churn Model_

## Key decisions (and why)

- **Derived the label from behaviour, not from `status`.** Part 1 measured `status` at a
  0.7pp spread in 90-day activity. Using the column that is literally named for churn
  would have produced a model trained on noise — with offline metrics good enough that
  nobody would have questioned it.
- **Split time explicitly (features ≤ cutoff, label > cutoff) and asserted it.** Building
  "lifetime" features over the whole file is the natural way to write this query and it
  leaks the outcome into the inputs. `leakage_check` is a `PASS`/`FAIL` view rather than a
  comment, because an assumption that is not tested is not a control.
- **Restricted scoring to members active in the 365 days before the cutoff.** Including
  members dormant for years would push the churn rate up with people who left long ago —
  the model would look more accurate while becoming less useful.
- **Put the cleaning in `common/clean.sql`, not in Part 2.** Parts 6, 7 and 8 all need the
  same cleaned data. One definition of "clean", derived from the audit that justified it,
  rather than four that drift apart.
- **Every repair carries a flag column, and the flags are features.** This does double
  duty: the model can learn to discount repaired rows, and the near-zero correlations on
  those flags are evidence the repairs did not themselves introduce a spurious pattern.
- **Smoothed the trend ratios** `(x+1)/(y+1)` so members with no prior-window activity
  produce a finite number rather than a null or an infinity the model must special-case.
- **Reported the label-window problem instead of quietly changing the window.** The brief
  specifies 90-day churn. A definition change is the stakeholder's call, so the 90-day
  table ships as asked with `label_window_sanity` beside it as evidence.

## Alternatives considered and rejected

- **`status` as the label** — rejected on Part 1's measurement. This was the single
  highest-leverage decision in the part.
- **Aggregating features over the full file** — rejected as leakage. It is the default
  shape of a "member-level aggregate" query, which is what makes it dangerous.
- **Scoring all 50,010 members** — rejected; dormant-for-years members make the label
  trivially predictable and the model commercially useless.
- **`GROUP BY transaction_id` to deduplicate** — rejected; deletes the 59 key collisions,
  which are real transactions.
- **Dropping the 15 corrupt-amount rows** — rejected; only one field is junk and the
  points make `amount` recoverable, so dropping would erase 15 genuine purchase events.
- **Netting negative amounts as refunds** — rejected on Part 1's three-way evidence.
- **Zero-filling null points** — rejected; it understates balances and silently corrupts
  `rd_redemption_rate`, which is a ratio.
- **Back-filling `join_date` from the first transaction** — rejected, and this is the one
  I went back and forth on. It would have removed the nulls from the table's *strongest*
  feature, which is exactly why it is a bad idea: a fabricated value in a top predictor is
  worse than an honest null.
- **Dropping the 150 conflicting members** — rejected; they are disproportionately
  high-tier and the flag preserves them without pretending the conflict is resolved.
- **One-hot encoding tier/country/brand in the feature table** — deferred to model
  training. The feature store should hold interpretable columns; encoding is a modelling
  concern and bakes in an assumption about the algorithm.

## Corrections made after external review

- **`join_date` later than a member's first transaction was documented as flagged, but the
  code only tested null and future dates.** 157 scored members kept an unflagged, invalid
  tenure value — in the table's *strongest* feature. The write-up described three defects
  and the `CASE` tested two. Caught by a reviewer reproducing the claim against the output,
  which is exactly the check I should have run on my own documented behaviour: assert the
  claim, do not just write it.
- **"No feature reads past the cutoff" was too strong a claim.** The assertion covers
  transaction-derived features; profile attributes come from a current-state export and
  cannot be reconstructed as-of-cutoff. Now scoped explicitly, with `snapshot_attribute_risk`
  naming each column and `member_features_modelling` excluding the unsafe ones — a caveat
  that is enforced in code rather than left in prose.

## Where an AI suggestion was wrong / incomplete, and how I caught it

- **The first feature query aggregated across the entire file.** That is the standard
  shape for "build a member-level feature table" and it leaks the label into the features
  — `f_txn_lifetime` would have counted post-cutoff transactions, which is most of the
  answer. Caught it by asking what the label actually *is* before writing the aggregates:
  once the label is "did they transact after date X", any feature reading past X is
  obviously disqualified. Fixed by splitting `tx_pre` / `tx_post` at the source and adding
  `leakage_check` so it cannot regress silently.
- **The 58.83% churn rate was nearly accepted as a modelling nuisance** — the standard
  advice for a high base rate is to rebalance or reweight. Wrong response here. Checking
  the median inter-purchase interval (**204 days**) showed the base rate is not an
  imbalance problem at all: the window is shorter than the population's natural purchase
  rhythm, so **90.8% of "churned" members are simply mid-gap**. Rebalancing would have
  buried a definition error under a modelling technique.
- **Nearly wrote up `tier` as a useful segmentation feature** because it is standard in
  loyalty churn models and it *looks* informative. Measuring it showed churn flat at
  58.6 / 58.9 / 58.7 / 60.0 and average spend flat at ~283 across the whole ladder. Caught
  it by checking rather than assuming domain convention transfers to this dataset.
- **`r_days_since_last_txn` ranking 12th by correlation looked like a bug.** Recency is
  supposed to dominate churn models, and the recency-band table *is* cleanly monotonic
  (45.5% → 68.6%). Reconciled the two rather than trusting either: correlation measures
  linear association and the relationship saturates. The conclusion is not "recency is
  weak" but "this table needs a tree-based model" — a different, more useful finding than
  either number alone.
- **Initial eligibility window used a magic `INTERVAL 455 DAY`** (90 + 365) computed from
  the anchor. Correct, but unreadable and easy to break. Rewritten to derive from
  `cutoff_date - INTERVAL 365 DAY`.
