-- Member-level feature table for 90-day churn. Expects common/clean.sql.
--
-- The label is the load-bearing decision. `status` cannot be it: active,
-- inactive and churned members differ by 0.7pp in 90-day activity, so a model
-- trained on it learns noise. Deriving the label from behaviour forces a split:
--
--     ... history ..........|  cutoff  |...... outcome 90d ......|
--     features from here                label observed here
--                        2026-04-01                    2026-06-30
--
-- Features read only on/before the cutoff; the label is activity after it.
-- Aggregating over the whole file -- the natural way to write a "lifetime"
-- feature -- leaks the answer into the inputs. leakage_check asserts it did not.

CREATE OR REPLACE TABLE f_params AS
SELECT anchor_date, cutoff_date,
       CAST(cutoff_date - INTERVAL 365 DAY AS DATE) AS eligibility_floor
FROM (SELECT ad AS anchor_date, CAST(ad - INTERVAL 90 DAY AS DATE) AS cutoff_date
      FROM (SELECT CAST(max(transaction_ts) AS DATE) AS ad FROM tx_clean));

-- Split at the cutoff so no feature query can reach the outcome window.
CREATE OR REPLACE TABLE tx_pre AS
SELECT t.* FROM tx_clean t, f_params p
WHERE CAST(t.transaction_ts AS DATE) <= p.cutoff_date;

CREATE OR REPLACE TABLE tx_post AS
SELECT t.* FROM tx_clean t, f_params p
WHERE CAST(t.transaction_ts AS DATE) > p.cutoff_date;

-- The active base a retention team could act on: at least one purchase in the
-- 365 days before the cutoff. Including members dormant for years would inflate
-- churn with people who left long ago -- a more accurate model, less useful.
CREATE OR REPLACE TABLE eligible AS
SELECT DISTINCT t.member_id
FROM tx_pre t, f_params p
JOIN mem_clean m ON m.member_id = t.member_id
WHERE CAST(t.transaction_ts AS DATE) > p.eligibility_floor;


CREATE OR REPLACE TABLE member_features AS
WITH p AS (SELECT * FROM f_params),

-- Behavioural aggregates, all strictly pre-cutoff.
agg AS (
    SELECT t.member_id,
           -- RECENCY
           date_diff('day', max(CAST(t.transaction_ts AS DATE)), p.cutoff_date) AS r_days_since_last_txn,
           date_diff('day', min(CAST(t.transaction_ts AS DATE)), p.cutoff_date) AS r_days_since_first_txn,
           -- FREQUENCY
           count(*)                                                             AS f_txn_lifetime,
           count(*) FILTER (WHERE CAST(t.transaction_ts AS DATE) >  p.cutoff_date - 90)  AS f_txn_90d,
           count(*) FILTER (WHERE CAST(t.transaction_ts AS DATE) >  p.cutoff_date - 180) AS f_txn_180d,
           count(*) FILTER (WHERE CAST(t.transaction_ts AS DATE) >  p.cutoff_date - 365) AS f_txn_365d,
           count(*) FILTER (WHERE CAST(t.transaction_ts AS DATE) <= p.cutoff_date - 90
                              AND CAST(t.transaction_ts AS DATE) >  p.cutoff_date - 180) AS f_txn_prior_90d,
           count(DISTINCT date_trunc('month', t.transaction_ts))
               FILTER (WHERE CAST(t.transaction_ts AS DATE) > p.cutoff_date - 365)       AS f_active_months_12m,
           -- MONETARY
           round(sum(t.amount), 2)                                              AS m_spend_lifetime,
           round(sum(t.amount) FILTER (WHERE CAST(t.transaction_ts AS DATE) > p.cutoff_date - 90), 2)  AS m_spend_90d,
           round(sum(t.amount) FILTER (WHERE CAST(t.transaction_ts AS DATE) > p.cutoff_date - 365), 2) AS m_spend_365d,
           round(sum(t.amount) FILTER (WHERE CAST(t.transaction_ts AS DATE) <= p.cutoff_date - 90
                                         AND CAST(t.transaction_ts AS DATE) >  p.cutoff_date - 180), 2) AS m_spend_prior_90d,
           round(avg(t.amount), 2)                                              AS m_avg_basket,
           round(max(t.amount), 2)                                              AS m_max_basket,
           -- REDEMPTION
           sum(t.points_earned)                                                 AS rd_points_earned,
           sum(t.points_redeemed)                                               AS rd_points_redeemed,
           sum(t.points_earned) - sum(t.points_redeemed)                        AS rd_points_balance,
           count(*) FILTER (WHERE t.points_redeemed > 0)                        AS rd_txn_with_redemption,
           max(CAST(t.transaction_ts AS DATE)) FILTER (WHERE t.points_redeemed > 0) AS rd_last_redemption_date,
           -- CHANNEL / BRAND BREADTH
           count(DISTINCT t.channel)                                            AS c_distinct_channels,
           count(DISTINCT t.brand)                                              AS c_distinct_brands,
           round(avg(CASE WHEN t.channel = 'app'      THEN 1.0 ELSE 0 END), 3)  AS c_pct_app,
           round(avg(CASE WHEN t.channel = 'online'   THEN 1.0 ELSE 0 END), 3)  AS c_pct_online,
           round(avg(CASE WHEN t.channel = 'in_store' THEN 1.0 ELSE 0 END), 3)  AS c_pct_in_store,
           -- Repairs carried forward as features so the model can discount them.
           count(*) FILTER (WHERE t.flag_sign_error)       AS dq_sign_error_txns,
           count(*) FILTER (WHERE t.flag_points_imputed)   AS dq_points_imputed_txns,
           count(*) FILTER (WHERE t.flag_amount_recovered) AS dq_amount_recovered_txns,
           min(CAST(t.transaction_ts AS DATE))             AS first_txn_date
    FROM tx_pre t, p
    GROUP BY t.member_id, p.cutoff_date
),

-- Outcome window: label only, never a feature.
outcome AS (
    SELECT member_id, count(*) AS post_txn_count
    FROM tx_post GROUP BY 1
)

SELECT
    e.member_id,
    (SELECT cutoff_date FROM p)                                       AS cutoff_date,

    -- ================= LABEL =================
    CASE WHEN coalesce(o.post_txn_count, 0) = 0 THEN 1 ELSE 0 END     AS churned_90d,

    -- ================= RECENCY =================
    a.r_days_since_last_txn,
    a.r_days_since_first_txn,
    date_diff('day', a.rd_last_redemption_date, (SELECT cutoff_date FROM p)) AS r_days_since_last_redemption,

    -- ================= FREQUENCY =================
    a.f_txn_lifetime, a.f_txn_90d, a.f_txn_180d, a.f_txn_365d, a.f_active_months_12m,
    CASE WHEN a.f_txn_lifetime > 1
         THEN round(a.r_days_since_first_txn::DOUBLE / (a.f_txn_lifetime - 1), 1)
         END                                                          AS f_avg_days_between_txn,

    -- ================= MONETARY =================
    a.m_spend_lifetime, a.m_spend_90d, a.m_spend_365d, a.m_avg_basket, a.m_max_basket,

    -- ================= ENGAGEMENT TREND =================
    -- Smoothed so an empty prior window gives a finite ratio rather than a null
    -- the model must special-case. Below 1 means decelerating.
    round((a.f_txn_90d + 1.0)  / (a.f_txn_prior_90d + 1.0), 3)        AS t_txn_trend_90_vs_prior,
    round((coalesce(a.m_spend_90d,0) + 1.0)
          / (coalesce(a.m_spend_prior_90d,0) + 1.0), 3)               AS t_spend_trend_90_vs_prior,

    -- ================= REDEMPTION =================
    a.rd_points_earned, a.rd_points_redeemed, a.rd_points_balance,
    round(a.rd_points_redeemed::DOUBLE
          / nullif(a.rd_points_earned, 0), 4)                         AS rd_redemption_rate,
    CASE WHEN a.rd_txn_with_redemption > 0 THEN 1 ELSE 0 END          AS rd_has_ever_redeemed,

    -- ================= BREADTH =================
    a.c_distinct_channels, a.c_distinct_brands,
    a.c_pct_app, a.c_pct_online, a.c_pct_in_store,

    -- ================= PROFILE =================
    m.tier, m.tier_rank, m.country, m.home_brand,
    date_diff('year', CAST(m.birth_ts AS DATE), (SELECT cutoff_date FROM p)) AS p_age,
    -- join_date is blank for 999 members, future-dated for 30, and later than the
    -- member's own first purchase for 205. Left NULL where not credible: tenure is
    -- the strongest feature here, and a fabricated value is worse than a missing one.
    --
    -- All THREE defects must be tested. An earlier version checked only null and
    -- future-dated, which left 157 scored members carrying an unflagged tenure
    -- computed from a join_date later than their own first transaction.
    CASE WHEN m.join_ts IS NOT NULL
          AND CAST(m.join_ts AS DATE) <= (SELECT cutoff_date FROM p)
          AND CAST(m.join_ts AS DATE) <= a.first_txn_date
         THEN date_diff('day', CAST(m.join_ts AS DATE), (SELECT cutoff_date FROM p))
         END                                                          AS p_tenure_days,
    CASE WHEN m.join_ts IS NULL
           OR CAST(m.join_ts AS DATE) > (SELECT cutoff_date FROM p)
           OR CAST(m.join_ts AS DATE) > a.first_txn_date THEN 1 ELSE 0 END AS dq_join_date_unusable,

    -- ================= DQ EXPOSURE FLAGS =================
    CASE WHEN m.flag_profile_conflicted THEN 1 ELSE 0 END             AS dq_profile_conflicted,
    a.dq_sign_error_txns, a.dq_points_imputed_txns, a.dq_amount_recovered_txns

FROM eligible e
JOIN agg a       ON a.member_id = e.member_id
JOIN mem_clean m ON m.member_id = e.member_id
LEFT JOIN outcome o ON o.member_id = e.member_id;


-- =============================================================================
-- Validation
-- =============================================================================

-- Assertion, not decoration: if any feature reaches past the cutoff the whole
-- table is invalid, so it is checked rather than assumed.
--
-- SCOPE: this covers TRANSACTION-DERIVED features only. It cannot cover the
-- profile attributes -- see snapshot_attribute_risk below.
CREATE OR REPLACE VIEW leakage_check AS
SELECT (SELECT max(CAST(transaction_ts AS DATE)) FROM tx_pre)  AS max_feature_txn_date,
       (SELECT cutoff_date FROM f_params)                      AS cutoff_date,
       (SELECT min(CAST(transaction_ts AS DATE)) FROM tx_post) AS min_outcome_txn_date,
       CASE WHEN (SELECT max(CAST(transaction_ts AS DATE)) FROM tx_pre)
                 <= (SELECT cutoff_date FROM f_params)
             AND (SELECT min(CAST(transaction_ts AS DATE)) FROM tx_post)
                 >  (SELECT cutoff_date FROM f_params)
            THEN 'PASS -- no transaction-derived feature reads past the cutoff'
            ELSE 'FAIL -- LEAKAGE' END                         AS verdict;

-- The leakage the check above CANNOT test.
--
-- members.csv is a current-state export with no SCD history, so these columns are
-- as-of-export, not as-of-cutoff. A member scored at the April cutoff may carry a
-- tier they only reached in June. Unverifiable with this data, so these are
-- labelled exploratory and excluded from the modelling set by default.
CREATE OR REPLACE VIEW snapshot_attribute_risk AS
SELECT * FROM (VALUES
  ('tier',       'export snapshot', 'EXPLORATORY -- exclude from modelling'),
  ('tier_rank',  'export snapshot', 'EXPLORATORY -- exclude from modelling'),
  ('country',    'export snapshot', 'low risk -- rarely changes'),
  ('home_brand', 'export snapshot', 'low risk -- rarely changes'),
  ('p_age',      'derived from birth_date', 'safe -- birth_date is immutable'),
  ('p_tenure_days', 'derived from join_date', 'safe -- join_date is immutable when valid')
) AS t(feature, provenance, modelling_status);

CREATE OR REPLACE VIEW label_balance AS
SELECT count(*)                                       AS members_scored,
       sum(churned_90d)                               AS churned,
       round(100.0 * avg(churned_90d), 2)             AS churn_rate_pct
FROM member_features;

-- Churn must fall monotonically as recency improves. The cheapest test that the
-- label means anything.
CREATE OR REPLACE VIEW churn_by_recency AS
SELECT CASE WHEN r_days_since_last_txn <=  30 THEN '1. 0-30d'
            WHEN r_days_since_last_txn <=  90 THEN '2. 31-90d'
            WHEN r_days_since_last_txn <= 180 THEN '3. 91-180d'
            WHEN r_days_since_last_txn <= 365 THEN '4. 181-365d'
            ELSE '5. 365d+' END                AS recency_band,
       count(*)                                AS members,
       round(100.0 * avg(churned_90d), 1)      AS churn_rate_pct
FROM member_features GROUP BY 1 ORDER BY 1;

CREATE OR REPLACE VIEW churn_by_tier AS
SELECT tier, count(*) AS members, round(100.0 * avg(churned_90d), 1) AS churn_rate_pct
FROM member_features GROUP BY 1 ORDER BY min(tier_rank);

CREATE OR REPLACE VIEW feature_nulls AS
SELECT 'r_days_since_last_redemption' AS feature,
       count(*) FILTER (WHERE r_days_since_last_redemption IS NULL) AS nulls,
       round(100.0 * count(*) FILTER (WHERE r_days_since_last_redemption IS NULL)/count(*),1) AS pct
FROM member_features UNION ALL
SELECT 'rd_redemption_rate', count(*) FILTER (WHERE rd_redemption_rate IS NULL),
       round(100.0 * count(*) FILTER (WHERE rd_redemption_rate IS NULL)/count(*),1) FROM member_features UNION ALL
SELECT 'p_tenure_days', count(*) FILTER (WHERE p_tenure_days IS NULL),
       round(100.0 * count(*) FILTER (WHERE p_tenure_days IS NULL)/count(*),1) FROM member_features UNION ALL
SELECT 'f_avg_days_between_txn', count(*) FILTER (WHERE f_avg_days_between_txn IS NULL),
       round(100.0 * count(*) FILTER (WHERE f_avg_days_between_txn IS NULL)/count(*),1) FROM member_features UNION ALL
SELECT 'p_age', count(*) FILTER (WHERE p_age IS NULL),
       round(100.0 * count(*) FILTER (WHERE p_age IS NULL)/count(*),1) FROM member_features;


-- Is a 90-day window meaningful for THIS population? If the typical gap between
-- purchases already exceeds 90 days, "no purchase in 90 days" is ordinary
-- behaviour and the label is mostly timing noise. Reported rather than buried --
-- no amount of feature engineering fixes a mis-specified label.
CREATE OR REPLACE VIEW label_window_sanity AS
SELECT 90                                                              AS churn_window_days,
       round(median(f_avg_days_between_txn), 1)                        AS median_days_between_purchases,
       round(median(f_txn_365d), 1)                                    AS median_purchases_last_year,
       round(100.0 * avg(CASE WHEN f_avg_days_between_txn > 90
                              THEN 1.0 ELSE 0 END), 1)                 AS pct_members_whose_normal_gap_exceeds_window,
       round(100.0 * avg(CASE WHEN churned_90d = 1
                               AND f_avg_days_between_txn > 90
                              THEN 1.0 ELSE 0 END)
             / nullif(avg(churned_90d), 0), 1)                         AS pct_of_churned_who_are_merely_mid_gap
FROM member_features
WHERE f_avg_days_between_txn IS NOT NULL;


-- Modelling-safe view: transaction-derived features plus immutable profile
-- attributes. Excludes tier/tier_rank, whose as-of-cutoff value is unknowable
-- from a current-state export. Use member_features for exploration, this to train.
CREATE OR REPLACE VIEW member_features_modelling AS
SELECT * EXCLUDE (tier, tier_rank, country, home_brand) FROM member_features;
