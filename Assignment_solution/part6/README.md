# Part 6 — Which brand is actually the most generous?

**Section:** Analytical Reasoning · **Status:** Complete

**The ask.** Marketing claims PulseEats is the most generous brand on points per dollar. Settle it: which brand actually rewards a dollar most, is that framing trustworthy, and how confident am I?

## The answer

**Marketing is wrong, and not marginally — PulseEats is the *least* generous of the three.**

| Brand | Points per dollar | Rank |
|---|---|---|
| **PulseMart** | **2.30** | 1st — most generous |
| PulseHome | 2.00 | 2nd |
| **PulseEats** | **1.75** | **3rd — least generous** |

These are not estimates. They are exact constants: the standard deviation of per-transaction
points-per-dollar is **0.009** within each brand, and median equals mean equals ratio-of-sums
to four decimal places. Points are `round(rate × amount)` and the rate never varies.

**The skeptical analyst is right.** PulseMart rewards a dollar **31% more generously** than
PulseEats.

---

## The trap: the contamination points the wrong way

This is the part worth reading. On the **raw** data, the naive and entirely reasonable
calculation `sum(points) / sum(amount)` produces this:

| Brand | Naive points/dollar | Naive rank |
|---|---|---|
| PulseHome | 1.9483 | 1st |
| PulseEats | 1.7463 | 2nd |
| **PulseMart** | **0.9057** | **3rd — looks *least* generous** |

**PulseMart, the genuinely most generous brand, appears to be the worst — by a factor of
two.** An analyst checking marketing's claim without cleaning would conclude PulseMart is
the stingiest brand in the portfolio and never look again.

The cause is 15 rows. Part 1 (DQ-02) found a single corrupted batch dated 2026-02-15 with
sentinel amounts (999999.99, 99999.00) and *normal* points. **Twelve of the fifteen are
PulseMart:**

| Brand | Sentinel rows | Phantom dollars | Denominator inflation |
|---|---|---|---|
| **PulseMart** | **12** | **$6,599,994** | **+157.5%** |
| PulseHome | 2 | $163,889 | +3.9% |
| PulseEats | 1 | $64,000 | +1.5% |

Fifteen rows out of 194,311 — **0.008% of the data** — inflate PulseMart's denominator by
over 157% and invert the entire ranking. The ranking flips at the very first cleaning step:

| Cleaning step | PulseEats | PulseHome | PulseMart | Most generous |
|---|---|---|---|---|
| A. Raw, nothing cleaned | 1.746 | 1.948 | **0.906** | PulseHome |
| B. Drop 15 sentinel amounts | 1.773 | 2.025 | **2.332** | **PulseMart** |
| C. + repair sign errors | 1.737 | 1.984 | 2.282 | PulseMart |
| D. + dedup replays, impute points | **1.750** | **2.000** | **2.300** | **PulseMart** |

Steps C and D shift the third decimal. **Step B changes the answer.**

## What had to be cleaned, and why

| Fix | Rows | Effect on the answer |
|---|---|---|
| **Exclude 15 sentinel amounts** (DQ-02) | 15 | **Decisive — flips the ranking** |
| Repair sign-flipped amounts (DQ-07) | 2,012 | Third decimal. Left in, they understate every brand's rate by shrinking the denominator |
| Deduplicate replayed rows (DQ-04) | 1,936 | Negligible — replays scale numerator and denominator together |
| Impute null points (DQ-11) | 1,514 | Small downward bias if left null — points missing while spend counts |
| **Use transaction brand, not member brand** | 9.3% of rows | Attribution, not magnitude — but it is a real trap (framing F8) |

---

## Is "points per dollar" a trustworthy framing?

Two separate questions, and they get different answers.

### Is the metric self-consistent? **Yes.**

I tested eight framings a marketing team could plausibly have used. **PulseMart wins all
eight. PulseEats wins none.**

| Framing | PulseEats | PulseHome | PulseMart | Winner |
|---|---|---|---|---|
| F1 ratio of sums | 1.750 | 2.000 | 2.300 | PulseMart |
| F2 mean of per-transaction ratios | 1.750 | 2.000 | 2.300 | PulseMart |
| F3 median of per-transaction ratios | 1.750 | 2.000 | 2.300 | PulseMart |
| F4 mean of per-member ratios | 1.750 | 2.000 | 2.300 | PulseMart |
| F5 mean points per transaction | 114.9 | 132.1 | 151.0 | PulseMart |
| F6 total points issued | 7.33M | 8.46M | 9.75M | PulseMart |
| F7 points per member | 320 | 370 | 425 | PulseMart |
| F8 grouped by **member** brand (wrong join key) | 1.787 | 2.002 | 2.261 | PulseMart |

I also ruled out the two obvious confounds. Earn rates are **identical across all four
tiers** (no tier-mix effect), and average basket size is **$65.64–$66.04** across all three
brands (no basket-mix effect). The brands differ in rate, in nothing else.

**I could not construct any framing, defensible or otherwise, that reproduces marketing's
claim.** That matters: it means this is not a methodology dispute. Their number does not
come from this data.

### Does the metric measure *generosity*? **Not on its own — and this is the real flaw.**

Points per dollar ranks generosity **only if a point is worth the same at every brand**.
Nothing in this data states a redemption value: there is no rewards catalogue, no
redemption dollar amount, and `transaction_type` has a single value (`purchase`), so
redemptions appear only as a points column inside purchase rows.

So rather than leaving that as an unfalsifiable objection, I quantified it:

> **For marketing to be right, a PulseEats point must be worth at least 1.31× a PulseMart
> point** (and ≥1.14× a PulseHome point).

That converts "the framing is untrustworthy" into a specific claim someone can go and check
against the rewards catalogue in ten minutes.

**And there is weak evidence pointing their way.** If redemptions buy broadly similar
rewards, a brand needing *fewer* points per redemption has more valuable points:

| Brand | Avg points per redemption | Implied point value vs PulseEats |
|---|---|---|
| PulseEats | 82.3 | 1.00 |
| PulseHome | 89.4 | 1.086 |
| PulseMart | 96.5 | **1.172** |

A PulseEats point looks like it may be worth **~1.17×** a PulseMart point — the direction
marketing's argument needs. **But they need 1.31×, and 1.17 falls short.** Adjusting for
it, PulseMart still leads by roughly 12% rather than 31%.

This is the most interesting result in the part: **the objection to the metric is real and
closes most of the gap, but not enough to change the answer.**

---

## Confidence

| Claim | Confidence | Basis |
|---|---|---|
| Earn rates are 1.75 / 2.00 / 2.30 | **Very high** | Deterministic; SD = 0.009; stable across 8 framings, 4 tiers, and basket size |
| Marketing's claim is not supported by this data | **Very high** | PulseEats ranks last on all 8 framings; no reconstruction reproduces it |
| **PulseMart rewards a dollar most generously** | **High** | Holds on every framing; survives the point-value adjustment the data supports |
| The *size* of the gap (31%) | **Moderate** | Assumes equal point value. Best available evidence narrows it to ~12% |
| PulseMart is most generous *in delivered customer value* | **Moderate** | Depends on redemption economics the data does not contain |

**What would change my mind:** a rewards catalogue showing a PulseEats point redeems for
≥1.31× a PulseMart point. That is the one piece of evidence that would flip this, and it is
the first thing I would ask marketing for — because if they have it, their claim is right
for a reason they have not stated.

**What I would tell marketing:** don't run the campaign on this claim. Not because the
framing is debatable, but because **the brand you are calling most generous is measurably
the least generous on every version of your own metric.** If the claim rests on point
values rather than earn rates, say so explicitly and show the catalogue — and note that
PulseMart would still lead on the numbers available today.

## Output index

| File | Contents |
|---|---|
| `g1_naive.csv` / `g2_clean.csv` | The inverted vs correct ranking |
| `g3_contamination.csv` | Ranking at each cleaning step — where it flips |
| `g4_sentinel_impact.csv` | The 15 rows and their denominator inflation |
| `g5_framings.csv` | Eight framings, all won by PulseMart |
| `g6_tier_confound.csv`, `g7_basket_confound.csv` | Confounds ruled out |
| `g8_point_utility_proxy.csv` | Redemption behaviour by brand |
| `g9_breakeven.csv` | What must be true for marketing to be right |
| `g10_redemption_size_signal.csv` | Weak evidence on relative point value |
