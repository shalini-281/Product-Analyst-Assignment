# Part 7 — Decision Log

_Pick the win-back campaign list_

## Key decisions (and why)

- **Measured lapse relative to each member's own rhythm.** With a median inter-purchase gap
  of 204 days, a fixed 90-day rule flags 23,911 members — 48% of the base. The overdue ratio
  distinguishes a weekly shopper silent for 90 days from an annual shopper silent for 90 days;
  a threshold cannot.
- **Valued members on annualised spend *while active*, not trailing-year spend.** Trailing-year
  spend scores every lapsed member near zero, which would systematically deprioritise the exact
  population the campaign exists to reach.
- **Bounded the ratio at both ends.** Below 1.5 they have not actually lapsed; above 4 they are
  probably gone. Budget spent outside that band is spent on people who did not need the offer or
  will not answer it.
- **Counted every exclusion in a funnel.** "I excluded orphans" is a claim; a funnel showing
  52,984 → 3,329 is auditable, and it makes the cost of each filter visible.
- **Carried three Part 1 findings into operational exclusions** — orphans cannot be emailed,
  conflicted profiles cannot be addressed correctly, shared emails would double-contact one
  person. Each is a campaign failure, not a data-quality footnote.
- **Ranked by value at risk rather than predicted response.** There is no campaign history in
  this data, so a propensity model would be fabricated precision dressed as rigour.
- **Declined to impose brand or tier quotas**, but flagged the 65% PulseHome concentration
  rather than letting CRM discover it after approval.
- **Separated confidence on "valuable and lapsing" (high, measured) from "will come back"
  (low, unmeasurable here).** Reporting one number for both would overstate the weaker half.

## Alternatives considered and rejected

- **Fixed recency threshold (90 or 180 days).** Rejected — flags half the base and misses
  high-frequency members. This is the single most consequential decision in the part.
- **Targeting by tier.** Rejected, and the data explains why: Bronze outnumbers Platinum 9 to 2
  in the final list. Part 2 showed tier is inert here — the obvious CRM instinct would have
  missed most of these members.
- **RFM scoring with equal weights.** Rejected — the R in a standard RFM is absolute recency,
  which is precisely the measure this population breaks.
- **Ranking on lifetime spend.** Rejected as biased toward tenure: a five-year member with
  modest annual spend outranks a one-year member spending twice as fast.
- **Building a win-back propensity model.** Rejected — no response outcome exists to train on.
- **Including members with huge overdue ratios** (the "most churned"). Rejected: most likely
  moved, switched, or died. The campaign should target the recoverable, not the most lapsed.
- **Enforcing brand balance in the top 20.** Rejected — it would drop higher-value members for
  lower-value ones to satisfy an aesthetic. Flagged for CRM instead, with the better fix
  (three per-brand lists) named.

## Where an AI suggestion was wrong / incomplete, and how I caught it

- **The first list was an artifact of my own value metric.** Requiring only 3 purchases with no
  minimum active span meant annualised spend divided by a short window — 3 purchases in 4 months
  extrapolated to "$3,115/year". The selected 20 averaged a 197-day active span against 509 for
  the pool: the ranking was selecting *short spans*, not value. Caught it by asking whether the
  selected members differed from the pool on anything I had **not** intended to select on —
  which is the check worth running on any ranked list. Confirmed with a span-band table showing
  annualised spend running inversely to span ($742 under 180 days vs $156 at 2y+). The fix,
  requiring a year-long relationship, is also the better business rule: a brief burst followed
  by silence is a failed onboarding, not a lapsed loyalist.
- **The initial approach reached for RFM** because it is the standard loyalty answer. Its
  recency component is absolute, which is exactly what this population breaks. Adapting the
  familiar framework would have imported the bug the framework does not know it has.
- **Nearly ranked on lifetime spend** — intuitive and tenure-biased. Annualising corrects it, but
  only once the span floor makes the annualisation stable, so the two decisions are coupled and I
  initially made only one of them.
- **Nearly omitted the points-balance observation.** I had it as a scoring input and missed that
  it is the campaign's *content*: these members average 3,948 unredeemed points against 455 for
  the base, so the offer costs nothing and draws down an existing liability. The most useful
  sentence in the answer nearly stayed a column in a CSV.
- **Almost reported one confidence number for the whole part.** "Valuable and lapsing" is
  measured; "will respond" is not supported by anything here. Splitting them is what makes the
  caveat honest rather than decorative.
