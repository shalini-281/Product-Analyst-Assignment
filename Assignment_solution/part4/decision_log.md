# Part 4 — Decision Log

_Production Incident_

## Key decisions (and why)

- **Read the signature before running any query.** Four properties — exact zero not null,
  one brand, one bounded window, ~40% — each independently argue against a behavioural
  cause. That is enough to answer the stakeholder in five minutes with a *provisional*
  answer, which is what they actually need, rather than going quiet for an hour.
- **Answered the Slack thread first.** An unanswered incident thread fills with speculation
  from other people. A holding message with a reasoned lean and an ETA costs two minutes
  and prevents the escalation happening without me.
- **Ordered the triage by hypothesis-space elimination**, not by pipeline order. Step 1
  (is the *other* 60% normal?) is first because it alone separates "subset failure" from
  "distribution shift" — the difference between a bug and a business event.
- **Made the exact-zero-vs-NULL distinction the lead evidence.** It is the single most
  informative bit in the whole scenario: zero is a value someone *chose*, and the choice is
  almost always a `COALESCE` on a failed join.
- **Ranked the stakeholder's own hypothesis explicitly, and last.** Omitting it would read
  as dodging the question. Naming it at <5% *with reasons* answers them directly.
- **Stated falsification criteria** — what would make me change the ranking. A ranked list
  with no conditions attached is an opinion; with them it is a test.
- **Separated "the feed failed" from "the code turned missing into zero."** The second is
  the more valuable finding: the feed will fail again, and next time the pipeline should
  say *I don't know* rather than *it's zero*.

## Alternatives considered and rejected

- **Escalating to the brand team immediately.** Rejected — the signature is too obviously
  structural. A false escalation costs the brand team's time and my credibility for the
  next one, which matters more than being fast once.
- **Saying nothing until certain.** Rejected — silence on a live thread is how a
  speculative answer becomes the accepted one.
- **Starting from pipeline logs.** Tempting, and it is where I would *want* to start, but
  logs tell you what the pipeline did, not whether the output is wrong. Characterising the
  anomaly first means the logs get read with a specific question in mind.
- **Checking every feature for the same pattern first.** Broader, and slower. Better done
  at step 4 once the mechanism is known — otherwise it produces a wide, undirected survey.
- **Treating the 6-day window as noise.** Rejected — a bounded window has two edges, and
  both are evidence. Something started it and something stopped it, which is why Step 5
  correlates against the deploy log.

## Where an AI suggestion was wrong / incomplete, and how I caught it

- **The first triage plan started with "check the pipeline logs and recent deployments."**
  That is the standard incident runbook and it is subtly wrong here: it assumes the
  conclusion (that it is a pipeline problem) before testing it. If the anomaly *were* a
  real drop, an hour would go into logs that all look fine. Reordered so Step 1 measures
  whether the unaffected 60% moved — the one check that separates a bug from a business
  event before committing to either branch.
- **Nearly ranked "genuine engagement drop" second** on the reasoning that one should take
  the stakeholder's hypothesis seriously. Taking it seriously means *testing* it, not
  inflating its probability. The four signature properties argue against it, and the honest
  ranking is last — with the specific evidence that would promote it.
- **The initial hypothesis list treated "app tracking break" as a business event.** It is
  not. Even if H3 is correct, engagement did not fall — our ability to observe it did, and
  the answer to "should we escalate to the brand team as a retention risk" is still no.
  Worth separating, because the two lead to completely different follow-up actions.
- **Missed the `COALESCE` point on the first pass**, writing the incident up as purely a
  feed-delivery failure. Re-reading my own Step 1 — *why zero and not null?* — surfaced it:
  the null-to-zero conversion is a design defect independent of whichever hypothesis is
  correct, and it is the part most likely to recur. The prevention section is stronger for
  naming both.
- **Nearly forgot the downstream consequence.** Finding the bug is not closing the
  incident: members scored 0 may have been targeted or suppressed by a live campaign. That
  business impact outlives the fix and is the thing the stakeholder will actually be asked
  about.
