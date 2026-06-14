USE job_market;
SHOW FULL TABLES WHERE Table_type = 'VIEW';
-- VIEW 1: Skill Demand Velocity
CREATE OR REPLACE VIEW vw_skill_velocity AS
WITH weekly_counts AS (
    SELECT
        s.skill_name,
        s.skill_category,
        d.week_number,
        d.year,
        COUNT(*) AS weekly_mentions
    FROM fact_skill_listings fsl
    JOIN dim_skill         s   ON fsl.skill_id   = s.skill_id
    JOIN fact_job_listings fjl ON fsl.listing_id = fjl.listing_id
    JOIN dim_date          d   ON fjl.date_id    = d.date_id
    GROUP BY s.skill_name, s.skill_category, d.week_number, d.year
),
with_rolling AS (
    SELECT *,
        ROUND(AVG(weekly_mentions) OVER (
            PARTITION BY skill_name
            ORDER BY year, week_number
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ), 1) AS rolling_4wk_avg
    FROM weekly_counts
)
SELECT
    skill_name,
    skill_category,
    week_number,
    year,
    weekly_mentions,
    rolling_4wk_avg,
    ROUND(weekly_mentions / NULLIF(rolling_4wk_avg, 0), 2) AS velocity,
    CASE
        WHEN weekly_mentions / NULLIF(rolling_4wk_avg, 0) >= 1.2 THEN 'RISING'
        WHEN weekly_mentions / NULLIF(rolling_4wk_avg, 0) <= 0.8 THEN 'DECLINING'
        ELSE 'STABLE'
    END AS trend_label
FROM with_rolling
WHERE rolling_4wk_avg IS NOT NULL;

-- ── VIEW 2: Hiring Difficulty ─────────────────────────────────
CREATE OR REPLACE VIEW vw_hiring_difficulty AS
SELECT
    r.role_category,
    l.city,
    l.tier,
    COUNT(DISTINCT fjl.listing_id)          AS open_roles,
    COALESCE(SUM(fjl.applicant_count), 0)   AS total_applicants,
    ROUND(
        COUNT(DISTINCT fjl.listing_id) * 100.0
        / NULLIF(SUM(fjl.applicant_count), 0), 4
    )                                        AS difficulty_score,
    RANK() OVER (
        PARTITION BY l.city
        ORDER BY COUNT(DISTINCT fjl.listing_id) * 1.0
                 / NULLIF(SUM(fjl.applicant_count), 0) DESC
    )                                        AS city_difficulty_rank
FROM fact_job_listings  fjl
JOIN dim_role     r ON fjl.role_id     = r.role_id
JOIN dim_location l ON fjl.location_id = l.location_id
GROUP BY r.role_category, l.city, l.tier;

-- ── VIEW 3: Salary Intelligence ───────────────────────────────
CREATE OR REPLACE VIEW vw_salary_intelligence AS
WITH monthly AS (
    SELECT
        r.role_category,
        r.exp_level,
        l.city,
        d.month,
        d.year,
        ROUND(AVG((fjl.salary_min + fjl.salary_max) / 2.0), 1) AS avg_mid_salary,
        MIN(fjl.salary_min)                                      AS min_salary,
        MAX(fjl.salary_max)                                      AS max_salary,
        COUNT(*)                                                 AS listing_count
    FROM fact_job_listings fjl
    JOIN dim_role     r ON fjl.role_id     = r.role_id
    JOIN dim_location l ON fjl.location_id = l.location_id
    JOIN dim_date     d ON fjl.date_id     = d.date_id
    WHERE fjl.salary_min IS NOT NULL
    GROUP BY r.role_category, r.exp_level, l.city, d.month, d.year
)
SELECT *,
    LAG(avg_mid_salary) OVER (
        PARTITION BY role_category, exp_level, city
        ORDER BY year, month
    ) AS prev_month_salary,
    ROUND(
        (avg_mid_salary - LAG(avg_mid_salary) OVER (
            PARTITION BY role_category, exp_level, city
            ORDER BY year, month
        )) * 100.0 / NULLIF(LAG(avg_mid_salary) OVER (
            PARTITION BY role_category, exp_level, city
            ORDER BY year, month
        ), 0)
    , 2) AS mom_pct_change
FROM monthly;

-- ── VIEW 4: Skill Co-occurrence ───────────────────────────────
CREATE OR REPLACE VIEW vw_skill_cooccurrence AS
SELECT
    s1.skill_name        AS skill_a,
    s2.skill_name        AS skill_b,
    s1.skill_category    AS category_a,
    COUNT(*)             AS co_occurrences,
    ROUND(COUNT(*) * 100.0 / (
        SELECT COUNT(DISTINCT listing_id) FROM fact_skill_listings
    ), 2)                AS pct_of_all_jobs
FROM fact_skill_listings fsl1
JOIN fact_skill_listings fsl2
    ON  fsl1.listing_id = fsl2.listing_id
    AND fsl1.skill_id   < fsl2.skill_id
JOIN dim_skill s1 ON fsl1.skill_id = s1.skill_id
JOIN dim_skill s2 ON fsl2.skill_id = s2.skill_id
GROUP BY s1.skill_name, s2.skill_name, s1.skill_category
HAVING COUNT(*) > 5
ORDER BY co_occurrences DESC;

-- ── VIEW 5: Fresher Hotspots ──────────────────────────────────
CREATE OR REPLACE VIEW vw_fresher_hotspots AS
SELECT
    l.city,
    l.tier,
    l.region,
    r.role_category,
    COUNT(*)                           AS total_openings,
    ROUND(AVG(fjl.salary_max), 1)      AS avg_max_salary_lpa,
    ROUND(AVG(fjl.applicant_count), 0) AS avg_competition,
    DENSE_RANK() OVER (
        ORDER BY COUNT(*) DESC
    )                                  AS opportunity_rank
FROM fact_job_listings fjl
JOIN dim_role     r ON fjl.role_id     = r.role_id
JOIN dim_location l ON fjl.location_id = l.location_id
WHERE r.exp_level = 'fresher'
GROUP BY l.city, l.tier, l.region, r.role_category
HAVING COUNT(*) >= 5;

-- ── VIEW 6: Top Skills Per Role ───────────────────────────────
CREATE OR REPLACE VIEW vw_top_skills_by_role AS
WITH ranked AS (
    SELECT
        r.role_category,
        s.skill_name,
        s.skill_category,
        COUNT(DISTINCT fjl.listing_id) AS listings_requiring,
        ROUND(
            COUNT(DISTINCT fjl.listing_id) * 100.0 / NULLIF((
                SELECT COUNT(DISTINCT listing_id)
                FROM fact_job_listings fjl2
                JOIN dim_role r2 ON fjl2.role_id = r2.role_id
                WHERE r2.role_category = r.role_category
            ), 0)
        , 1) AS pct_of_role_listings,
        ROW_NUMBER() OVER (
            PARTITION BY r.role_category
            ORDER BY COUNT(DISTINCT fjl.listing_id) DESC
        ) AS skill_rank
    FROM fact_skill_listings fsl
    JOIN fact_job_listings fjl ON fsl.listing_id = fjl.listing_id
    JOIN dim_skill         s   ON fsl.skill_id   = s.skill_id
    JOIN dim_role          r   ON fjl.role_id    = r.role_id
    GROUP BY r.role_category, s.skill_name, s.skill_category
)
SELECT * FROM ranked WHERE skill_rank <= 15;