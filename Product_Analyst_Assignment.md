

## Before you start

- **AI tools are fully allowed** — ChatGPT, Claude, Copilot, whatever you normally use. We are not testing whether you can write every line of SQL from memory.
- We *are* testing how you think: how you validate output, catch problems in messy real-world data, make and justify decisions, and communicate them. Two candidates could submit similar code and score very differently based on the reasoning behind it.
- **Budget: ~4 hours for Section 1, plus a hard ~60 minutes for Section 2.** Timebox Section 2 deliberately — if you run out of time on a part, tell us what you'd have done with more. We'd rather see clear thinking on part of it than a rushed attempt at all of it.
- Scenario and data below are synthetic, built for this exercise. Any resemblance to real systems is coincidental.

**The assignment has two sections:**
- **Section 1 — Pipeline & Modelling Track** (Parts 1–5): build the churn-feature pipeline end to end.
- **Section 2 — Analytical Reasoning Track** (Parts 6–8): three short, independent problems. Each tests a *different* skill, and each looks simpler than it is. What we're scoring is whether you frame the real question, validate your own numbers, and are honest about your confidence — not whether you produce a tidy answer fast.

**Deliverables:** one written response covering all parts (markdown, doc, or notebook — your choice), plus any code you wrote. Keep it readable over polished.

**Data files (same two files feed both sections):**
- `members.csv` — member profile data
- `transactions.csv` — transaction-level activity

These are **raw exports as they landed from source systems** — nobody has cleaned them yet. That's your job to figure out.

---
---

# SECTION 1 — Pipeline & Modelling Track

## Part 1 — Data Quality & Governance Audit

Review both files. Produce a short **data quality report** as a table with these columns:

| Issue | Evidence (how you found it) | Likely root cause | Fix | Prevention control (so it doesn't happen again) |

We're not looking for an exhaustive list of every possible check — we're looking for the issues that would actually break a churn model or a governance audit, and clear evidence you *looked at the data* rather than described generic "data cleaning best practices."

---

## Part 2 — Feature Engineering for a Churn Model

Using SQL and/or Python, build a **member-level feature table** with at least 8 features useful for predicting 90-day churn (think recency, frequency, monetary value, tier behavior, engagement trend, redemption behavior, etc.).

Requirements:
- Show your actual query/code, not just a feature list.
- For **at least 3** of the data quality issues you found in Part 1, explicitly state how you handled them in this feature table (drop, impute, flag, dedup, etc.) and why you chose that approach over the alternatives.
- Note any feature you'd be nervous shipping to production as-is, and why.

---

## Part 3 — Pipeline Design

This currently works as a one-off CSV pull. Assume it now needs to run **daily, across 20 brands, at ~50x current volume**, feeding a feature store that an ML model reads from every morning.

Write a short design doc (diagram optional but welcome) covering:
- Ingestion approach and how you'd guarantee idempotency (no duplicate processing on replay/retry)
- How you'd detect and handle schema drift from source systems
- A data quality **SLA and alerting** approach — what gets checked automatically before data is considered "safe to serve"
- PII handling (email, name, birth date) — what you'd mask/tokenize and where in the pipeline
- Your orchestration tool choice and why (Airflow, Databricks Workflows, dbt, etc. — pick one, justify it, don't just list options)

---

## Part 4 — Production Incident (no new data — this is a thinking exercise)

**Scenario:** It's Monday morning. Yesterday's feature refresh shows `engagement_score` dropped to 0 for ~40% of members in the PulseEats brand only, for the same 6-day window. A stakeholder is asking in Slack whether this is a real drop in engagement they should escalate to the brand team.

Walk through, step by step:
1. What you'd check first, and in what order
2. What specific queries or tools you'd use at each step
3. Your top 3 hypotheses, ranked by likelihood, with the reasoning behind the ranking

---

## Part 5 — Stakeholder Communication

Write a **~150-word Slack message** to a non-technical product manager, explaining why churn scores will now be delayed by 2 days following the data quality fixes you designed in Part 3. Assume they will forward this message as-is to a client.

---
---

# SECTION 2 — Analytical Reasoning Track

**~60 minutes total.** Three independent problems, each testing a different skill: spotting contamination (Part 6), turning a fuzzy business goal into a defensible decision (Part 7), and reasoning to a number when the data doesn't hand you one (Part 8). You may use AI freely. For each, show your working and **state your assumptions and confidence explicitly** — a defensible answer with caveats beats a confident answer you can't stand behind.

## Part 6 — Which brand is actually the most generous?

Marketing is running a campaign built on the claim that **PulseEats is the most generous brand** because it "gives the most points per dollar spent." A skeptical analyst on your team thinks that's wrong.

Settle it with the data: **which brand actually rewards a real dollar of spend most generously?** Is marketing's claim correct, and is the way they've framed "points per dollar" trustworthy? Show what you had to clean or exclude to trust your answer, and how confident you are.

---

## Part 7 — Pick the win-back campaign list

The CRM team has budget to run a **win-back campaign for 20 members** — people who were valuable but look like they're slipping away, and who a targeted offer might bring back. They've asked you to hand them the list.

Using the data, **choose the ~20 members you'd target and defend your selection criteria.** There's no single correct list — we're interested in how you define "worth winning back" and "slipping away," what you decide to exclude and why, and whether the members you pick are ones a campaign could actually work on. Be explicit about the judgment calls you made.

---

## Part 8 — What's the outstanding points liability?

Finance needs to put a number on the balance sheet: the **outstanding points liability** — the monetary value of points members have *earned but not yet redeemed*.

Produce a **defensible dollar figure** from the data. State every assumption you had to make and why. If anything in the data makes you distrust your own number, say so — a figure you can defend with caveats is worth far more to us than a confident number you can't.

---
---

## A note on how you work (applies to both sections)

Wherever you used AI tools, we'd like a short **decision log** alongside your answers — a few bullets per part is enough:
- Key decisions you made and why
- Alternatives you considered and rejected
- Any point where an AI tool's first suggestion was wrong, incomplete, or something you had to correct — and how you caught it

This isn't a trap — using AI well and catching its mistakes is exactly the skill we're hiring for. We just want to see the thinking, not only the output.
