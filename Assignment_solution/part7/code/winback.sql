-- Win-back campaign list. Expects common/clean.sql.
--
-- Central judgement: "slipping away" is measured against each member's own
-- rhythm, not a calendar threshold. The median member buys every ~204 days, so a
-- fixed "no purchase in 90 days" rule flags 48% of the base while still missing
-- an at-risk weekly shopper silent for 60 days.
--
--     overdue_ratio = days_since_last_purchase / personal_avg_gap

CREATE OR REPLACE TABLE wb_params AS
SELECT CAST(max(transaction_ts) AS DATE) AS as_of_date FROM tx_clean;

-- Behavioural profile over all available history.
CREATE OR REPLACE TABLE wb_profile AS
SELECT t.member_id,
       count(*)                                                    AS n_txns,
       min(CAST(t.transaction_ts AS DATE))                         AS first_txn,
       max(CAST(t.transaction_ts AS DATE))                         AS last_txn,
       date_diff('day', max(CAST(t.transaction_ts AS DATE)), p.as_of_date) AS days_since_last,
       date_diff('day', min(CAST(t.transaction_ts AS DATE)),
                        max(CAST(t.transaction_ts AS DATE)))       AS active_span_days,
       round(sum(t.amount), 2)                                     AS lifetime_spend,
       round(avg(t.amount), 2)                                     AS avg_basket,
       sum(t.points_earned) - sum(t.points_redeemed)               AS points_balance,
       count(*) FILTER (WHERE t.points_redeemed > 0)               AS redemptions,
       count(DISTINCT t.channel)                                   AS channels_used,
       count(DISTINCT t.brand)                                     AS brands_used,
       mode(t.brand)                                               AS main_brand
FROM tx_clean t, wb_params p
GROUP BY t.member_id, p.as_of_date;

-- Personal rhythm, and how far past it each member is.
CREATE OR REPLACE TABLE wb_signals AS
SELECT w.*,
       CASE WHEN n_txns > 1 THEN round(active_span_days::DOUBLE / (n_txns - 1), 1) END AS avg_gap_days,
       CASE WHEN n_txns > 1 AND active_span_days > 0
            THEN round(days_since_last / (active_span_days::DOUBLE / (n_txns - 1)), 2) END AS overdue_ratio,
       -- Spend rate while engaged. Trailing-year spend scores every lapsed member
       -- near zero -- it would deprioritise exactly the people being targeted.
       CASE WHEN active_span_days >= 90
            THEN round(lifetime_spend / (active_span_days / 365.0), 2) END AS annualised_spend
FROM wb_profile w;

-- Exclusions, applied in order and counted so the funnel is auditable.
CREATE OR REPLACE TABLE wb_candidates AS
WITH dup_emails AS (            -- DQ-12: 20 emails span multiple member_ids
    SELECT lower(trim(email)) AS em FROM mem_clean
    GROUP BY 1 HAVING count(DISTINCT member_id) > 1
)
SELECT s.*, m.tier, m.tier_rank, m.country, m.home_brand, m.email,
       m.flag_profile_conflicted,
       (d.em IS NOT NULL) AS flag_shared_email
FROM wb_signals s
JOIN mem_clean m USING (member_id)          -- DQ-06: drops orphans, they have no profile
LEFT JOIN dup_emails d ON d.em = lower(trim(m.email));

CREATE OR REPLACE VIEW wb_exclusion_funnel AS
WITH f AS (SELECT * FROM wb_candidates)
SELECT * FROM (VALUES
  ('0. members with any transaction',           (SELECT count(*) FROM wb_signals)),
  ('1. minus orphans with no profile (DQ-06)',  (SELECT count(*) FROM f)),
  ('2. minus fewer than 4 purchases',           (SELECT count(*) FROM f WHERE n_txns >= 4)),
  ('3. minus active span under 365d',           (SELECT count(*) FROM f WHERE n_txns >= 4 AND active_span_days >= 365)),
  ('4. minus not yet overdue (ratio < 1.5)',    (SELECT count(*) FROM f WHERE n_txns >= 4 AND active_span_days >= 365
                                                   AND overdue_ratio >= 1.5)),
  ('5. minus likely unrecoverable (ratio > 4)', (SELECT count(*) FROM f WHERE n_txns >= 4 AND active_span_days >= 365
                                                   AND overdue_ratio BETWEEN 1.5 AND 4)),
  ('6. minus gone > 540 days (absolute cap)',   (SELECT count(*) FROM f WHERE n_txns >= 4 AND active_span_days >= 365
                                                   AND overdue_ratio BETWEEN 1.5 AND 4 AND days_since_last <= 540)),
  ('7. minus silent < 60 days (too early)',     (SELECT count(*) FROM f WHERE n_txns >= 4 AND active_span_days >= 365
                                                   AND overdue_ratio BETWEEN 1.5 AND 4 AND days_since_last BETWEEN 60 AND 540)),
  ('8. minus conflicted profile (DQ-03)',       (SELECT count(*) FROM f WHERE n_txns >= 4 AND active_span_days >= 365
                                                   AND overdue_ratio BETWEEN 1.5 AND 4 AND days_since_last BETWEEN 60 AND 540
                                                   AND NOT flag_profile_conflicted)),
  ('9. minus shared email (DQ-12)',             (SELECT count(*) FROM f WHERE n_txns >= 4 AND active_span_days >= 365
                                                   AND overdue_ratio BETWEEN 1.5 AND 4 AND days_since_last BETWEEN 60 AND 540
                                                   AND NOT flag_profile_conflicted AND NOT flag_shared_email)),
  ('10. FINAL eligible pool',                   (SELECT count(*) FROM f WHERE n_txns >= 4 AND active_span_days >= 365
                                                   AND overdue_ratio BETWEEN 1.5 AND 4 AND days_since_last BETWEEN 60 AND 540
                                                   AND NOT flag_profile_conflicted AND NOT flag_shared_email
                                                   AND annualised_spend IS NOT NULL))
) AS t(step, members_remaining);

-- CORRECTED. The first version required only n_txns >= 3 with no constraint on how
-- long the member had been active, and the resulting list was an artifact:
-- the selected 20 averaged a 197-day active span against 509 for the pool, because
-- annualising a short burst extrapolates it wildly. Members active <180 days show
-- avg annualised spend of 742 on avg lifetime spend of 273 -- a 2.7x inflation --
-- while members active 2y+ show 156 against 409. The ranking was selecting
-- SHORT SPANS, not high value.
--
-- Requiring a demonstrated year-long relationship fixes the statistics and is the
-- right business rule independently: three purchases in four months followed by
-- silence is a failed onboarding, which needs a different campaign and a different
-- offer than a member who shopped steadily for two years and then stopped.
CREATE OR REPLACE TABLE wb_eligible AS
SELECT * FROM wb_candidates
WHERE n_txns >= 4                              -- enough purchases for a stable rhythm
  AND active_span_days >= 365                  -- a real relationship, and a grounded rate
  AND overdue_ratio BETWEEN 1.5 AND 4          -- overdue, but not so long they are gone
  AND days_since_last BETWEEN 60 AND 540       -- absolute guardrails on the ratio
  AND NOT flag_profile_conflicted              -- DQ-03: cannot trust their tier
  AND NOT flag_shared_email                    -- DQ-12: would contact one person twice
  AND annualised_spend IS NOT NULL;

-- Value at risk, discounted for absolute silence since response rates decay.
-- The decay is capped at 40% so it tilts the ranking without letting a slightly
-- fresher mid-value member outrank a far more valuable one.
CREATE OR REPLACE TABLE wb_scored AS
SELECT *,
       round(annualised_spend * (1 - 0.4 * (days_since_last - 60) / 480.0), 2) AS winback_score
FROM wb_eligible;

CREATE OR REPLACE TABLE wb_target_list AS
SELECT row_number() OVER (ORDER BY winback_score DESC) AS rank,
       member_id, tier, main_brand, country,
       n_txns, active_span_days, lifetime_spend, annualised_spend, avg_basket,
       first_txn, last_txn, days_since_last, avg_gap_days, overdue_ratio,
       points_balance, redemptions, channels_used, brands_used,
       winback_score
FROM wb_scored ORDER BY winback_score DESC LIMIT 20;

-- Is the list a monoculture, and how does it compare with the base?
CREATE OR REPLACE VIEW wb_list_composition AS
SELECT 'tier' AS dimension, tier AS value, count(*) AS members FROM wb_target_list GROUP BY 1,2
UNION ALL SELECT 'brand', main_brand, count(*) FROM wb_target_list GROUP BY 1,2
UNION ALL SELECT 'country', country, count(*) FROM wb_target_list GROUP BY 1,2
ORDER BY 1, 3 DESC;

CREATE OR REPLACE VIEW wb_list_vs_base AS
SELECT 'selected 20' AS cohort, count(*) AS members,
       round(avg(active_span_days),0)  AS avg_active_span_days,
       round(avg(annualised_spend),2) AS avg_annualised_spend,
       round(avg(lifetime_spend),2)   AS avg_lifetime_spend,
       round(avg(days_since_last),1)  AS avg_days_since_last,
       round(avg(overdue_ratio),2)    AS avg_overdue_ratio,
       round(avg(points_balance),0)   AS avg_points_balance
FROM wb_target_list
UNION ALL
SELECT 'eligible pool', count(*), round(avg(active_span_days),0), round(avg(annualised_spend),2), round(avg(lifetime_spend),2),
       round(avg(days_since_last),1), round(avg(overdue_ratio),2), round(avg(points_balance),0)
FROM wb_eligible
UNION ALL
SELECT 'all profiled members', count(*), round(avg(active_span_days),0), round(avg(annualised_spend),2), round(avg(lifetime_spend),2),
       round(avg(days_since_last),1), round(avg(overdue_ratio),2), round(avg(points_balance),0)
FROM wb_candidates;

-- What a fixed-threshold rule would have picked instead: the comparison that
-- justifies the personal-rhythm approach rather than merely asserting it.
CREATE OR REPLACE VIEW wb_vs_naive_rule AS
WITH naive AS (
    SELECT member_id FROM wb_candidates
    WHERE days_since_last > 90 AND lifetime_spend IS NOT NULL
    ORDER BY lifetime_spend DESC LIMIT 20
)
SELECT (SELECT count(*) FROM wb_candidates WHERE days_since_last > 90)      AS naive_rule_flags_members,
       (SELECT count(*) FROM wb_eligible)                                   AS rhythm_rule_eligible,
       (SELECT count(*) FROM naive n JOIN wb_target_list t USING (member_id)) AS overlap_in_top_20,
       (SELECT round(avg(overdue_ratio), 2) FROM wb_candidates n
         JOIN naive USING (member_id))                                      AS naive_pick_avg_overdue_ratio,
       (SELECT round(avg(overdue_ratio), 2) FROM wb_target_list)            AS our_pick_avg_overdue_ratio;
