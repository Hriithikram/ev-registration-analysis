/* ═══════════════════════════════════════════════════════════════════════════
   PROJECT      : Electric Vehicle Population Analysis
   AUTHOR       : Hrithik Ram
   DATABASE     : PostgreSQL
   PURPOSE      : End-to-end data exploration, cleaning, and preparation of a
                  clean, analysis-ready Electric Vehicle (EV) population
                  dataset, followed by business-question analysis.
   SOURCE TABLE : ev_population
   OUTPUT TABLE : ev_data
═══════════════════════════════════════════════════════════════════════════ */


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 1 : INITIAL DATA INSPECTION
═══════════════════════════════════════════════════════════════════════════ */

-- 1.1 Preview a sample of the raw dataset
SELECT *
FROM ev_population;

-- 1.2 Total row count in the raw (unprocessed) dataset
SELECT COUNT(*) AS total_rows
FROM ev_population;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 2 : DATA EXPLORATION
═══════════════════════════════════════════════════════════════════════════ */

-- 2.1 Model year range covered by the dataset
SELECT
    MIN("Model Year") AS min_model_year,
    MAX("Model Year") AS max_model_year
FROM ev_population;

-- 2.2 Distinct vehicle manufacturers represented in the dataset
SELECT DISTINCT "Make" AS make
FROM ev_population
ORDER BY make;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 3 : DATA CLEANING
═══════════════════════════════════════════════════════════════════════════ */

-- 3.1 Feature selection, text formatting, and location parsing
WITH ev_cleaned_1 AS (
    SELECT
        id,
        TRIM(INITCAP("City"))                              AS city,
        TRIM("State")                                      AS state,
        "Model Year"::INT                                  AS model_year,
        TRIM(INITCAP("Make"))                               AS make,
        TRIM(INITCAP("Model"))                              AS model,
        TRIM(INITCAP("Electric Vehicle Type"))              AS ev_type,
        "Electric Range"::INT                               AS electric_range,
        TRIM(SPLIT_PART(REPLACE(REPLACE("Vehicle Location", 'POINT (', ''), ')', ''), ' ', 1))::NUMERIC AS longitude,
        TRIM(SPLIT_PART(REPLACE(REPLACE("Vehicle Location", 'POINT (', ''), ')', ''), ' ', 2))::NUMERIC AS latitude
    FROM ev_population
),

-- 3.2 Standardize EV type category labels
ev_cleaned_2 AS (
    SELECT
        id, city, state, model_year, make, model,
        CASE
            WHEN ev_type = 'Battery Electric Vehicle (Bev)'          THEN 'Battery EV'
            WHEN ev_type = 'Plug-In Hybrid Electric Vehicle (Phev)'  THEN 'Plug-In Hybrid EV'
            ELSE ev_type
        END AS ev_type,
        electric_range, longitude, latitude
    FROM ev_cleaned_1
)

-- 3.3 Persist cleaned records into a staging table
SELECT *
INTO TEMP TABLE ev_cleaned
FROM ev_cleaned_2;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 4 : DATA QUALITY CHECK
═══════════════════════════════════════════════════════════════════════════ */

-- 4.1 Identify rows with any missing (NULL) fields
SELECT *
FROM ev_cleaned
WHERE city           IS NULL
   OR state           IS NULL
   OR model_year      IS NULL
   OR make            IS NULL
   OR model           IS NULL
   OR ev_type         IS NULL
   OR electric_range  IS NULL
   OR longitude       IS NULL
   OR latitude        IS NULL;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 5 : HANDLE MISSING VALUES
   Rows missing "city" are removed; remaining numeric gaps are imputed
   in Section 6 using column averages.
═══════════════════════════════════════════════════════════════════════════ */

-- 5.1 Remove rows with unrecoverable location data
DELETE FROM ev_cleaned
WHERE city IS NULL;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 6 : FINAL DATASET CREATION
═══════════════════════════════════════════════════════════════════════════ */

-- 6.1 Impute missing numeric fields with column-level averages
WITH ev_final AS (
    SELECT
        id, city, state, model_year, make, model, ev_type,
        ROUND(COALESCE(electric_range, (SELECT AVG(electric_range) FROM ev_cleaned)))::INT AS electric_range,
        ROUND(COALESCE(longitude,      (SELECT AVG(longitude)      FROM ev_cleaned)), 5)   AS longitude,
        ROUND(COALESCE(latitude,       (SELECT AVG(latitude)       FROM ev_cleaned)), 5)   AS latitude
    FROM ev_cleaned
),

-- 6.2 Generate a clean, sequential ID for the final dataset
ev_numbered AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY id) AS id,
        city, state, model_year, make, model, ev_type, electric_range, longitude, latitude
    FROM ev_final
)

-- 6.3 Persist the final dataset into an output table
SELECT *
INTO TEMP TABLE ev_data
FROM ev_numbered;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 7 : VALIDATION
═══════════════════════════════════════════════════════════════════════════ */

-- 7.1 Preview the final dataset
SELECT *
FROM ev_data;

-- 7.2 Final row count check
SELECT COUNT(*) AS final_rows
FROM ev_data;

-- 7.3 Confirm no missing values remain in the final dataset
SELECT *
FROM ev_data
WHERE city           IS NULL
   OR state           IS NULL
   OR model_year      IS NULL
   OR make            IS NULL
   OR model           IS NULL
   OR ev_type         IS NULL
   OR electric_range  IS NULL
   OR longitude       IS NULL
   OR latitude        IS NULL;


/* ═══════════════════════════════════════════════════════════════════════════
   NOTES / DATA CLEANING DECISIONS
   1. Duplicate records were intentionally retained, as they represent
      distinct, valid vehicle registrations rather than erroneous duplicates.
   2. Rows with a missing "city" value were removed, since location data
      could not be reliably recovered or imputed for this field.
   3. Missing numeric values (electric_range, longitude, latitude) were
      imputed using their respective column averages to preserve row count
      while minimizing distortion to overall distributions.
   4. The final dataset uses ROW_NUMBER() to generate a clean, sequential
      primary key (id) suitable for downstream analysis and export.
═══════════════════════════════════════════════════════════════════════════ */


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 8 : FINAL OUTPUT
═══════════════════════════════════════════════════════════════════════════ */

SELECT *
FROM ev_data;


/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 9 : BUSINESS QUESTIONS
═══════════════════════════════════════════════════════════════════════════ */

-- ───────────────────────────────────────────────────────────────────────────
-- 9.1  Which cities have the most electric vehicle registrations?
-- ───────────────────────────────────────────────────────────────────────────
SELECT
    city,
    COUNT(*) AS total_registrations
FROM ev_data
GROUP BY city
ORDER BY total_registrations DESC
LIMIT 3;

-- ───────────────────────────────────────────────────────────────────────────
-- 9.2  Which vehicle brands are the most popular?
-- ───────────────────────────────────────────────────────────────────────────
SELECT
    make_rank,
    make,
    make_count
FROM (
    SELECT
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS make_rank,
        make,
        COUNT(*) AS make_count
    FROM ev_data
    GROUP BY make
) AS ranked_makes
ORDER BY make_rank
LIMIT 3;

-- ───────────────────────────────────────────────────────────────────────────
-- 9.3  What are the top 10 most registered EV models?
-- ───────────────────────────────────────────────────────────────────────────
SELECT
    model,
    COUNT(*) AS most_registered
FROM ev_data
GROUP BY model
ORDER BY most_registered DESC
LIMIT 10;

-- ───────────────────────────────────────────────────────────────────────────
-- 9.4  How many Battery Electric Vehicles (BEVs) and Plug-in Hybrid
--      Vehicles (PHEVs) are registered?
-- ───────────────────────────────────────────────────────────────────────────
SELECT
    ev_type,
    COUNT(*) AS category_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM ev_data), 2) AS percentage
FROM ev_data
GROUP BY ev_type
ORDER BY percentage DESC;

-- ───────────────────────────────────────────────────────────────────────────
-- 9.5  Which model years have the highest number of EV registrations?
-- ───────────────────────────────────────────────────────────────────────────
SELECT
    model_year,
    COUNT(*) AS total_registrations
FROM ev_data
GROUP BY model_year
ORDER BY total_registrations DESC
LIMIT 5;

-- ───────────────────────────────────────────────────────────────────────────
-- 9.6  Which brands offer the highest average electric driving range?
-- ───────────────────────────────────────────────────────────────────────────
SELECT
    make,
    ROUND(AVG(electric_range), 2) AS avg_electric_range
FROM ev_data
GROUP BY make
ORDER BY avg_electric_range DESC
LIMIT 3;

-- ───────────────────────────────────────────────────────────────────────────
-- 9.7  Which cities have the highest average electric vehicle range?
-- ───────────────────────────────────────────────────────────────────────────
SELECT
    city,
    avg_elec_range
FROM (
    SELECT
        city,
        ROUND(AVG(electric_range), 2) AS avg_elec_range
    FROM ev_data
    GROUP BY city
    ORDER BY avg_elec_range DESC
    LIMIT 3
) AS top_range_cities;

-- ───────────────────────────────────────────────────────────────────────────
-- 9.8  What percentage of all registered EVs belong to the top five
--      manufacturers?
-- ───────────────────────────────────────────────────────────────────────────
SELECT
    make,
    COUNT(*) AS make_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM ev_data), 2) AS percentage
FROM ev_data
GROUP BY make
ORDER BY percentage DESC
LIMIT 5;