-- Location dimension shared by both data sources
-- Grain: one row per distinct combination of borough / council_district / zip.

WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_nyc_311_dot') }}
),

stg_dob AS (
    SELECT * FROM {{ ref('stg_nyc_dob_job_filings') }}
),

all_locations AS (

    SELECT DISTINCT
        CAST(borough AS STRING) AS borough,
        CAST(council_district AS STRING) AS council_district,
        CAST(zip AS STRING) AS zip
    FROM stg_311
    WHERE borough IS NOT NULL
       OR council_district IS NOT NULL
       OR zip IS NOT NULL

    UNION DISTINCT

    SELECT DISTINCT
        CAST(borough AS STRING) AS borough,
        CAST(council_district AS STRING) AS council_district,
        CAST(zip_code AS STRING) AS zip
    FROM stg_dob
    WHERE borough IS NOT NULL
       OR council_district IS NOT NULL
       OR zip_code IS NOT NULL

),

location_dimension AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'borough', 'council_district', 'zip'
        ]) }} AS location_key,

        borough,