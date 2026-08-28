-- Outstanding points liability. Expects common/clean.sql.
--
-- The points arithmetic is near-exact. The dollar figure rests on two things the
-- data cannot supply -- what a point is worth, and what share will ever be
-- redeemed -- so this measures what is measurable, isolates what is assumed, and
-- prices how far the answer moves when the assumptions move.

CREATE OR REPLACE TABLE lb_params AS
SELECT CAST(max(transaction_ts) AS DATE) AS as_of_date FROM tx_clean;

-- Measured: gross outstanding points.
--
-- Summed from per-member balances floored at zero, not from the raw column totals.
-- Five members show a negative balance (-225 points in total) because redemptions
-- can be recorded against points earned outside this window. A member cannot owe
-- the programme points, so a negative balance is not a receivable to net off --
-- it is a data artefact. The floor moves the total by 225 points (~$0.02 of
-- liability) and makes the accounting logic defensible rather than merely close.
CREATE OR REPLACE VIEW l1_gross_points AS
WITH per_member AS (
    SELECT member_id,
           sum(points_earned)   AS earned,
           sum(points_redeemed) AS redeemed,
           greatest(sum(points_earned) - sum(points_redeemed), 0) AS balance
    FROM tx_clean GROUP BY 1
)
SELECT sum(earned)                                 AS points_earned,
       sum(redeemed)                               AS points_redeemed,
       sum(balance)                                AS points_outstanding,
       round(100.0 * sum(redeemed) / sum(earned), 2) AS pct_redeemed_to_date,
       count(*)                                    AS members,
       count(*) FILTER (WHERE earned - redeemed < 0) AS members_floored
FROM per_member;

CREATE OR REPLACE VIEW l2_by_brand AS
SELECT brand,
       sum(points_earned) - sum(points_redeemed)   AS points_outstanding,
       round(100.0 * sum(points_redeemed) / sum(points_earned), 2) AS pct_redeemed,
       count(DISTINCT member_id)                   AS members
FROM tx_clean GROUP BY 1 ORDER BY points_outstanding DESC;

-- Orphan members hold real points. The obligation exists whether or not we can
-- identify the counterparty, so they are quantified rather than dropped --
-- excluding them would understate a liability, which is the wrong direction.
CREATE OR REPLACE VIEW l3_orphan_exposure AS
SELECT CASE WHEN m.member_id IS NULL THEN 'orphan (no profile, DQ-06)'
            ELSE 'identifiable member' END        AS population,
       count(DISTINCT t.member_id)                AS members,
       sum(t.points_earned) - sum(t.points_redeemed) AS points_outstanding
FROM tx_clean t LEFT JOIN mem_clean m USING (member_id)
GROUP BY 1 ORDER BY 2 DESC;

-- Will these points ever be redeemed? Only 9.3% have been, and two explanations
-- fit -- a young programme still accumulating, or members who simply do not
-- redeem. They imply liabilities ~10x apart, and cohort age separates them: if
-- redemption were merely slow, older cohorts would show materially more of it.
CREATE OR REPLACE VIEW l4_cohort_burndown AS
WITH first_seen AS (
    SELECT member_id, min(CAST(transaction_ts AS DATE)) AS first_txn
    FROM tx_clean GROUP BY 1
)
SELECT year(f.first_txn)                                             AS cohort_year,
       count(DISTINCT t.member_id)                                   AS members,
       round(avg(date_diff('day', f.first_txn,
                 (SELECT as_of_date FROM lb_params))) / 365.0, 1)    AS avg_years_since_joining,
       sum(t.points_earned)                                          AS points_earned,
       sum(t.points_redeemed)                                        AS points_redeemed,
       round(100.0 * sum(t.points_redeemed) / sum(t.points_earned), 2) AS pct_redeemed
FROM tx_clean t JOIN first_seen f USING (member_id)
GROUP BY 1 ORDER BY 1;

-- Redemption is only observable inside a purchase row, so a member who redeems
-- without buying is invisible. Observed redemption is a floor, and the liability
-- computed from it a ceiling.
CREATE OR REPLACE VIEW l5_redemption_mechanics AS
SELECT count(*)                                                        AS txns,
       count(*) FILTER (WHERE points_redeemed > 0)                     AS txns_with_redemption,
       round(100.0 * avg(CASE WHEN points_redeemed > 0 THEN 1.0 ELSE 0 END), 2) AS pct_txns_redeeming,
       max(points_redeemed)                                            AS max_single_redemption,
       round(avg(points_redeemed) FILTER (WHERE points_redeemed > 0), 1) AS avg_redemption,
       count(DISTINCT member_id) FILTER (WHERE points_redeemed > 0)    AS members_who_ever_redeemed,
       count(DISTINCT member_id)                                       AS members_total
FROM tx_clean;

-- Points held by members who look gone: still owed, far less likely to be
-- claimed, and the main driver of any breakage estimate.
CREATE OR REPLACE VIEW l6_balance_by_dormancy AS
WITH b AS (
    SELECT member_id,
           greatest(sum(points_earned) - sum(points_redeemed), 0) AS bal,
           date_diff('day', max(CAST(transaction_ts AS DATE)),
                     (SELECT as_of_date FROM lb_params)) AS days_since_last
    FROM tx_clean GROUP BY 1
)
SELECT CASE WHEN days_since_last <=  90 THEN '1. active (0-90d)'
            WHEN days_since_last <= 365 THEN '2. slowing (91-365d)'
            WHEN days_since_last <= 730 THEN '3. dormant (1-2y)'
            ELSE '4. likely gone (2y+)' END AS segment,
       count(*)                             AS members,
       sum(bal)                             AS points_outstanding,
       round(100.0 * sum(bal) / (SELECT sum(bal) FROM b), 1) AS pct_of_total
FROM b GROUP BY 1 ORDER BY 1;

-- The clearest breakage signal, and the one immune to the cohort test's dilution:
-- what share of members have never redeemed a single point, ever.
CREATE OR REPLACE VIEW l6b_never_redeemed AS
WITH m AS (
    SELECT member_id, sum(points_redeemed) AS redeemed,
           sum(points_earned) - sum(points_redeemed) AS bal
    FROM tx_clean GROUP BY 1
)
SELECT count(*)                                                  AS members,
       count(*) FILTER (WHERE redeemed = 0)                      AS never_redeemed,
       round(100.0 * avg(CASE WHEN redeemed = 0 THEN 1.0 ELSE 0 END), 1) AS pct_never_redeemed,
       sum(bal) FILTER (WHERE redeemed = 0)                      AS points_held_by_never_redeemers,
       round(100.0 * sum(bal) FILTER (WHERE redeemed = 0) / sum(bal), 1) AS pct_of_liability
FROM m;

-- Point value is absent from the data, so it is anchored to the earn rate: at
-- $0.01 the brands return 1.75-2.30% of spend, normal for retail loyalty. That
-- reasoning is what makes $0.01 defensible rather than round. Still an assumption.
CREATE OR REPLACE VIEW l7_point_value_anchor AS
SELECT brand, round(earn_rate, 3) AS points_per_dollar,
       round(earn_rate * 0.005, 4) AS pct_back_at_half_cent,
       round(earn_rate * 0.010, 4) AS pct_back_at_one_cent,
       round(earn_rate * 0.015, 4) AS pct_back_at_1_5_cent
FROM brand_rate ORDER BY 1;

-- Ultimate redemption of 25%. Observed redemption is 9.3% and flat across cohort
-- age, and 63% of members have never redeemed -- but observed redemption is a
-- floor, no expiry policy is known, and a liability should not be understated.
-- So 25% sits deliberately above the data and below a generic retail default.
-- It is a judgement, which is why l9_sensitivity exists.
CREATE OR REPLACE VIEW l8_headline_liability AS
SELECT points_outstanding,
       0.01                                                AS assumed_value_per_point,
       0.25                                                AS assumed_ultimate_redemption_rate,
       round(points_outstanding * 0.01, 2)                 AS gross_liability_usd,
       round(points_outstanding * 0.01 * 0.25, 2)          AS net_liability_usd,
       round(points_outstanding * 0.01 * 0.15, 2)          AS low_case_usd,
       round(points_outstanding * 0.01 * 0.50, 2)          AS high_case_usd
FROM l1_gross_points;

-- Both assumptions at once. The answer is a surface, not a scalar, and the
-- reader should see how wide it is: this grid spans 20x.
CREATE OR REPLACE VIEW l9_sensitivity AS
WITH p AS (SELECT points_outstanding AS pts FROM l1_gross_points),
     v(value_per_point) AS (VALUES (0.005), (0.0075), (0.010), (0.0125), (0.015)),
     r(redemption_rate) AS (VALUES (0.15), (0.25), (0.35), (0.50), (1.00))
SELECT v.value_per_point,
       round(max(CASE WHEN r.redemption_rate=0.15 THEN p.pts*v.value_per_point*r.redemption_rate END),0) AS "15pct_redeemed",
       round(max(CASE WHEN r.redemption_rate=0.25 THEN p.pts*v.value_per_point*r.redemption_rate END),0) AS "25pct_redeemed",
       round(max(CASE WHEN r.redemption_rate=0.35 THEN p.pts*v.value_per_point*r.redemption_rate END),0) AS "35pct_redeemed",
       round(max(CASE WHEN r.redemption_rate=0.50 THEN p.pts*v.value_per_point*r.redemption_rate END),0) AS "50pct_redeemed",
       round(max(CASE WHEN r.redemption_rate=1.00 THEN p.pts*v.value_per_point*r.redemption_rate END),0) AS "100pct_no_breakage"
FROM p, v, r GROUP BY 1 ORDER BY 1;

-- How much of the figure rests on my own repairs rather than on source data.
CREATE OR REPLACE VIEW l10_repair_exposure AS
SELECT 'points imputed where source was NULL (DQ-11)' AS source,
       sum(points_earned) FILTER (WHERE flag_points_imputed) AS points,
       round(100.0 * sum(points_earned) FILTER (WHERE flag_points_imputed)
             / sum(points_earned), 3)                        AS pct_of_issued
FROM tx_clean
UNION ALL
SELECT 'points on sign-error rows (DQ-07)',
       sum(points_earned) FILTER (WHERE flag_sign_error),
       round(100.0 * sum(points_earned) FILTER (WHERE flag_sign_error) / sum(points_earned), 3)
FROM tx_clean
UNION ALL
SELECT 'points on recovered-amount rows (DQ-02)',
       sum(points_earned) FILTER (WHERE flag_amount_recovered),
       round(100.0 * sum(points_earned) FILTER (WHERE flag_amount_recovered) / sum(points_earned), 3)
FROM tx_clean
UNION ALL
SELECT 'points removed with replayed rows (DQ-04)',
       (SELECT sum(points_earned) FROM tx_typed) - (SELECT sum(points_earned) FROM tx_dedup),
       round(100.0 * ((SELECT sum(points_earned) FROM tx_typed) - (SELECT sum(points_earned) FROM tx_dedup))
             / (SELECT sum(points_earned) FROM tx_clean), 3);
