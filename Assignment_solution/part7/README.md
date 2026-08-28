# Part 7 — Pick the win-back campaign list

**Section:** Analytical Reasoning · **Status:** Complete

**The ask.** Choose ~20 members for a win-back campaign — valuable, slipping away, and reachable — and defend the selection criteria, the exclusions, and the judgment calls.

## The central judgment: "slipping away" is relative, not absolute

Part 2 established that the median member buys every **204 days**. So the obvious rule —
*"no purchase in 90 days"* — is worse than useless here:

- It flags **23,911 members, 48% of the base**. That is not a target list, it is a mailing list.
- It simultaneously **misses** a genuinely at-risk weekly shopper silent for 60 days.

Both errors cost money: the first wastes budget on people who never left, the second misses
the people you could still save. So the signal is each member's deviation from **their own**
rhythm:

```
overdue_ratio = days_since_last_purchase / personal_average_gap
```

A member who normally buys every 30 days and has been silent 90 days (ratio 3.0) is in
trouble. A member who normally buys every 300 days and has been silent 90 days (ratio 0.3)
is behaving completely normally. **A fixed threshold cannot tell these apart; the ratio
can.**

## Definitions

| Concept | Measure | Why this one |
|---|---|---|
| **Valuable** | Annualised spend *while active* = `lifetime_spend / (active_span / 365)` | Trailing-year spend scores every lapsed member near zero — it would systematically deprioritise exactly the people we are targeting |
| **Slipping away** | `overdue_ratio` between **1.5 and 4** | Past their own rhythm, but not so far gone they are unrecoverable |
| **Actionable** | ≥4 purchases, ≥365-day active span, clean identity, unredeemed balance | A campaign needs a real prior relationship and something concrete to offer |

## Exclusion funnel

Every filter is counted, so the list is auditable rather than asserted:

| Step | Members remaining |
|---|---|
| 0. Members with any transaction | 52,984 |
| 1. − orphans with no profile (DQ-06) | 49,996 |
| 2. − fewer than 4 purchases | 27,078 |
| 3. − active span under 365 days | 19,860 |
| 4. − not yet overdue (ratio < 1.5) | 4,780 |
| 5. − likely unrecoverable (ratio > 4) | 4,093 |
| 6. − gone more than 540 days | 3,340 |
| 7. − silent less than 60 days (too early to intervene) | 3,340 |
| 8. − conflicted profile (DQ-03) | 3,331 |
| 9. − shared email (DQ-12) | 3,329 |
| **Final eligible pool** | **3,329** → top 20 by score |

**Three exclusions come straight from Part 1**, and each would otherwise cause a real
operational failure:

- **Orphans (2,988)** — no profile row means no email. They cannot be contacted, so including
  them would silently shrink a 20-person campaign.
- **Conflicted profiles (DQ-03)** — two contradictory tiers with no `updated_at` to
  arbitrate. Addressing someone as Gold when the other record says Bronze is worse than not
  writing.
- **Shared emails (DQ-12)** — 20 emails span multiple `member_id`s. Two "different" members
  can be one person, who would receive the same win-back offer twice.

## Ranking

```sql
winback_score = annualised_spend * (1 - 0.4 * (days_since_last - 60) / 480.0)
```

Value at risk, with a mild recency discount because response rates decay with absolute
silence. The decay is capped at 40% so it tilts the ranking without overturning it — I did
not want a slightly-fresher mid-value member outranking a far more valuable one.

---

## The list

20 members, `output/wb_target_list.csv`. Selected against the base:

| | Selected 20 | Eligible pool | All members |
|---|---|---|---|
| Annualised spend | **$1,772** | $285 | $280 |
| Lifetime spend | **$1,985** | $457 | $249 |
| **Points balance** | **3,948** | 849 | 455 |
| Days since last purchase | 224 | 331 | 184 |
| Overdue ratio | 2.74 | 2.22 | 1.90 |
| Active span | 411 days | 700 | 491 |

**6.3× the annualised spend and 8.7× the points balance of the average member.**

### The campaign writes itself

Every selected member has a large **unredeemed points balance — averaging 3,948 points**,
and almost none has ever redeemed. That is the offer: *"You have 3,948 points waiting."*
No discount required, no margin sacrificed, and it reactivates a liability the business is
already carrying (Part 8). A win-back list where the incentive is already sitting in the
member's account is a materially cheaper campaign than one needing a discount.

### Composition

| Dimension | Split |
|---|---|
| Brand | PulseHome 13 · PulseEats 4 · PulseMart 3 |
| Country | IN 10 · US 6 · AE 2 · SG 1 · GB 1 |
| Tier | Bronze 9 · Silver 5 · Gold 4 · Platinum 2 |

Two things to flag honestly:

**PulseHome is 13 of 20** against an expected ~7. I did *not* impose brand quotas — value
should drive selection, and forcing balance would mean dropping more valuable members for
less valuable ones. But a campaign landing 65% on one brand needs that brand's buy-in
before it ships, and if CRM wants portfolio balance the right move is three lists of ~7,
not one list rebalanced after the fact.

**Bronze outnumbers Platinum 9 to 2** — the highest-value members by actual spend are mostly
*low* tier. That directly corroborates Part 2's finding that tier is inert in this data
(churn flat at 58.6–60.0% across the ladder, spend flat at ~$283). **Targeting by tier — the
obvious CRM instinct — would have missed most of this list.**

## Judgment calls I made

| Call | Reasoning | What I gave up |
|---|---|---|
| Ratio, not fixed threshold | The 90-day rule flags 48% of the base | Harder to explain to stakeholders |
| Upper bound at ratio 4 | Past ~4× their own rhythm, a member has changed circumstances, not preferences. Budget is better spent on the recoverable | Some genuinely winnable members excluded |
| Lower bound at 60 days silent | Contacting someone mid-normal-gap is spam, and risks *causing* the churn | Misses very-high-frequency members |
| Require ≥365-day active span | See below — this is the correction that mattered most | Excludes lapsed new members |
| No brand/tier quotas | Value should drive selection | 65% brand concentration |
| Rank by value, not by predicted win-back probability | No campaign response history exists in the data. A propensity model with no outcome variable would be fabricated precision | The list optimises value at risk, not expected recovery |

## The error I caught

**My first list was an artifact of the value measure, not a selection of valuable members.**

The initial rule required only 3 purchases with no constraint on how long the member had
been active. Because annualised spend divides by active span, a member with 3 purchases in
4 months gets extrapolated into a "$3,115/year customer". The result:

| Active span | Members | Avg annualised spend | Avg lifetime spend |
|---|---|---|---|
| < 180 days | 639 | **$742** | $273 |
| 180–365 days | 1,640 | $487 | $357 |
| 1–2 years | 2,286 | $345 | $456 |
| 2 years+ | 1,284 | **$156** | $409 |

Annualised spend runs **inversely** to active span — a pure artifact. The first list averaged
a **197-day** active span against **509** for the pool: it was ranking *short spans*, not
value. I caught it by checking whether the selected members differed from the pool on
anything I had not intended to select on.

The fix — requiring a ≥365-day demonstrated relationship — is also the right *business* rule
independently: **three purchases in four months followed by silence is a failed onboarding**,
which needs a different campaign and a different offer than a member who shopped steadily
for a year and then stopped.

## Confidence, and what would improve it

| | |
|---|---|
| **These 20 are high-value and genuinely off their rhythm** | **High** — 6.3× spend, ratio 2.74, both directly measured |
| **A campaign will win them back** | **Low** — nothing in this data supports a response-rate estimate |

That gap is the honest limit of the exercise. There is **no campaign history, no response
data, and no control group**, so "worth winning back" is measurable and "will come back" is
not. What I would do next, in order: **hold out a random 20% of the eligible pool as a
control** so the next campaign can measure lift rather than repeating the guess; **A/B the
points-balance reminder against a discount**, since the former costs nothing; and check the
PulseHome concentration with the brand team before sending.

## Output index

| File | Contents |
|---|---|
| `wb_target_list.csv` | **The 20 members**, with every input to the decision |
| `wb_exclusion_funnel.csv` | Auditable filter chain |
| `wb_list_vs_base.csv` | Selected vs pool vs base |
| `wb_list_composition.csv` | Brand / country / tier split |
| `wb_vs_naive_rule.csv` | Personal-rhythm vs fixed 90-day rule |
| `eligible_pool.csv` | All 3,329 eligible, for reruns at other list sizes |
