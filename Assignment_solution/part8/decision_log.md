# Part 8 — Decision Log

_What's the outstanding points liability?_

## Key decisions (and why)

- **Separated the measured component from the assumed ones, structurally.** 23.2M outstanding
  points is near-exact; the dollar value is two assumptions stacked on top. Presenting one
  number without that split would imply precision that does not exist.
- **Tested breakage rather than assuming an industry default.** Whether 9.32% observed
  redemption means "young programme" or "nobody redeems" changes the answer by ~10×. A cohort
  comparison answers it with data instead of convention.
- **Anchored point value to the earn rate.** $0.01/point implies 1.75–2.30% back, which is
  normal for retail loyalty. That reasoning is what separates a defensible assumption from a
  round number picked because it is round.
- **Chose 25% ultimate redemption deliberately above the ~10% the data shows.** Observed
  redemption is a floor (redemptions are only visible inside purchase rows), no expiry policy
  is known, and a balance-sheet liability should not be understated. Stated as a judgement,
  not dressed up as a finding.
- **Made the sensitivity grid the real deliverable.** The 5×5 table spans $17K–$347K. Finance
  can pick a cell against their own accounting policy; a single number invites false confidence.
- **Included orphan members' 388,681 points.** The obligation exists regardless of whether we
  can identify the member. Excluding them would understate the liability, which is the wrong
  direction for prudence.
- **Disclosed how much of the figure rests on my own Part 1 repairs** (~2%, partly
  self-cancelling). If a repair decision were wrong, the liability moves — that belongs in the
  disclosure, not in a footnote nobody reads.
- **Named the one question that could remove a third of the number** — the expiry policy —
  rather than burying it among caveats.

## Alternatives considered and rejected

- **Reporting gross outstanding points only, no dollar figure.** Rejected — Finance asked for
  a number for the balance sheet. "It depends" is not an answer; a number with a stated range
  is.
- **Assuming 100% redemption (no breakage).** Rejected — it triples the figure to $231,551 and
  contradicts the cohort evidence. It is the "safe" choice that is safely wrong.
- **Using a generic 20–30% industry breakage rate without testing.** Rejected: it happens to
  land near my answer, which is exactly why it needed testing rather than borrowing. Arriving
  at the right number for no reason is not the same as being right.
- **Excluding dormant members' balances.** Rejected — dormancy is not expiry. Without a stated
  expiry policy those points remain claimable, so they stay in the liability with the
  concentration disclosed instead.
- **Excluding orphan members.** Rejected — understating a liability because the counterparty
  is hard to identify is the wrong direction.
- **A single blended point value across brands.** Kept for the headline but flagged as a
  weakness: earn rates differ 1.75 / 2.00 / 2.30, and if point values differ too, the blend is
  wrong. Per-brand balances are reported so the split can be redone.

## Where an AI suggestion was wrong / incomplete, and how I caught it

- **The first version computed `earned − redeemed × $0.01` and called that the liability.**
  That is the gross figure, $231,551, and it assumes every point will be redeemed — an
  assumption made silently by not making it. Caught it by asking what the 9.32% observed
  redemption rate actually implies, which turned "one number" into "two assumptions and a
  sensitivity grid" and changed the answer by 4×.
- **My initial breakage assumption was 35%**, taken from general retail-loyalty knowledge
  rather than from this dataset. When I ran the cohort test and found redemption flat at
  8–10% from a 4.8-year-old cohort to a 0.2-year-old one, 35% was clearly too generous.
  Revised to 25% — still above the data, but for stated reasons (observed redemption is a
  floor, no expiry known, prudence) rather than by convention.
- **I nearly presented the cohort test as conclusive.** It is not: cohorts are defined by first
  purchase but members keep earning, so a 2021 member's balance contains 2026 points that have
  had no time to be redeemed. That dilution flattens the curve artificially. Caught it while
  writing up the method — the act of explaining *why* the test works exposed why it partly
  does not. The 63%-never-redeemed statistic is immune to that effect, which is why it now
  carries the argument instead.
- **Nearly omitted the expiry question entirely** because the data has no expiry field. Absence
  of a field is not absence of a policy — and if points expire after 24 months, roughly a third
  of this liability is not a liability. The most important thing in this part is a question I
  cannot answer from the data, which is worth more to Finance than the number itself.
- **The runner initially wrote each output twice** under two filenames, from a leftover
  formatting expression. Caught it on directory listing; harmless, but a duplicated artefact in
  a deliverable invites the reader to wonder which one is authoritative.
