# Capillary — Product Analyst Assignment

Response to [`Product_Analyst_Assignment.md`](Product_Analyst_Assignment.md).

All analysis is SQL (DuckDB) over the two raw CSVs; Python only runs it. Every figure
below regenerates from `members.csv` and `transactions.csv` in about eight seconds.

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python Assignment_solution/part1/code/run_audit.py          # and part2, 6, 7, 8
```

**This document is the summary.** Each part links to a full write-up with the complete
working, the code, and the generated evidence. Recency logic anchors to the data's own
last transaction date (`2026-06-30`) rather than the wall clock, so results reproduce.

---

## The three findings I would lead with

**1. The column that looks like a churn label is meaningless.** `status` separates
`active` / `inactive` / `churned` by **0.7 percentage points** of 90-day activity
(52.3 / 52.0 / 51.6). Using it as the label — the obvious move — trains a model on noise
that scores respectably offline. This redirected the whole of Part 2.

**2. Cleaning inverts the answer to Part 6.** On raw data, `sum(points)/sum(amount)` ranks
PulseMart **last at 0.906**. It is actually **first at 2.30**. Fifteen corrupted rows —
0.008% of the file, twelve of them PulseMart — inflate its denominator by **157%**. An
analyst who checks marketing's claim without cleaning reaches the opposite conclusion.

**3. A 90-day churn window does not fit this population.** The median member buys every
**204 days**, so **90.8%** of "churned" members are merely mid-gap. I built the table as
specified and shipped the evidence beside it, because changing the target definition is
the stakeholder's call, not mine.

---

## Section 1 — Pipeline & Modelling

### Part 1 — Data Quality & Governance Audit → [full write-up](Assignment_solution/part1/)

13 findings, filtered by two lenses: does it break the **model** (corrupts the label, a
feature, or a join's row count) or a **governance audit** (PII, identity resolution,
traceability). Every column is read as `VARCHAR` deliberately — a type-sniffing reader
turns the 1,500 `MM/DD/YYYY` dates into nulls, so the report would say *"1,500 nulls"*
instead of *"a second date format"*: same count, wrong root cause, wrong fix.

| Severity | Finding |
|---|---|
| A | `status` behaviourally meaningless (0.7pp spread) |
| A | 15-row corrupted batch, all dated 2026-02-15, sentinel amounts with intact points |
| A | 150 member_ids with two contradictory profiles, no `updated_at` to arbitrate |
| A | 1,936 replayed transactions **and** 59 primary-key collisions — two problems, two fixes |
| A | 2,988 orphan transactions from an unloaded second source system |
| A | PII unmasked for all 50,160 members; 20 emails span multiple member_ids |
| B | 2,012 sign-flipped amounts, 3 date formats, 1,234 join_date defects, 1,302 vocabulary variants, 1,514 null points |

**Three findings inverted on inspection**, and in each case the careless fix produces a
plausible table that is quietly wrong: the negative amounts are **sign errors, not
refunds** (no clawback, points computed on the magnitude, 0 of 1,995 have a paired
original); the slash dates are **provably `MM/DD`** (component 1 never exceeds 12 while
component 2 reaches 31); the null points are **exactly recoverable**, since
`points = round(rate × amount)` holds for 100% of rows within one point.

**The `transaction_id` prefix reveals three loaders** — `T#####` mainline (191,308 rows),
`TX#####` (2,988 rows, **100% orphaned**), `TO####` (15 rows, **100% corrupt, one day**).
Each family is perfectly homogeneous in its defect, which is what turns "some missing
members" into *an entire unloaded source system* and "some bad values" into *one bad load
on 2026-02-15*.

Checks that passed are reported too — birth dates all plausible, all emails well-formed,
brand and channel vocabularies clean — so the audit doubles as a regression test.

### Part 2 — Feature Engineering → [full write-up](Assignment_solution/part2/)

**31,690 members × 37 features.** Since `status` is unusable, the label is derived from
behaviour, which forces a time split: features from transactions on or before
`2026-04-01`, label = any transaction after it. Aggregating "lifetime" features over the
whole file is the natural way to write the query and leaks the answer into the inputs, so
`leakage_check` **asserts** the split rather than assuming it.

Features span recency, frequency, monetary, engagement trend, redemption, channel breadth,
profile, and five **data-quality exposure flags** that carry Part 1's repairs forward so a
model can discount repaired rows. Those flags correlate near zero with the label, which is
evidence the repairs did not introduce a spurious pattern.

Seven DQ issues handled (three required). The ones that mattered: **dedup on
`(transaction_id, row_fp)`, not `transaction_id`** — the reflex fix silently deletes the
59 genuine collisions; **corrupt amounts recovered** as `points / rate` rather than
dropped, since only one field is junk; **sign errors `abs()`-ed, not netted**, because
Part 1 proved they are not refunds.

**What I would not ship:** `p_tenure_days` is the strongest feature (r = 0.38) *and* is
built on `join_date`, the least trustworthy column in the file. `tier` is inert here
(churn flat at 58.6–60.0% across the ladder) and is an export-snapshot attribute — see
*Known limitations*.

### Part 3 — Pipeline Design → [full write-up](Assignment_solution/part3/)

Daily, 20 brands, ~50x volume, feature store read at 07:00.

**Idempotency by deterministic addressing, not bookkeeping.** Partitions keyed on
`(brand, logical_date)` and replaced wholesale, plus `MERGE` on the natural key. A
processed-batches table can desynchronise from reality; a deterministic path cannot. **The
merge key is `(source_system, transaction_id)`** — generic best practice says
`transaction_id`, and Part 1 shows why that would be idempotent *and lossy*.

**Schema drift is classified, not just detected** — additive warns, breaking halts that
brand, unknown enum quarantines the row. Halting on an added column trains people to mute
the channel; continuing through a retyped column corrupts the store silently.

**The DQ gate is a task publication depends on**, with an SLA that has numbers and an
owner: sources by 03:00, features by 06:00, **26-hour staleness ceiling**. Two severities
only — blocking holds the previous snapshot and pages; warning publishes and tickets. The
check that matters most is `volume_within_expected_band`, because it catches the *partial*
load that looks like a real business drop.

**PII is tokenised between raw landing and staging** — later leaves a window where
clear-text PII is queryable. Email → vault token (must stay reversible; a DSAR arrives as
an email address, and 20 emails span multiple member_ids so a `member_id` lookup returns
an incomplete record). Names → HMAC. Birth date → age band at ingest, raw date discarded.

**Orchestration: Airflow**, for backfill/replay as a first-class path, dynamic mapping over
20 brands, heterogeneous sources, and because it orchestrates rather than computes. Its
operational cost is real and stated. One condition flips the answer: if all compute already
runs on Databricks, Workflows wins.

### Part 4 — Production Incident → [full write-up](Assignment_solution/part4/)

**Don't escalate yet** — and I would say so in the thread within five minutes, because the
signature is diagnostic before any query runs. Exactly **0** rather than low (a default
value, not a measurement); **one brand** (brands map to feeds); the **same 6-day window**
for everyone (a sharp start *and* end); **~40%** (a partition, not a behaviour).

Triage is ordered by hypothesis-space elimination. Step 1 is the fork: **is the unaffected
60% still normal?** A real drop shifts the whole distribution; a data failure zeroes a
subset. Then: does the raw activity exist upstream → what do affected members share → what
do the pipeline runs say → what changed 7 days ago → and only then, did something real
happen.

Ranked: **H1 partial feed failure with missing activity coalesced to zero (~60%)** — it
explains all four signature properties at once; **H2 join-key mismatch (~25%)**, which has
precedent in this very dataset; **H3 app instrumentation break (~10%)**, the only one where
40% is a natural number rather than a suspicious one. A **genuine engagement drop is <5%**,
ranked last explicitly with falsification criteria, because that is the question being
asked and it deserves a direct answer.

**The prevention finding worth more than the bug:** `COALESCE(activity, 0)` converts *"we
don't know"* into *"we know it's zero"*, destroying the distinction the incident needed.
Missing input should produce NULL and fail a null-rate check.

### Part 5 — Stakeholder Communication → [full write-up](Assignment_solution/part5/) · [the message](Assignment_solution/part5/slack_message.md)

144 words. The brief hides its constraint in one line — *forwarded as-is to a client* — so
it has two audiences and no chance to tailor for either.

The load-bearing sentence is *"These checks used to run after the scores went out — now
they run before."* The honest version is that we found real defects, but a client reading
*"we discovered our data was wrong"* hears *"the scores I've been acting on were wrong"*.
What I wrote is completely true, volunteers no fault, and still explains the delay. The
delay is justified in the client's currency — a campaign aimed at people who never left
*"spends budget and irritates good customers"* — not in data-quality language.

I named that tension in the write-up rather than pretending the framing is neutral,
including what I would say if the PM asked directly whether we found problems.

---

## Section 2 — Analytical Reasoning

### Part 6 — Which brand is most generous? → [full write-up](Assignment_solution/part6/)

**Marketing is wrong. PulseEats is the least generous of the three.**

| Brand | Points per dollar | |
|---|---|---|
| **PulseMart** | **2.30** | most generous |
| PulseHome | 2.00 | |
| **PulseEats** | **1.75** | least generous |

Exact constants, not estimates — per-transaction standard deviation is 0.009 and median
equals mean equals ratio-of-sums to four decimals.

**The contamination points the wrong way**, which is what makes this more than an
arithmetic exercise. Raw, the ranking is PulseHome 1.948 / PulseEats 1.746 / **PulseMart
0.906** — the most generous brand appears worst by a factor of two. Twelve of the fifteen
corrupted rows are PulseMart, adding **$6.6M of phantom dollars** and inflating its
denominator **157.5%**. The ranking flips at the first cleaning step; everything after
moves the third decimal.

**Eight framings tested — PulseMart wins all eight, PulseEats none**, including the
wrong-join-key version that attributes spend to the member's home brand (9.3% of
transactions are cross-brand, so it is a live trap). Tier-mix and basket-mix confounds
ruled out. No reconstruction reproduces marketing's claim, so this is not a methodology
dispute.

**Is the framing trustworthy? Only conditionally** — points per dollar ranks generosity
only if a point is worth the same everywhere, and nothing in the data states a redemption
value. Rather than leave that unfalsifiable, I quantified it: **marketing needs a PulseEats
point to be worth ≥1.31× a PulseMart point.** Redemption sizes suggest **~1.17×** — the
direction their argument needs, short of the magnitude. The objection is real and closes
most of the gap without changing the answer.

*Confidence: very high on the rates and on the claim being unsupported; high on the
ranking; moderate on the 31% gap.*

### Part 7 — Win-back list → [full write-up](Assignment_solution/part7/) · [the 20 members](Assignment_solution/part7/output/wb_target_list.csv)

**"Slipping away" is measured against each member's own rhythm.** With a median gap of 204
days, a fixed "no purchase in 90 days" rule flags **23,911 members — 48% of the base** —
while still missing an at-risk weekly shopper silent for 60 days. So the signal is
`overdue_ratio = days_since_last / personal_avg_gap`, bounded 1.5–4: past their own rhythm,
not so far gone as to be unrecoverable.

Funnel: 52,984 → **3,329 eligible** → top 20 by value at risk. Three exclusions come
straight from Part 1 and each would otherwise be an operational failure — orphans have no
email, conflicted profiles cannot be addressed correctly, and 20 shared emails would
double-contact one person.

The selected 20 average **6.3× the base annualised spend** and **8.7× the points balance**.
That balance is the campaign: they hold **3,948 unredeemed points each** and almost none
has ever redeemed, so the offer costs nothing and draws down an existing liability.

**Bronze outnumbers Platinum 9 to 2** — the highest-value members are mostly low tier,
corroborating Part 2's finding that tier is inert. Targeting by tier would have missed most
of this list. PulseHome is 13 of 20 against an expected ~7; I did not impose quotas, but
flagged it as needing the brand's buy-in.

*Confidence: high that these are valuable and off-rhythm (measured); low that a campaign
recovers them — there is no response history here, so I did not build a propensity model
with no outcome to train on.*

### Part 8 — Points liability → [full write-up](Assignment_solution/part8/)

## **$57,900** — range **$35,000–$116,000**

| | |
|---|---|
| Points outstanding (measured) | **23,155,302** |
| × value per point (assumed) | $0.010 |
| × ultimate redemption (assumed) | 25% |
| **Net liability** | **$57,888** |

The points arithmetic is near-exact; the dollars rest on two assumptions the data does not
contain, so the structure separates them.

**Point value** is anchored to the earn rate: at $0.01 the brands return 1.75–2.30% of
spend, normal for retail loyalty. That reasoning is what makes it defensible rather than
round.

**Breakage** is where the work is. Only 9.32% of points issued have been redeemed, and two
stories fit — a young programme still accumulating, or members who do not redeem — implying
liabilities ~10× apart. Cohort age separates them: redemption is **flat at 8–10% from a
4.8-year-old cohort to a 0.2-year-old one**. Corroborated by the cleanest statistic here —
**63% of members have never redeemed a single point, and they hold 54.3% of the balance.**

I assume 25% rather than the ~10% observed because redemptions are only visible inside
purchase rows (so observed redemption is a floor), no expiry policy is known, and a
liability should not be understated. It is a judgement, which is why the sensitivity grid
spanning **$17K–$347K** is the real deliverable.

**What I distrust most:** the cohort test is diluted — cohorts are defined by first
purchase but members keep earning, so older cohorts look flatter than they are. The
63%-never-redeemed figure is immune to that and carries the argument instead. **And the
single most useful thing I can say is a question I cannot answer from the data: what is the
expiry policy?** If points expire at 24 months, a third of this number is not a liability.

---

## Known limitations

**The feature table is not fully leakage-free.** `leakage_check` covers transaction-derived
features only. `tier`, `tier_rank`, `country` and `home_brand` come from a current-state
export with no SCD history, so they are as-of-export, not as-of-cutoff: a member scored at
the April cutoff may carry a tier they only reached in June. This is unverifiable with this
data, so those columns are labelled **exploratory** (`snapshot_attribute_risk`) and excluded
from `member_features_modelling`, the view intended for training.

**The 90-day churn label is mis-specified for this population** (median gap 204 days). Built
as briefed, with the evidence shipped alongside.

**No campaign response history**, so Part 7 optimises value at risk, not expected recovery.

**No rewards catalogue and no expiry policy**, so both of Part 8's multipliers are
assumptions rather than measurements.

---

## How I worked

Full decision logs — decisions, rejected alternatives, and mistakes caught — sit in each
part folder as `decision_log.md`. The errors worth naming:

- **Part 1:** my corrupt-batch detector returned 3,003 rows instead of ~15. I had assumed an
  odd id prefix marked the same bad batch; the orphans carry a different prefix and are a
  separate finding. Caught because the count was two orders of magnitude off. The corrected
  detector plus the prefix table produced the strongest evidence in the audit.
- **Part 1:** the determinism check read 98.98% and I nearly wrote "impute cautiously". The
  gap is a rounding convention, not non-determinism — spotted because the *worst* match rate
  belonged to the brand with the *cleanest* rate. Within-1-point is 100%, which is the
  difference between dropping 1,514 rows and imputing them exactly.
- **Part 2:** the first feature query aggregated over the whole file — the standard shape,
  and it leaks the label. Fixed by splitting at source and asserting it.
- **Part 2:** I nearly treated the 58.83% churn rate as a class-imbalance problem to
  rebalance. Checking the inter-purchase interval showed it is a label-definition problem.
- **Part 7:** my first list was an artifact of my own value metric — annualising over short
  spans, so the picks averaged a 197-day active span against 509 for the pool. Caught by
  asking whether the selected members differed from the pool on anything I had not intended
  to select on.
- **Part 8:** I nearly presented the cohort test as conclusive before realising it is
  diluted by ongoing earning.

**Corrections made after external review:** `join_date` later than a member's first
transaction was documented as flagged but only null/future dates were tested, leaving 157
scored members with an unflagged invalid tenure (now fixed); the leakage claim was scoped to
transaction-derived features; the liability is now summed from per-member balances floored
at zero, since a member cannot owe the programme points.

---

## Repository layout

```
members.csv, transactions.csv     raw exports, untouched
SOLUTION.md                       this document
Assignment_solution/
  common/                         paths.py + clean.sql (shared cleaning layer)
  part1/ … part8/
    README.md                     full write-up for that part
    decision_log.md               decisions · alternatives · mistakes caught
    code/                         SQL + thin Python runner
    output/                       generated evidence (regenerable)
```

Part 1 audits the **raw** data; `common/clean.sql` implements the fixes it prescribed,
once, so Parts 2 and 6–8 share one definition of "clean". Parts 3–5 are design and writing
and carry no code.
