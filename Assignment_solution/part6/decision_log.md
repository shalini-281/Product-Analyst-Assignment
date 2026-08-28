# Part 6 — Decision Log

_Which brand is actually the most generous?_

## Key decisions (and why)

- **Computed the naive answer first, deliberately.** The interesting finding is not the
  clean number — it is that the contamination inverts the ranking. Without the raw
  calculation there is nothing to compare against and the 15 rows look like housekeeping.
- **Attributed the contamination per brand.** "I cleaned 15 rows" is a step; "12 of them are
  PulseMart and they inflate its denominator by 157.5%" is an explanation.
- **Tested eight framings rather than defending one.** The question asks whether the framing
  is trustworthy. A single number cannot answer that; a stability analysis can. All eight
  agreeing is much stronger evidence than picking the "right" one.
- **Ruled out tier and basket confounds explicitly.** Earn-rate differences could have been
  a mix effect. They are not, and checking took two queries.
- **Used transaction brand, not member brand** — and included the wrong-key version as
  framing F8 to show it does not rescue the claim either. With 9.3% cross-brand shopping
  this is a live trap, not a hypothetical.
- **Converted the point-value objection into a break-even multiple.** "Points per dollar
  ignores point value" is unfalsifiable and easy to wave away. "A PulseEats point must be
  worth ≥1.31× a PulseMart point" is checkable against a rewards catalogue.
- **Reported the evidence that favours marketing.** The redemption-size signal points their
  way. It falls short — 1.17 against the 1.31 needed — but suppressing it would make the
  answer less honest and less useful.
- **Separated confidence by claim.** Very high that PulseMart leads; moderate on the size of
  the gap. Collapsing those into one number would overstate the weaker half.

## Alternatives considered and rejected

- **Reporting only the cleaned ranking.** Rejected — correct and much less useful. The
  finding *is* the inversion.
- **Winsorising or capping outliers instead of excluding the 15 rows.** Rejected: these are
  not extreme values, they are non-values. A sentinel of 999999.99 with 119 points is not a
  large purchase to be tamed, it is a corrupt field to be removed.
- **Mean of per-transaction ratios as the headline.** Rejected as the primary — it weights a
  $5 purchase equally with a $500 one. Reported as F2 for robustness; it agrees anyway.
- **Excluding the negative-amount rows.** Rejected — Part 1 showed they are sign errors, not
  refunds, so `abs()` retains real spend that dropping would discard.
- **Declaring the question unanswerable without point values.** Rejected as a cop-out. The
  earn rates are exact, the ranking is stable, and the residual uncertainty can be bounded
  — so the honest answer is a ranking plus a named condition, not a shrug.

## Where an AI suggestion was wrong / incomplete, and how I caught it

- **The first pass computed the clean answer and stopped**, reporting "PulseMart 2.30 is
  most generous, marketing is wrong." True, and it misses the whole point of the exercise.
  Caught it by re-reading the prompt's phrase *"show what you had to clean or exclude to
  trust your answer"* — which only means something if cleaning changed the answer. Going
  back to compute the naive ranking revealed the inversion, which is the actual finding.
- **I initially assumed the contamination would flatter PulseMart**, since a corrupt batch
  is usually a story about inflated numbers. It does the opposite: the junk is in the
  *denominator*, so it makes the most generous brand look like the least. Caught it by
  computing the naive number instead of predicting it. This is the trap the exercise is
  built around, and reasoning from intuition would have walked straight into it.
- **Nearly wrote "points per dollar is a flawed metric because it ignores point value" and
  left it there.** That is a true, unactionable objection. Turning it into a break-even
  multiple made it testable — and then the redemption-size data turned out to have
  something real to say about it, which I would have missed entirely.
- **Assumed a tier confound without checking.** High tiers plausibly earn bonus points, and
  a brand skewed toward Platinum would look generous for the wrong reason. Two queries
  showed rates identical across all four tiers and baskets within $0.40 across brands. Worth
  the two minutes to be able to say "ruled out" rather than "probably fine."
- **Nearly reported the redemption-size signal as supporting my own conclusion**, since
  lower redemption sizes at PulseEats initially read as "PulseEats members have fewer
  points". It is better read as evidence *against* my ranking — fewer points per redemption
  suggests more valuable points. Reversing that reading is what produced the most
  interesting paragraph in the answer.
