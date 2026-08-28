-- Which brand actually rewards a dollar of spend most generously?
--
-- Expects common/clean.sql. This part also rebuilds the RAW view on purpose: the
-- finding is not the clean number, it is that cleaning inverts the ranking.

-- What an analyst gets by loading the CSV and computing the obvious ratio.
CREATE OR REPLACE TABLE tx_naive AS
SELECT transaction_id, member_id,
       to_num(amount)        AS amount,
       to_num(points_earned) AS points_earned,
       to_num(points_redeemed) AS points_redeemed,
       brand
FROM tx_raw;

-- The naive answer. sum(points)/sum(amount) is how such a claim is normally
-- produced -- and here it ranks the most generous brand last.
CREATE OR REPLACE VIEW g1_naive AS
SELECT brand,
       count(*)                                          AS txns,
       round(sum(amount), 2)                             AS total_spend,
       sum(points_earned)                                AS total_points,
       round(sum(points_earned) / sum(amount), 4)        AS points_per_dollar,
       rank() OVER (ORDER BY sum(points_earned) / sum(amount) DESC) AS generosity_rank
FROM tx_naive GROUP BY 1 ORDER BY points_per_dollar DESC;

-- The cleaned answer. Sentinel amounts excluded, replays deduped, sign errors
-- repaired, null points imputed -- see common/clean.sql for each.
CREATE OR REPLACE VIEW g2_clean AS
SELECT brand,
       count(*)                                          AS txns,
       round(sum(amount), 2)                             AS total_spend,
       sum(points_earned)                                AS total_points,
       round(sum(points_earned) / sum(amount), 4)        AS points_per_dollar,
       round(median(points_earned / amount), 4)          AS median_ppd,
       round(stddev(points_earned / amount), 6)          AS sd_ppd,
       rank() OVER (ORDER BY sum(points_earned) / sum(amount) DESC) AS generosity_rank
FROM tx_clean
WHERE amount > 0 AND points_earned IS NOT NULL AND NOT flag_amount_recovered
GROUP BY 1 ORDER BY points_per_dollar DESC;

-- How far each fix moves each brand. Answers "what did I clean to trust this"
-- with a number rather than a list of steps -- and shows where the rank flips.
CREATE OR REPLACE VIEW g3_contamination AS
WITH steps AS (
    SELECT 'A. raw (nothing cleaned)' AS step, brand,
           sum(points_earned) / sum(amount) AS ppd FROM tx_naive GROUP BY 2
    UNION ALL
    SELECT 'B. drop 15 sentinel amounts', brand,
           sum(points_earned) / sum(amount) FROM tx_naive WHERE amount < 10000 GROUP BY 2
    UNION ALL
    SELECT 'C. + repair sign errors', brand,
           sum(points_earned) / sum(abs(amount)) FROM tx_naive WHERE amount < 10000 GROUP BY 2
    UNION ALL
    SELECT 'D. + dedup replays, impute points (final)', brand,
           sum(points_earned) / sum(amount) FROM tx_clean
           WHERE amount > 0 AND points_earned IS NOT NULL AND NOT flag_amount_recovered GROUP BY 2
)
SELECT step,
       round(max(ppd) FILTER (WHERE brand='PulseEats'), 4) AS PulseEats,
       round(max(ppd) FILTER (WHERE brand='PulseHome'), 4) AS PulseHome,
       round(max(ppd) FILTER (WHERE brand='PulseMart'), 4) AS PulseMart,
       arg_max(brand, ppd)                                 AS ranked_most_generous
FROM steps GROUP BY 1 ORDER BY 1;

-- The 15 rows, and the phantom dollars they add to each brand's denominator.
CREATE OR REPLACE VIEW g4_sentinel_impact AS
SELECT brand,
       count(*)                                    AS sentinel_rows,
       round(sum(amount), 2)                       AS phantom_dollars,
       round(sum(amount) / (SELECT sum(amount) FROM tx_naive
                            WHERE brand = t.brand AND amount < 10000) * 100, 1)
                                                   AS pct_inflation_of_denominator
FROM tx_naive t WHERE amount > 10000 GROUP BY 1 ORDER BY phantom_dollars DESC;

-- Every framing a marketing team could plausibly have used. A single number
-- cannot show whether a metric is trustworthy; a stability analysis can.
CREATE OR REPLACE VIEW g5_framings AS
WITH base AS (
    SELECT * FROM tx_clean
    WHERE amount > 0 AND points_earned IS NOT NULL AND NOT flag_amount_recovered
),
per_member AS (
    SELECT member_id, brand, sum(points_earned) AS pts, sum(amount) AS amt
    FROM base GROUP BY 1, 2
)
SELECT 'F1 ratio of sums  sum(pts)/sum(amt)' AS framing,
       round(max(v) FILTER (WHERE brand='PulseEats'),3) AS PulseEats,
       round(max(v) FILTER (WHERE brand='PulseHome'),3) AS PulseHome,
       round(max(v) FILTER (WHERE brand='PulseMart'),3) AS PulseMart,
       arg_max(brand, v) AS winner
FROM (SELECT brand, sum(points_earned)/sum(amount) AS v FROM base GROUP BY 1)
UNION ALL
SELECT 'F2 mean of per-txn ratios',
       round(max(v) FILTER (WHERE brand='PulseEats'),3), round(max(v) FILTER (WHERE brand='PulseHome'),3),
       round(max(v) FILTER (WHERE brand='PulseMart'),3), arg_max(brand, v)
FROM (SELECT brand, avg(points_earned/amount) AS v FROM base GROUP BY 1)
UNION ALL
SELECT 'F3 median of per-txn ratios',
       round(max(v) FILTER (WHERE brand='PulseEats'),3), round(max(v) FILTER (WHERE brand='PulseHome'),3),
       round(max(v) FILTER (WHERE brand='PulseMart'),3), arg_max(brand, v)
FROM (SELECT brand, median(points_earned/amount) AS v FROM base GROUP BY 1)
UNION ALL
SELECT 'F4 mean of per-MEMBER ratios',
       round(max(v) FILTER (WHERE brand='PulseEats'),3), round(max(v) FILTER (WHERE brand='PulseHome'),3),
       round(max(v) FILTER (WHERE brand='PulseMart'),3), arg_max(brand, v)
FROM (SELECT brand, avg(pts/amt) AS v FROM per_member GROUP BY 1)
UNION ALL
SELECT 'F5 mean points per transaction',
       round(max(v) FILTER (WHERE brand='PulseEats'),3), round(max(v) FILTER (WHERE brand='PulseHome'),3),
       round(max(v) FILTER (WHERE brand='PulseMart'),3), arg_max(brand, v)
FROM (SELECT brand, avg(points_earned) AS v FROM base GROUP BY 1)
UNION ALL
SELECT 'F6 total points issued',
       round(max(v) FILTER (WHERE brand='PulseEats'),3), round(max(v) FILTER (WHERE brand='PulseHome'),3),
       round(max(v) FILTER (WHERE brand='PulseMart'),3), arg_max(brand, v)
FROM (SELECT brand, sum(points_earned) AS v FROM base GROUP BY 1)
UNION ALL
SELECT 'F7 points per member',
       round(max(v) FILTER (WHERE brand='PulseEats'),3), round(max(v) FILTER (WHERE brand='PulseHome'),3),
       round(max(v) FILTER (WHERE brand='PulseMart'),3), arg_max(brand, v)
FROM (SELECT brand, sum(points_earned)/count(DISTINCT member_id) AS v FROM base GROUP BY 1)
UNION ALL
-- Wrong join key: attribute spend to the member's home brand rather than where
-- it happened. 9.3% of transactions are cross-brand, so this trap is live.
SELECT 'F8 grouped by MEMBER brand (wrong key)',
       round(max(v) FILTER (WHERE brand='PulseEats'),3), round(max(v) FILTER (WHERE brand='PulseHome'),3),
       round(max(v) FILTER (WHERE brand='PulseMart'),3), arg_max(brand, v)
FROM (SELECT m.home_brand AS brand, sum(b.points_earned)/sum(b.amount) AS v
      FROM base b JOIN mem_clean m USING (member_id) GROUP BY 1);

-- Is the brand gap really a tier-mix or basket-mix effect?
CREATE OR REPLACE VIEW g6_tier_confound AS
SELECT m.tier,
       round(max(v) FILTER (WHERE brand='PulseEats'),4) AS PulseEats,
       round(max(v) FILTER (WHERE brand='PulseHome'),4) AS PulseHome,
       round(max(v) FILTER (WHERE brand='PulseMart'),4) AS PulseMart
FROM (SELECT t.brand, mm.tier, sum(t.points_earned)/sum(t.amount) AS v
      FROM tx_clean t JOIN mem_clean mm USING (member_id)
      WHERE t.amount > 0 AND t.points_earned IS NOT NULL AND NOT t.flag_amount_recovered
      GROUP BY 1,2) m
GROUP BY 1 ORDER BY 1;

CREATE OR REPLACE VIEW g7_basket_confound AS
SELECT brand, count(*) AS txns,
       round(avg(amount), 2) AS avg_basket, round(median(amount), 2) AS median_basket
FROM tx_clean
WHERE amount > 0 AND points_earned IS NOT NULL AND NOT flag_amount_recovered
GROUP BY 1 ORDER BY 1;

-- Points per dollar only ranks generosity if a point is worth the same at every
-- brand, and nothing here states a redemption value. Redemption behaviour is the
-- only available proxy, and a weak one.
CREATE OR REPLACE VIEW g8_point_utility_proxy AS
SELECT brand,
       sum(points_earned)                                              AS points_issued,
       sum(points_redeemed)                                            AS points_redeemed,
       round(100.0 * sum(points_redeemed) / sum(points_earned), 2)     AS pct_points_redeemed,
       round(100.0 * avg(CASE WHEN points_redeemed > 0 THEN 1.0 ELSE 0 END), 2) AS pct_txns_with_redemption,
       round(avg(points_redeemed) FILTER (WHERE points_redeemed > 0), 1) AS avg_redemption_size
FROM tx_clean
WHERE amount > 0 AND points_earned IS NOT NULL AND NOT flag_amount_recovered
GROUP BY 1 ORDER BY 1;

-- What would have to be true for marketing to be right? Quantifying the
-- objection turns "the framing ignores point value" -- unfalsifiable, easy to
-- wave away -- into a specific multiple checkable against the rewards catalogue.
CREATE OR REPLACE VIEW g9_breakeven AS
WITH r AS (
    SELECT brand, sum(points_earned) / sum(amount) AS earn_rate
    FROM tx_clean
    WHERE amount > 0 AND points_earned IS NOT NULL AND NOT flag_amount_recovered
    GROUP BY 1
),
eats AS (SELECT earn_rate AS e FROM r WHERE brand = 'PulseEats')
SELECT r.brand,
       round(r.earn_rate, 3)                             AS earn_rate_pts_per_dollar,
       round(r.earn_rate / e.e, 3)                       AS required_value_multiple,
       CASE WHEN r.brand = 'PulseEats' THEN 'baseline'
            ELSE 'a PulseEats point must be worth >= '
                 || round(r.earn_rate / e.e, 2) || 'x a ' || r.brand || ' point'
       END                                               AS what_marketing_needs_to_be_true
FROM r, eats e ORDER BY r.earn_rate DESC;

-- Indirect evidence on relative point value: if redemptions buy broadly similar
-- rewards, needing fewer points per redemption implies more valuable points.
-- Suggestive only -- redemption size also tracks accumulated balance.
CREATE OR REPLACE VIEW g10_redemption_size_signal AS
WITH s AS (
    SELECT brand, avg(points_redeemed) FILTER (WHERE points_redeemed > 0) AS avg_redemption
    FROM tx_clean
    WHERE amount > 0 AND points_earned IS NOT NULL AND NOT flag_amount_recovered
    GROUP BY 1
),
eats AS (SELECT avg_redemption AS e FROM s WHERE brand = 'PulseEats')
SELECT s.brand, round(s.avg_redemption, 1) AS avg_points_per_redemption,
       round(s.avg_redemption / e.e, 3)    AS implied_point_value_vs_eats
FROM s, eats e ORDER BY 2;
