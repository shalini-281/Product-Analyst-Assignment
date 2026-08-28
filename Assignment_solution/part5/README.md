# Part 5 — Stakeholder Communication

**Section:** Pipeline & Modelling · **Status:** Complete · *(writing exercise — no code)*

**The ask.** A ~150-word Slack message to a non-technical PM explaining why churn scores are now 2 days later, following the Part 3 fixes. **It will be forwarded as-is to a client.**

## The message

> Hi [Name] — quick heads-up on churn scores.
>
> From next week they'll reach you two days later than usual: **Wednesday morning instead
> of Monday**.
>
> We've added an automated check that confirms each brand's data is complete before it
> reaches the scoring model. These checks used to run after the scores went out — now they
> run before, so anything that needs a closer look is caught before it reaches you rather
> than after you've acted on it.
>
> Those two days buy confidence that the members on your list are the right ones. When a
> data feed arrives incomplete, active members can look inactive — and a win-back campaign
> aimed at the wrong people spends budget and irritates good customers.
>
> Nothing else changes: same scores, same format, same place. Previous scores are
> unaffected.
>
> First delivery on the new schedule is **[date]**. Happy to walk through it if useful.

---

## Why it's written this way

The brief hides a real constraint in one line: **it will be forwarded as-is to a client.**
That means it has two audiences with different needs and no chance to tailor for either —
the PM needs to understand it, and the client needs to not be alarmed by it. Every choice
below follows from that.

**The change and its impact are in the first two lines.** A forwarded message gets read for
about five seconds before someone decides whether it needs a reply. "Wednesday instead of
Monday" is the fact a PM must be able to act on without reading further.

**No self-incrimination.** The most important sentence in the message is *"These checks used
to run after the scores went out — now they run before."* The honest version of this change
is that we found real defects — a corrupted batch, duplicate transactions, an entire
unloaded source system. But a client reading *"we discovered our data was wrong"* hears
*"the scores I've been acting on were wrong,"* and that is a different, much larger
conversation. The sentence as written is completely true, volunteers no fault, and still
explains the delay. **Framing as an added safeguard rather than a correction is the single
highest-stakes decision in this part.**

**Justified in the client's currency, not ours.** Not "data integrity" or "completeness
thresholds" — *"spends budget and irritates good customers."* A win-back campaign aimed at
someone who never left is the concrete cost of the thing we prevented, and it is a cost the
client already understands.

**States what doesn't change.** "Same scores, same format, same place. Previous scores are
unaffected." Half the anxiety in a delay notice is unasked questions about scope. Answering
them pre-empts the reply thread.

**No apology.** An apology invites the question of what went wrong, and a deliberate
engineering trade-off is not something to be sorry about. The tone is a colleague informing
a colleague — not a vendor managing a complaint.

**A named date and an open door.** "[date]" and "happy to walk through it" give the PM
something concrete to forward and an easy exit if the client pushes back.

## What I deliberately left out

| Left out | Why |
|---|---|
| The specific defects found (corrupted batch, 2,988 orphan transactions, duplicate loads) | True, and alarming out of context. A client cannot calibrate whether 2,988 is a lot |
| Technical vocabulary — *pipeline, feature store, schema, null, gate* | The PM may not know them; the client definitely didn't ask |
| Which brand or system caused it | Naming a source system in a forwarded message is how an internal issue becomes a procurement conversation |
| "We're sorry for the inconvenience" | Invites scrutiny of a decision that was correct |
| A promise to reduce the delay later | Do not commit to a future improvement in a message that will be quoted back |

## The honest tension

There is a real trade here, and it's worth naming rather than pretending the message is
neutral. Framing the change as *added assurance* rather than *found problems* is accurate,
but it is a choice about emphasis, and a client could reasonably feel differently if they
later learned the full detail.

I'd defend it on this basis: **the delay is the fix working, not the failure.** The failure
already happened, silently, every week that unverified data reached the model. The client's
actual exposure went *down* this week. But if the PM asks me directly whether we found
problems, the answer is yes and I'd give them the detail — this message is written to be
forwarded, not to survive that question, and those are different jobs.

See `decision_log.md` for alternatives considered.
