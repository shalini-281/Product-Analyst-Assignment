# Part 5 — Decision Log

_Stakeholder Communication_

## Key decisions (and why)

- **Wrote for two audiences at once**, because the brief says it will be forwarded as-is.
  The PM needs to act on it; the client needs to not be alarmed. Every other decision
  follows from that constraint.
- **Framed as an added safeguard, not a discovered defect.** *"These checks used to run
  after the scores went out — now they run before"* is fully true, explains the delay, and
  volunteers no fault. The highest-stakes sentence in the part.
- **Led with the concrete impact** — Wednesday instead of Monday — in line two, because a
  forwarded message gets about five seconds of attention.
- **Justified the delay in business cost**, not data-quality language: a campaign aimed at
  members who never left spends budget and irritates good customers.
- **Explicitly listed what does not change.** Most of the reply thread a delay notice
  generates is scope questions; answering them up front prevents it.
- **No apology.** The trade-off was correct. Apologising invites scrutiny of a good
  decision and frames us as a vendor managing a complaint.
- **144 words** — inside the ~150 brief, and short enough to read on a phone without
  scrolling, which is how a forwarded Slack message is actually consumed.
- **Named the tension in the write-up rather than hiding it.** The framing is a choice
  about emphasis and it deserves to be defended openly, including what I would say if the
  PM asked directly whether we found problems.

## Alternatives considered and rejected

- **Explaining what we actually found** — the corrupted batch, the 2,988 orphan
  transactions, the duplicate loads. Rejected for a *forwardable* message: true, but a
  client cannot calibrate whether 2,988 is catastrophic or trivial, and the message would
  create a larger conversation than the delay warrants. Available immediately if asked.
- **Apologising for the delay.** Rejected — it reframes a deliberate improvement as a
  failure and invites "what went wrong?"
- **Promising to shorten the delay later.** Rejected — never commit to a future improvement
  in a message that will be quoted back at you.
- **Naming the brand or source system responsible.** Rejected — in a forwarded message that
  turns an internal engineering issue into a procurement conversation.
- **A bulleted "what changed / why / when" structure.** Rejected — bullets read as an
  internal status update. Prose reads as a person telling a colleague something, which is
  the right register for something a client will see.
- **Leading with the reason before the impact.** Rejected — it buries the one fact the PM
  must be able to act on beneath context they may not read.

## Where an AI suggestion was wrong / incomplete, and how I caught it

- **The first draft opened with the cause, not the consequence** — a paragraph about
  improved validation before mentioning the delay. Caught it by asking what a PM does with
  this message: they forward it and answer "so when do I get my scores?" That answer has to
  be in the first two lines.
- **The first draft said "we identified several data quality issues and have corrected
  them."** Technically accurate and quietly damaging: forwarded to a client, it reads as
  *the scores you've been acting on were wrong.* Caught it by re-reading the message as the
  client rather than as the PM — which is exactly what the brief's "forward as-is" clause is
  testing. Rewrote to describe the change in check *timing*, which is equally true and does
  not put past deliverables in question.
- **The draft used "data quality checks" and "validation layer" freely.** Both are jargon
  to a non-technical reader. Replaced with "confirms each brand's data is complete."
- **Landed at 210 words on the first pass.** Cutting to 144 forced a useful decision: the
  paragraph that had to go was the one explaining *how* the checks work, which no reader in
  either audience needs. The length constraint improved the message rather than truncating
  it.
- **Nearly wrote "minimal impact to your workflow."** Reassurance the writer cannot verify
  — a two-day delay may well be significant to a campaign calendar I cannot see. Replaced
  with the specific, checkable "same scores, same format, same place."
