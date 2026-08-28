# Part 8 — What's the outstanding points liability?

**Section:** Analytical Reasoning · **Status:** Complete

**The ask.** A defensible dollar figure for points earned but not yet redeemed, with every assumption stated and every reason to distrust the number.

## The figure

> ## $57,900
> **Central estimate.** Defensible range **$35,000 – $116,000**.
> Gross, before any breakage assumption: **$231,551**.

| | |
|---|---|
| Points earned (cleaned) | 25,534,344 |
| Points redeemed | 2,379,267 |
| **Points outstanding** | **23,155,302** |
| × assumed value per point | $0.010 |
| = gross liability | $231,553 |
| × assumed ultimate redemption | 25% |
| **= net liability** | **$57,888** |

**The points arithmetic is essentially exact. The dollar figure is not**, because it rests
on two numbers the data does not contain. Everything below separates the two.

---

## What is measured vs what is assumed

| Input | Status | Confidence |
|---|---|---|
| 23,155,302 points outstanding | **Measured** — points are deterministic (`round(rate × amount)`, 100% within 1 point) | **Very high** |
| $0.01 value per point | **Assumed** — no rewards catalogue, no redemption dollar value anywhere in the data | **Moderate** |
| 25% ultimate redemption | **Assumed** — inferred from observed behaviour, not stated | **Low–moderate** |

### Assumption 1 — a point is worth $0.01

Nothing in the data states a redemption value. `transaction_type` has a single value
(`purchase`), so redemptions appear only as a points column inside purchase rows — there is
no dollar amount attached to any redemption anywhere.

So I anchored it to the earn rate. At $0.01/point, the brands return:

| Brand | Points per dollar | Effective % back at $0.01 |
|---|---|---|
| PulseEats | 1.75 | **1.75%** |
| PulseHome | 2.00 | **2.00%** |
| PulseMart | 2.30 | **2.30%** |

1.75–2.30% back is squarely inside the normal range for retail loyalty. **That is what makes
$0.01 defensible rather than arbitrary** — at $0.005 the programme returns under 1.2% and
looks stingy for the sector; at $0.015 it returns 2.6–3.5%, which is generous enough that
Finance would already know. It remains an assumption, and the sensitivity grid prices it.

### Assumption 2 — only 25% of outstanding points will ever be redeemed

Only **9.32%** of all points ever issued have been redeemed. Two very different stories fit
that, and they imply liabilities differing by a factor of ten:

- **(a)** the programme is young and points are still accumulating → low breakage, near-full liability
- **(b)** members simply do not redeem → high breakage, the liability is a fraction of gross

**The cohort test separates them.** If redemption were merely slow, older cohorts would show
materially higher cumulative redemption:

| Cohort (first purchase) | Years since joining | Points earned | % redeemed |
|---|---|---|---|
| 2021 | 4.8 | 1,696,463 | **9.74%** |
| 2022 | 4.0 | 3,921,527 | 10.23% |
| 2023 | 3.0 | 4,942,463 | 10.30% |
| 2024 | 2.0 | 6,869,631 | 8.05% |
| 2025 | 1.0 | 5,948,455 | 9.63% |
| 2026 | 0.2 | 2,155,805 | **8.24%** |

**Flat.** A cohort with 4.8 years of opportunity has redeemed 9.74%; a cohort with 0.2 years
has redeemed 8.24%. Points are not being redeemed slowly — **they are mostly not being
redeemed at all.** Story (b).

Corroborated by the cleanest single statistic in this part:

> **63.0% of members (33,399 of 52,984) have never redeemed a single point.**
> They hold **12,572,722 points — 54.3% of the entire liability.**

More than half the balance sheet obligation is owed to people who have never once shown any
intention of claiming it.

**So why assume 25% rather than the ~10% the data shows?** Three reasons, and they pull in
opposite directions:

1. **Observed redemption is a floor, not a measurement.** Redemptions are only visible inside
   purchase rows. A member who redeems without buying is invisible to this dataset entirely.
2. **No expiry policy is present in the data.** If points never expire, a dormant balance
   remains claimable indefinitely and breakage should be assumed lower.
3. **Prudence.** A balance-sheet liability should not be understated. Where the evidence is
   ambiguous, err toward the larger obligation.

**25% sits deliberately above what the data shows and below a generic retail default.** It is
a judgement, not a finding — which is exactly why the sensitivity table below is the real
deliverable.

---

## Sensitivity — the answer is a surface, not a scalar

| Value per point | 15% redeemed | 25% redeemed | 35% redeemed | 50% redeemed | 100% (no breakage) |
|---|---|---|---|---|---|
| $0.0050 | $17,366 | $28,944 | $40,521 | $57,888 | $115,775 |
| $0.0075 | $26,049 | $43,416 | $60,782 | $86,832 | $173,663 |
| **$0.0100** | $34,733 | **$57,888** | $81,043 | $115,775 | $231,551 |
| $0.0125 | $43,416 | $72,360 | $101,303 | $144,719 | $289,438 |
| $0.0150 | $52,099 | $86,832 | $121,564 | $173,663 | $347,326 |

**The full grid spans 20×, from $17K to $347K.** Any single number quoted without this table
implies precision that does not exist. If Finance needs one figure I would give **$57,900**,
and if they need a prudent one for provisioning, **$81,000** (35%).

---

## What makes me distrust my own number

Ordered by how much they could move it.

**1. Both multipliers are assumptions, and they compound.** Being wrong on point value *and*
breakage in the same direction moves the answer by more than 4×. The measured component —
23.2M points — is the only part I would defend without caveats.

*(Outstanding points are summed from per-member balances floored at zero. Five members
show a negative balance totalling 225 points, because redemptions can be recorded against
points earned outside this window. A member cannot owe the programme points, so a negative
balance is a data artefact, not a receivable to net off. The floor moves the total by 225
points — about two cents of liability — and makes the accounting defensible rather than
merely close.)*

**2. The cohort test is diluted, and this is the weakness in my strongest evidence.** Cohorts
are defined by a member's *first* purchase, but members keep earning throughout. A 2021
member's balance includes points earned in 2026 that have had no time to be redeemed, which
suppresses older cohorts' apparent redemption rate and makes the curve look flatter than it
is. Points are not lot-tracked, so a true FIFO burn-down is impossible with this data. **The
flatness is suggestive, not conclusive** — the 63%-never-redeemed figure is the more robust
evidence, because it is immune to this effect.

**3. Redemptions are structurally under-observed.** `transaction_type` has one value, so
redemption is visible only when it accompanies a purchase. Observed redemption is a lower
bound and the liability computed from it is an upper bound. I cannot size this error.

**4. No expiry policy exists in the data.** If points expire after 24 months, most of the
$57,900 is not a liability at all — 15.4% of the balance already sits with members dormant
over a year. **This is a one-question fix and the first thing I would ask Finance.**

**5. Balances are concentrated in members who may never return.**

| Segment | Members | Points outstanding | % of liability |
|---|---|---|---|
| Active (0–90d) | 26,572 | 9,795,828 | 42.3% |
| Slowing (91–365d) | 17,646 | 9,781,157 | 42.2% |
| Dormant (1–2y) | 6,741 | 2,882,746 | 12.4% |
| Likely gone (2y+) | 2,025 | 695,346 | 3.0% |

**6. ~2% of the points rest on Part 1 repairs**, not on source data:

| Source | Points | % of issued |
|---|---|---|
| Imputed where source was NULL (DQ-11) | 200,830 | 0.79% |
| On sign-error rows (DQ-07) | 265,750 | 1.04% |
| Removed with replayed rows (DQ-04) | −253,174 | 0.99% |
| On recovered-amount rows (DQ-02) | 1,787 | 0.01% |

Individually small and partly self-cancelling, but worth disclosing: had the replayed rows
been left in, the liability would be overstated by ~1%.

**7. 388,681 points (1.7%) belong to orphan members with no profile** (DQ-06). **I included
them.** The obligation exists whether or not we can identify who it is owed to — excluding
them would understate the balance sheet, which is the wrong direction for a liability. But it
does mean 1.7% of the figure is owed to members we cannot currently contact or identify.

---

## What I would do before booking this

1. **Get the expiry policy.** One question, and it could remove a third of the number.
2. **Get the rewards catalogue** to replace the $0.01 assumption with a measured redemption
   value — this is the single largest source of uncertainty.
3. **Instrument redemptions as their own transaction type.** The reason breakage is hard to
   estimate is that redemption is only observable as a side effect of purchase. This is a
   tractable fix and it would make next year's figure far more defensible.
4. **Split the estimate by brand** — earn rates differ 1.75 / 2.00 / 2.30, so if point values
   also differ, a single blended rate is wrong. Outstanding balances are PulseMart 8.88M,
   PulseHome 7.66M, PulseEats 6.61M.

**Bottom line for Finance:** book **$57,900**, disclose the range, and note that the estimate
is materially sensitive to an expiry policy that is not visible in the data. I would rather
hand over that sentence than a clean number I could not defend.

## Output index

| File | Contents |
|---|---|
| `l1_gross_points.csv` | The measured 23.2M outstanding |
| `l4_cohort_burndown.csv` | **The breakage test** — redemption flat across cohort age |
| `l6b_never_redeemed.csv` | 63% never redeemed, holding 54.3% of liability |
| `l6_balance_by_dormancy.csv` | Where the balances sit |
| `l7_point_value_anchor.csv` | Why $0.01 is defensible |
| `l8_headline_liability.csv` | The figure with low/high cases |
| `l9_sensitivity.csv` | The 5×5 grid |
| `l10_repair_exposure.csv` | How much rests on Part 1 repairs |
| `l3_orphan_exposure.csv` | Points owed to unidentifiable members |
