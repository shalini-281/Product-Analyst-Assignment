-- Data quality audit. Produces every number quoted in part1/README.md.
--
--   .venv/bin/python Assignment_solution/part1/code/run_audit.py
--
-- A check earns a place here only if it breaks the churn model (corrupts the
-- label, a feature, or a join's row count) or fails a governance audit (exposes
-- PII, breaks identity resolution, blocks traceability). Passing checks are kept
-- too, so this doubles as a regression test rather than a one-off narrative.


-- Every column as VARCHAR, deliberately. A type-sniffing reader coerces the
-- malformed values this audit exists to find: the 1,500 MM/DD/YYYY dates become
-- NULL and the report then says "1,500 nulls" instead of "a second date format" --
-- same count, wrong root cause. The parser has to be ours, and fail-closed.
CREATE OR REPLACE VIEW members_raw AS
SELECT * FROM read_csv('members.csv',      all_varchar = true, header = true);

CREATE OR REPLACE VIEW tx_raw AS
SELECT * FROM read_csv('transactions.csv', all_varchar = true, header = true);


-- Anything not matching a known format stays NULL and is counted, never guessed.
-- MM/DD orientation is proven by ev_slash_date_orientation before it is used here.
CREATE OR REPLACE MACRO parse_ts(d) AS coalesce(
    try_strptime(trim(d), '%Y-%m-%d %H:%M:%S'),
    try_strptime(trim(d), '%Y-%m-%d'),
    try_strptime(trim(d), '%m/%d/%Y')
);

CREATE OR REPLACE MACRO to_num(x) AS try_cast(nullif(trim(x), '') AS DOUBLE);


-- row_fp hashes the RAW strings: it answers "is this row byte-identical to
-- another", which separates a replayed load from a real primary-key collision.
CREATE OR REPLACE VIEW tx AS
SELECT
    transaction_id,
    member_id,
    transaction_date               AS transaction_date_raw,
    parse_ts(transaction_date)     AS transaction_ts,
    amount                         AS amount_raw,
    to_num(amount)                 AS amount,
    to_num(points_earned)          AS points_earned,
    to_num(points_redeemed)        AS points_redeemed,
    channel, brand, transaction_type,
    md5(concat_ws('|', coalesce(member_id,''), coalesce(transaction_date,''),
                       coalesce(amount,''), coalesce(points_earned,''),
                       coalesce(points_redeemed,''), coalesce(channel,''),
                       coalesce(brand,''), coalesce(transaction_type,''))) AS row_fp
FROM tx_raw;

CREATE OR REPLACE TABLE mem AS
SELECT
    member_id, email, first_name, last_name,
    join_date                                  AS join_date_raw,
    try_strptime(trim(join_date), '%Y-%m-%d')  AS join_ts,
    tier, brand, status, country,
    try_strptime(trim(birth_date), '%Y-%m-%d') AS birth_ts,
    md5(concat_ws('|', coalesce(email,''), coalesce(first_name,''),
                       coalesce(last_name,''), coalesce(join_date,''),
                       coalesce(tier,''), coalesce(brand,''), coalesce(status,''),
                       coalesce(country,''), coalesce(birth_date,''))) AS row_fp
FROM members_raw;

-- Anchored to the data's last transaction date, not the wall clock, so every
-- number here reproduces on any future run.
CREATE OR REPLACE TABLE dq_params AS
SELECT CAST(max(transaction_ts) AS DATE) AS anchor_date FROM tx;

CREATE OR REPLACE TABLE dq_rowcounts AS
SELECT (SELECT count(*) FROM mem) AS member_rows,
       (SELECT count(*) FROM tx)  AS tx_rows;



-- DQ-01 -- Is `status` behaviourally meaningful, or decorative?
-- If the last-90-day activity rate is flat across active/inactive/churned, the
-- column carries no signal and must not be used as a churn label.
CREATE OR REPLACE VIEW ev_status_vs_behaviour AS
WITH last_tx AS (
    SELECT member_id, max(transaction_ts) AS last_dt FROM tx GROUP BY 1
)
SELECT m.status,
       count(*)                                                      AS members,
       round(100 * avg(CASE WHEN date_diff('day', l.last_dt,
             (SELECT anchor_date FROM dq_params)) <= 90
             THEN 1 ELSE 0 END), 1)                                  AS pct_active_last_90d,
       round(avg(date_diff('day', l.last_dt,
             (SELECT anchor_date FROM dq_params))), 1)               AS avg_days_since_last_tx
FROM mem m JOIN last_tx l USING (member_id)
GROUP BY 1 ORDER BY 1;

-- DQ-02 -- Implausible amounts. Keyed on magnitude alone: an id-prefix rule also
-- catches the 2,988 orphans, which are a different finding (DQ-06). p99.9 of
-- legitimate amounts is ~600, so >10,000 is three orders of magnitude out rather
-- than a judgement call about big spenders.
CREATE OR REPLACE VIEW ev_corrupt_batch AS
SELECT transaction_id, member_id, transaction_date_raw, amount,
       points_earned, points_redeemed, channel, brand,
       round(points_earned / amount, 6) AS implied_points_per_dollar
FROM tx
WHERE amount > 10000
ORDER BY amount DESC;

-- Three id conventions in one file is the tell that three loaders wrote it.
CREATE OR REPLACE VIEW ev_id_prefix_families AS
SELECT CASE
         WHEN regexp_matches(t.transaction_id, '^T[0-9]+$')  THEN 'T#####   (mainline)'
         WHEN regexp_matches(t.transaction_id, '^TO[0-9]+$') THEN 'TO####   (corrupt batch, DQ-02)'
         WHEN regexp_matches(t.transaction_id, '^TX[0-9]+$') THEN 'TX#####  (orphan source, DQ-06)'
         ELSE 'other'
       END                                                    AS id_family,
       count(*)                                               AS rows,
       count(*) FILTER (WHERE m.member_id IS NULL)            AS rows_with_orphan_member,
       count(*) FILTER (WHERE t.amount > 10000)               AS rows_with_implausible_amount,
       min(CAST(t.transaction_ts AS DATE))                    AS first_date,
       max(CAST(t.transaction_ts AS DATE))                    AS last_date
FROM tx t
LEFT JOIN (SELECT DISTINCT member_id FROM mem) m USING (member_id)
GROUP BY 1 ORDER BY rows DESC;

-- DQ-03 -- Member key integrity: identical replays vs conflicting versions.
CREATE OR REPLACE VIEW ev_member_key_integrity AS
WITH g AS (
    SELECT member_id, count(*) AS n_rows, count(DISTINCT row_fp) AS n_versions
    FROM mem GROUP BY 1
)
SELECT count(*)                                             AS distinct_member_ids,
       count(*) FILTER (WHERE n_rows > 1)                   AS ids_appearing_more_than_once,
       coalesce(sum(n_rows - 1) FILTER (WHERE n_rows > 1),0) AS surplus_rows,
       count(*) FILTER (WHERE n_rows > 1 AND n_versions = 1) AS identical_replays,
       count(*) FILTER (WHERE n_rows > 1 AND n_versions > 1) AS conflicting_versions
FROM g;

-- Which fields actually disagree when a member_id has two versions?
CREATE OR REPLACE VIEW ev_member_conflict_fields AS
WITH dupes AS (
    SELECT member_id FROM mem GROUP BY 1 HAVING count(*) > 1
)
SELECT count(DISTINCT member_id)                                  AS conflicting_members,
       count(DISTINCT member_id) FILTER (WHERE n_tier   > 1)      AS tier_disagrees,
       count(DISTINCT member_id) FILTER (WHERE n_status > 1)      AS status_disagrees,
       count(DISTINCT member_id) FILTER (WHERE n_join   > 1)      AS join_date_disagrees,
       count(DISTINCT member_id) FILTER (WHERE n_brand  > 1)      AS brand_disagrees
FROM (
    SELECT m.member_id,
           count(DISTINCT m.tier) AS n_tier, count(DISTINCT m.status) AS n_status,
           count(DISTINCT m.join_date_raw) AS n_join, count(DISTINCT m.brand) AS n_brand
    FROM mem m JOIN dupes USING (member_id) GROUP BY 1
);

CREATE OR REPLACE VIEW ev_member_conflict_sample AS
SELECT m.member_id, m.tier, m.status, m.brand, m.join_date_raw, m.country
FROM mem m
JOIN (SELECT member_id FROM mem GROUP BY 1 HAVING count(*) > 1 LIMIT 6) s USING (member_id)
ORDER BY m.member_id, m.tier;

-- DQ-04 -- Transaction key integrity: replay vs primary-key collision.
-- These need different fixes, so they must not be reported as one number.
CREATE OR REPLACE VIEW ev_tx_key_integrity AS
WITH g AS (
    SELECT transaction_id, count(*) AS n_rows, count(DISTINCT row_fp) AS n_versions
    FROM tx GROUP BY 1
)
SELECT count(*)                                              AS distinct_transaction_ids,
       count(*) FILTER (WHERE n_rows > 1)                    AS ids_appearing_more_than_once,
       coalesce(sum(n_rows - 1) FILTER (WHERE n_rows > 1),0) AS surplus_rows,
       count(*) FILTER (WHERE n_rows > 1 AND n_versions = 1) AS identical_replay_ids,
       count(*) FILTER (WHERE n_rows > 1 AND n_versions > 1) AS key_collision_ids
FROM g;

CREATE OR REPLACE VIEW ev_tx_collision_sample AS
SELECT t.transaction_id, t.member_id, t.transaction_date_raw, t.amount,
       t.points_earned, t.channel, t.brand
FROM tx t
JOIN (SELECT transaction_id FROM tx GROUP BY 1
      HAVING count(*) > 1 AND count(DISTINCT row_fp) > 1 LIMIT 4) s USING (transaction_id)
ORDER BY t.transaction_id;

-- DQ-05 -- Orphan transactions: activity for members that do not exist.
CREATE OR REPLACE VIEW ev_orphan_transactions AS
SELECT count(*)                                    AS orphan_tx_rows,
       count(DISTINCT t.member_id)                 AS orphan_member_ids,
       round(100.0 * count(*) /
             (SELECT tx_rows FROM dq_rowcounts), 2) AS pct_of_all_tx,
       min(t.member_id)                            AS min_orphan_id,
       max(t.member_id)                            AS max_orphan_id,
       round(sum(t.amount), 2)                     AS orphaned_spend
FROM tx t LEFT JOIN (SELECT DISTINCT member_id FROM mem) m USING (member_id)
WHERE m.member_id IS NULL;

-- DQ-06 -- Points earn rate per brand, and whether points are deterministic.
-- If points = round(rate * amount), the 1,514 NULL points are recoverable
-- exactly, which changes the fix from "drop" to "impute".
CREATE OR REPLACE TABLE ev_points_rate_by_brand AS
SELECT brand,
       median(points_earned / amount) AS implied_rate,
       count(*)                       AS rows_used
FROM tx
WHERE amount > 0 AND amount < 10000 AND points_earned IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- Two match columns on purpose. Exact match understates determinism: at
-- PulseHome's rate of exactly 2.0, rate * amount lands on .5 constantly and
-- DuckDB rounds half away from zero where the source rounds half to even.
-- pct_within_1 separates that convention artifact from real non-determinism --
-- which is what decides whether NULL points can be imputed or must be dropped.
CREATE OR REPLACE VIEW ev_points_determinism AS
SELECT r.brand, r.implied_rate,
       count(*)                                                                    AS rows_tested,
       count(*) FILTER (WHERE round(r.implied_rate * t.amount) = t.points_earned)   AS exact_match,
       round(100.0 * count(*) FILTER (WHERE round(r.implied_rate * t.amount)
             = t.points_earned) / count(*), 4)                                      AS pct_exact,
       count(*) FILTER (WHERE abs(r.implied_rate * t.amount - t.points_earned) <= 1) AS within_1_point,
       round(100.0 * count(*) FILTER (WHERE abs(r.implied_rate * t.amount
             - t.points_earned) <= 1) / count(*), 4)                                AS pct_within_1
FROM tx t JOIN ev_points_rate_by_brand r USING (brand)
WHERE t.amount > 0 AND t.amount < 10000 AND t.points_earned IS NOT NULL
GROUP BY 1, 2 ORDER BY 1;

-- DQ-07 -- Negative amounts: refund, or sign error?
-- Decisive test: if points were computed on the ABSOLUTE amount, the row was a
-- normal purchase whose sign got flipped downstream. A true refund would carry
-- NEGATIVE points (a clawback).
CREATE OR REPLACE VIEW ev_negative_amount_diagnosis AS
WITH neg AS (
    SELECT t.*, r.implied_rate
    FROM tx t JOIN ev_points_rate_by_brand r USING (brand)
    WHERE t.amount < 0
)
SELECT count(*)                                                                   AS negative_rows,
       count(*) FILTER (WHERE points_earned > 0)                                  AS with_positive_points,
       count(*) FILTER (WHERE points_earned < 0)                                  AS with_negative_points_clawback,
       count(*) FILTER (WHERE points_redeemed > 0)                                AS also_redeeming_points,
       count(*) FILTER (WHERE round(implied_rate * abs(amount)) = points_earned)   AS points_match_abs_amount,
       round(100.0 * count(*) FILTER (WHERE round(implied_rate * abs(amount))
             = points_earned) / count(*), 1)                                       AS pct_points_match_abs
FROM neg;

-- Corroborating test: does a same-member positive transaction of equal magnitude
-- exist (which is what a genuine refund would look like)?
CREATE OR REPLACE VIEW ev_negative_refund_pairing AS
WITH neg AS (SELECT transaction_id, member_id, abs(amount) AS amt FROM tx WHERE amount < 0),
     pos AS (SELECT DISTINCT member_id, amount AS amt FROM tx WHERE amount > 0)
-- Grain is distinct transaction_id, not rows: 2,012 negative rows collapse to
-- 1,995 ids because some negatives are themselves among the DQ-04 replays.
SELECT count(*)                        AS negative_transaction_ids,
       count(*) FILTER (WHERE has_match) AS with_matching_positive_same_member
FROM (
    SELECT n.transaction_id,
           max(CASE WHEN p.member_id IS NOT NULL THEN 1 ELSE 0 END)::BOOLEAN AS has_match
    FROM neg n
    LEFT JOIN pos p ON n.member_id = p.member_id AND abs(n.amt - p.amt) < 0.005
    GROUP BY 1
);

-- DQ-08 -- Date formats present in transaction_date.
CREATE OR REPLACE VIEW ev_date_formats AS
SELECT CASE
         WHEN trim(coalesce(transaction_date_raw,'')) = ''                                      THEN 'EMPTY'
         WHEN regexp_matches(trim(transaction_date_raw), '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$') THEN 'ISO timestamp  YYYY-MM-DD HH:MM:SS'
         WHEN regexp_matches(trim(transaction_date_raw), '^\d{4}-\d{2}-\d{2}$')                   THEN 'ISO date only  YYYY-MM-DD'
         WHEN regexp_matches(trim(transaction_date_raw), '^\d{2}/\d{2}/\d{4}$')                   THEN 'Slash          NN/NN/YYYY'
         ELSE 'OTHER'
       END                                              AS date_format,
       count(*)                                         AS rows,
       count(*) FILTER (WHERE transaction_ts IS NULL)   AS unparsed_after_fix,
       min(transaction_date_raw)                        AS example
FROM tx GROUP BY 1 ORDER BY rows DESC;

-- Proof the slash dates are MM/DD and not DD/MM: component 1 never exceeds 12,
-- while component 2 reaches 31. Only month/day fits.
CREATE OR REPLACE VIEW ev_slash_date_orientation AS
SELECT count(*)                                                  AS slash_rows,
       max(CAST(split_part(trim(transaction_date_raw),'/',1) AS INT)) AS max_component_1,
       max(CAST(split_part(trim(transaction_date_raw),'/',2) AS INT)) AS max_component_2,
       count(*) FILTER (WHERE CAST(split_part(trim(transaction_date_raw),'/',1) AS INT) > 12) AS rows_c1_over_12,
       count(*) FILTER (WHERE CAST(split_part(trim(transaction_date_raw),'/',2) AS INT) > 12) AS rows_c2_over_12
FROM tx
WHERE regexp_matches(trim(transaction_date_raw), '^\d{2}/\d{2}/\d{4}$');

-- DQ-09 -- join_date defects. Also confirms the defects are NOT a parsing
-- artifact: non_iso_format counts rows our parser could not read.
CREATE OR REPLACE VIEW ev_join_date_defects AS
WITH first_tx AS (
    SELECT member_id, min(transaction_ts) AS first_dt FROM tx GROUP BY 1
)
SELECT count(*)                                                                    AS member_rows,
       count(*) FILTER (WHERE trim(coalesce(m.join_date_raw,'')) = '')             AS blank_join_date,
       count(*) FILTER (WHERE trim(coalesce(m.join_date_raw,'')) <> ''
                          AND m.join_ts IS NULL)                                   AS non_iso_format,
       count(*) FILTER (WHERE CAST(m.join_ts AS DATE)
                            > (SELECT anchor_date FROM dq_params))                 AS join_date_in_future,
       count(*) FILTER (WHERE f.first_dt IS NOT NULL AND m.join_ts > f.first_dt)   AS joined_after_first_tx,
       max(CAST(m.join_ts AS DATE))                                                AS max_join_date,
       (SELECT anchor_date FROM dq_params)                                         AS data_anchor_date
FROM mem m LEFT JOIN first_tx f USING (member_id);

-- DQ-10 -- Controlled-vocabulary drift in tier and country.
CREATE OR REPLACE VIEW ev_tier_variants AS
SELECT tier AS raw_value, count(*) AS rows,
       CASE WHEN tier IN ('Bronze','Silver','Gold','Platinum')
            THEN 'canonical' ELSE 'VARIANT' END AS verdict
FROM mem GROUP BY 1 ORDER BY verdict DESC, rows DESC;

CREATE OR REPLACE VIEW ev_country_variants AS
SELECT country AS raw_value, count(*) AS rows,
       CASE WHEN regexp_matches(country, '^[A-Z]{2}$')
            THEN 'canonical ISO-3166-2' ELSE 'VARIANT' END AS verdict
FROM mem GROUP BY 1 ORDER BY verdict DESC, rows DESC;

-- DQ-11 -- Identity resolution + PII exposure (the governance lens).
CREATE OR REPLACE VIEW ev_identity_and_pii AS
SELECT (SELECT count(*) FROM (
            SELECT lower(trim(email)) AS em FROM mem
            GROUP BY 1 HAVING count(DISTINCT member_id) > 1))              AS emails_shared_across_member_ids,
       (SELECT count(*) FROM mem WHERE trim(coalesce(email,'')) = '')      AS blank_emails,
       (SELECT count(*) FROM mem
         WHERE NOT regexp_matches(email, '^[^@\s]+@[^@\s]+\.[^@\s]+$'))    AS malformed_emails,
       (SELECT count(*) FROM mem WHERE birth_ts IS NOT NULL)               AS rows_with_birth_date_in_clear,
       (SELECT count(*) FROM mem)                                          AS rows_with_name_and_email_in_clear;

-- DQ-12 -- Null points_earned (recoverable given DQ-06).
CREATE OR REPLACE VIEW ev_null_points AS
SELECT count(*)                                              AS tx_rows,
       count(*) FILTER (WHERE points_earned IS NULL)         AS null_points_earned,
       count(*) FILTER (WHERE points_redeemed IS NULL)       AS null_points_redeemed,
       count(*) FILTER (WHERE amount IS NULL)                AS null_amount,
       round(100.0 * count(*) FILTER (WHERE points_earned IS NULL)
             / count(*), 3)                                  AS pct_null_points
FROM tx;

-- Brand recorded on the transaction vs on the member. Not a defect, but it
-- decides the join key for any brand-level analysis (see Part 6).
CREATE OR REPLACE VIEW ev_brand_agreement AS
SELECT count(*)                                                   AS joined_tx_rows,
       count(*) FILTER (WHERE t.brand = m.brand)                  AS brand_matches_member,
       round(100.0 * count(*) FILTER (WHERE t.brand = m.brand)
             / count(*), 1)                                       AS pct_match
FROM tx t JOIN (SELECT DISTINCT member_id, brand FROM mem) m USING (member_id);


-- Checks that passed. An audit reporting only failures gives no evidence of its
-- own coverage.
CREATE OR REPLACE VIEW ev_checks_passed AS
SELECT * FROM (VALUES
  ('birth_date plausibility',
   (SELECT count(*) FROM mem WHERE date_diff('year', CAST(birth_ts AS DATE),
        (SELECT anchor_date FROM dq_params)) NOT BETWEEN 18 AND 100)::VARCHAR || ' implausible ages'),
  ('email well-formedness',
   (SELECT count(*) FROM mem WHERE NOT regexp_matches(email,
        '^[^@\s]+@[^@\s]+\.[^@\s]+$'))::VARCHAR || ' malformed'),
  ('brand vocabulary (transactions)',
   (SELECT count(DISTINCT brand) FROM tx)::VARCHAR || ' distinct values, all canonical'),
  ('channel vocabulary',
   (SELECT count(DISTINCT channel) FROM tx)::VARCHAR || ' distinct values, all canonical'),
  ('transaction_id / member_id null check',
   (SELECT count(*) FROM tx WHERE transaction_id IS NULL OR member_id IS NULL)::VARCHAR || ' nulls'),
  ('transaction_type cardinality',
   (SELECT count(DISTINCT transaction_type) FROM tx)::VARCHAR ||
   ' value(s) — redemptions are embedded in purchase rows, not separate events')
) AS t(check_name, result);


-- Consolidated findings: the backbone of the report table in part1/README.md.
CREATE OR REPLACE VIEW dq_findings AS
SELECT * FROM (VALUES
  ('DQ-01','A','MODEL',      'status is behaviourally meaningless',
      'spread in 90-day activity rate across status values (pct points)',
      (SELECT round(max(pct_active_last_90d) - min(pct_active_last_90d),1) FROM ev_status_vs_behaviour)),
  ('DQ-02','A','MODEL',      'Corrupted batch: implausible amounts with normal points',
      'rows', (SELECT count(*)::DOUBLE FROM ev_corrupt_batch)),
  ('DQ-03','A','MODEL',      'Conflicting member records under one member_id',
      'member_ids with disagreeing versions',
      (SELECT conflicting_versions::DOUBLE FROM ev_member_key_integrity)),
  ('DQ-04','A','MODEL',      'Replayed transactions (byte-identical duplicates)',
      'transaction_ids', (SELECT identical_replay_ids::DOUBLE FROM ev_tx_key_integrity)),
  ('DQ-05','A','MODEL',      'Primary-key collisions (same id, different content)',
      'transaction_ids', (SELECT key_collision_ids::DOUBLE FROM ev_tx_key_integrity)),
  ('DQ-06','A','MODEL',      'Orphan transactions (member_id absent from members)',
      'rows', (SELECT orphan_tx_rows::DOUBLE FROM ev_orphan_transactions)),
  ('DQ-07','B','MODEL',      'Negative amounts still earning positive points',
      'rows', (SELECT negative_rows::DOUBLE FROM ev_negative_amount_diagnosis)),
  ('DQ-08','B','MODEL',      'Multiple date formats in transaction_date',
      'rows not in ISO timestamp form',
      (SELECT sum(rows)::DOUBLE FROM ev_date_formats
        WHERE date_format <> 'ISO timestamp  YYYY-MM-DD HH:MM:SS')),
  ('DQ-09','B','MODEL',      'join_date blank / future-dated / after first transaction',
      'defective rows', (SELECT (blank_join_date + join_date_in_future
                                 + joined_after_first_tx)::DOUBLE FROM ev_join_date_defects)),
  ('DQ-10','B','MODEL',      'Controlled-vocabulary drift in tier and country',
      'non-canonical rows',
      (SELECT (SELECT coalesce(sum(rows),0) FROM ev_tier_variants   WHERE verdict='VARIANT')
            + (SELECT coalesce(sum(rows),0) FROM ev_country_variants WHERE verdict='VARIANT'))::DOUBLE),
  ('DQ-11','B','MODEL',      'NULL points_earned (recoverable — see DQ-06 determinism)',
      'rows', (SELECT null_points_earned::DOUBLE FROM ev_null_points)),
  ('DQ-12','A','GOVERNANCE', 'One email shared across multiple member_ids',
      'emails', (SELECT emails_shared_across_member_ids::DOUBLE FROM ev_identity_and_pii)),
  ('DQ-13','A','GOVERNANCE', 'PII (email, name, birth_date) unmasked in raw export',
      'member rows carrying clear-text PII',
      (SELECT rows_with_name_and_email_in_clear::DOUBLE FROM ev_identity_and_pii))
) AS t(check_id, severity, lens, issue, metric, value)
ORDER BY severity, check_id;
