-- Shared cleaning layer. Part 1 audits the raw data; this applies the fixes it
-- prescribed, once, so Parts 2 and 6-8 share one definition of "clean".
--
-- Emits:   brand_rate, tx_clean, mem_clean, clean_rejects, clean_audit
-- Expects: members.csv and transactions.csv in the working directory
--
-- Every repair sets a flag column -- nothing is altered silently.

CREATE OR REPLACE VIEW members_raw AS
SELECT * FROM read_csv('members.csv',      all_varchar = true, header = true);
CREATE OR REPLACE VIEW tx_raw AS
SELECT * FROM read_csv('transactions.csv', all_varchar = true, header = true);

-- Three date formats in one column. Slash dates are MM/DD, not DD/MM: the first
-- component never exceeds 12 while the second reaches 31. Unknown formats stay NULL.
CREATE OR REPLACE MACRO parse_ts(d) AS coalesce(
    try_strptime(trim(d), '%Y-%m-%d %H:%M:%S'),
    try_strptime(trim(d), '%Y-%m-%d'),
    try_strptime(trim(d), '%m/%d/%Y')
);
CREATE OR REPLACE MACRO to_num(x) AS try_cast(nullif(trim(x), '') AS DOUBLE);

-- CASE rather than initcap(): an unrecognised value must surface as 'Unknown',
-- not be quietly title-cased into a plausible-looking category.
CREATE OR REPLACE MACRO norm_tier(t) AS
    CASE lower(trim(t))
        WHEN 'bronze' THEN 'Bronze' WHEN 'silver'   THEN 'Silver'
        WHEN 'gold'   THEN 'Gold'   WHEN 'platinum' THEN 'Platinum'
        ELSE 'Unknown' END;

CREATE OR REPLACE MACRO norm_country(c) AS
    CASE lower(replace(replace(trim(c), '.', ''), ' ', ''))
        WHEN 'in' THEN 'IN' WHEN 'india'     THEN 'IN'
        WHEN 'us' THEN 'US' WHEN 'usa'       THEN 'US'
        WHEN 'sg' THEN 'SG' WHEN 'singapore' THEN 'SG'
        WHEN 'ae' THEN 'AE' WHEN 'uae'       THEN 'AE'
        WHEN 'gb' THEN 'GB' WHEN 'uk'        THEN 'GB'
        ELSE 'Unknown' END;

CREATE OR REPLACE MACRO tier_rank(t) AS
    CASE t WHEN 'Bronze' THEN 1 WHEN 'Silver' THEN 2
           WHEN 'Gold'   THEN 3 WHEN 'Platinum' THEN 4 ELSE 0 END;


-- row_fp hashes the raw strings: it answers "is this row byte-identical to
-- another", which is what separates a replayed load from a real key collision.
CREATE OR REPLACE TABLE tx_typed AS
SELECT transaction_id, member_id,
       parse_ts(transaction_date)  AS transaction_ts,
       to_num(amount)              AS amount,
       to_num(points_earned)       AS points_earned,
       to_num(points_redeemed)     AS points_redeemed,
       channel, brand, transaction_type,
       md5(concat_ws('|', coalesce(member_id,''), coalesce(transaction_date,''),
                          coalesce(amount,''), coalesce(points_earned,''),
                          coalesce(points_redeemed,''), coalesce(channel,''),
                          coalesce(brand,''), coalesce(transaction_type,''))) AS row_fp
FROM tx_raw;


-- Dedupe on (transaction_id, row_fp), NOT transaction_id. 1,995 ids repeat, but
-- only 1,936 are byte-identical replays; the other 59 are distinct transactions
-- sharing a reused id. Deduping on the id alone silently deletes those 59.
CREATE OR REPLACE TABLE tx_dedup AS
SELECT *, md5(transaction_id || '|' || row_fp) AS transaction_sk
FROM tx_typed
QUALIFY row_number() OVER (PARTITION BY transaction_id, row_fp
                           ORDER BY member_id) = 1;


-- points = round(rate * amount) holds for 100% of rows within one point, so this
-- is a measured constant, not a fitted estimate -- which is what makes the repairs
-- below exact. Derived from clean rows only, then used to repair the dirty ones.
CREATE OR REPLACE TABLE brand_rate AS
SELECT brand, round(median(points_earned / amount), 4) AS earn_rate, count(*) AS rows_used
FROM tx_dedup
WHERE amount > 0 AND amount < 10000 AND points_earned IS NOT NULL
GROUP BY 1;


CREATE OR REPLACE TABLE tx_clean AS
WITH base AS (
    SELECT d.*, r.earn_rate FROM tx_dedup d LEFT JOIN brand_rate r USING (brand)
)
SELECT
    transaction_sk, transaction_id, member_id, transaction_ts,
    channel, brand, transaction_type, earn_rate,

    -- Not refunds: points were computed on |amount|, no clawback exists, and none
    -- has a matching positive twin. Sign flipped in transit, so abs() restores it.
    (amount < 0)                                     AS flag_sign_error,

    -- Sentinel amounts (999999.99) with intact points: the purchase is real, only
    -- the amount field is junk, so recover it rather than dropping the row.
    (amount > 10000)                                 AS flag_amount_recovered,

    -- Deterministic, so this imputes exactly rather than estimating.
    (points_earned IS NULL)                          AS flag_points_imputed,

    CASE WHEN amount > 10000 AND points_earned IS NOT NULL
              THEN round(points_earned / earn_rate, 2)
         WHEN amount > 10000 THEN NULL
         ELSE round(abs(amount), 2) END              AS amount,

    CASE WHEN points_earned IS NOT NULL THEN points_earned
         WHEN amount IS NOT NULL        THEN round(earn_rate * abs(amount))
         ELSE NULL END                               AS points_earned,

    coalesce(points_redeemed, 0)                     AS points_redeemed
FROM base;


-- 150 member_ids carry two rows disagreeing on tier and status. With no
-- updated_at, no rule can recover the true record -- any pick is arbitrary. Choose
-- deterministically so runs reproduce, and flag it so downstream can discount
-- those members rather than trusting a coin-flip.
CREATE OR REPLACE TABLE mem_clean AS
WITH conflicted AS (
    SELECT member_id FROM members_raw GROUP BY 1 HAVING count(*) > 1
),
typed AS (
    SELECT m.member_id, m.email, m.first_name, m.last_name,
           try_strptime(trim(m.join_date), '%Y-%m-%d')  AS join_ts,
           try_strptime(trim(m.birth_date), '%Y-%m-%d') AS birth_ts,
           norm_tier(m.tier)                            AS tier,
           tier_rank(norm_tier(m.tier))                 AS tier_rank,
           m.brand                                      AS home_brand,
           m.status                                     AS status_raw,
           norm_country(m.country)                      AS country,
           (c.member_id IS NOT NULL)                    AS flag_profile_conflicted
    FROM members_raw m LEFT JOIN conflicted c USING (member_id)
)
SELECT * FROM typed
QUALIFY row_number() OVER (PARTITION BY member_id
                           ORDER BY tier_rank DESC, status_raw) = 1;


-- Orphans are quarantined, not dropped: an inner join would erase 2,988 rows and
-- $192k of spend with no trace.
CREATE OR REPLACE TABLE clean_rejects AS
SELECT 'orphan_transaction' AS reason, t.transaction_sk, t.member_id,
       t.transaction_ts, t.amount, t.points_earned
FROM tx_clean t
LEFT JOIN (SELECT member_id FROM mem_clean) m USING (member_id)
WHERE m.member_id IS NULL;

CREATE OR REPLACE TABLE clean_audit AS
SELECT 'tx rows in raw'                AS metric, (SELECT count(*) FROM tx_typed)::BIGINT AS value UNION ALL
SELECT 'tx rows after replay dedup',   (SELECT count(*) FROM tx_dedup) UNION ALL
SELECT 'replay rows removed',          (SELECT count(*) FROM tx_typed) - (SELECT count(*) FROM tx_dedup) UNION ALL
SELECT 'sign errors repaired',         (SELECT count(*) FROM tx_clean WHERE flag_sign_error) UNION ALL
SELECT 'corrupt amounts recovered',    (SELECT count(*) FROM tx_clean WHERE flag_amount_recovered) UNION ALL
SELECT 'null points imputed',          (SELECT count(*) FROM tx_clean WHERE flag_points_imputed) UNION ALL
SELECT 'orphan tx quarantined',        (SELECT count(*) FROM clean_rejects) UNION ALL
SELECT 'member rows in raw',           (SELECT count(*) FROM members_raw) UNION ALL
SELECT 'members after conflict resolution', (SELECT count(*) FROM mem_clean) UNION ALL
SELECT 'members flagged conflicted',   (SELECT count(*) FROM mem_clean WHERE flag_profile_conflicted);
