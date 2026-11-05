-- Clean and standardize DOB NOW job application filings
-- Grain: one row per job filing number

WITH source AS (
    SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
),

cleaned AS (
    SELECT
        * EXCEPT (
            job_filing_number, filing_status, current_status_date,
            house_no, bin, bbl, nta, commmunity_board, postcode,
            initial_cost, borough, apt_condo_no_s, owner_s_business_name,
            applicant_professional_title, proposed_no_of_stories,
            existing_stories, total_construction_floor_area, job_type
        ),

        -- Identifiers
        CAST(job_filing_number AS STRING) AS job_filing_number,
        CAST(bin AS STRING) AS building_identification_number,
        CAST(bbl AS STRING) AS borough_block_lot,

        -- Job details
        UPPER(TRIM(job_type)) AS job_type,
        UPPER(TRIM(filing_status)) AS filing_status,
        current_status_date AS status_date,

        -- Cost: strip "$" and commas
        SAFE_CAST(REGEXP_REPLACE(initial_cost, r'[$,]', '') AS NUMERIC) AS initial_cost_usd,
        SAFE_CAST(total_construction_floor_area AS FLOAT64) AS total_floor_area_sqft,
        SAFE_CAST(existing_stories AS INT64) AS existing_stories,
        SAFE_CAST(proposed_no_of_stories AS INT64) AS proposed_stories,

        -- Renamed to clearer names (fixes the "commmunity" typo too)
        house_no AS house_number,
        apt_condo_no_s AS apartment_condo_numbers,
        nta AS neighborhood_tabulation_area,
        commmunity_board AS community_board,
        owner_s_business_name AS owner_business_name,
        applicant_professional_title AS applicant_title,

        -- Borough
        CASE
            WHEN UPPER(TRIM(borough)) IN ('MANHATTAN', 'NEW YORK COUNTY') THEN 'Manhattan'
            WHEN UPPER(TRIM(borough)) IN ('BRONX', 'THE BRONX') THEN 'Bronx'
            WHEN UPPER(TRIM(borough)) IN ('BROOKLYN', 'KINGS COUNTY') THEN 'Brooklyn'
            WHEN UPPER(TRIM(borough)) IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY') THEN 'Queens'
            WHEN UPPER(TRIM(borough)) IN ('STATEN ISLAND', 'RICHMOND COUNTY') THEN 'Staten Island'
            ELSE 'UNKNOWN'
        END AS borough,

        -- Zip code (property zip is `postcode`)
        CASE
            WHEN UPPER(TRIM(postcode)) IN ('', 'N/A', 'NA', 'NONE', 'ANONYMOUS') THEN NULL
            WHEN TRIM(postcode) = '00000' THEN NULL
            WHEN REGEXP_CONTAINS(TRIM(postcode), r'^\d{5}$') THEN TRIM(postcode)
            WHEN REGEXP_CONTAINS(TRIM(postcode), r'^\d{5}-?\d{4}$') THEN SUBSTR(TRIM(postcode), 1, 5)
            ELSE NULL
        END AS zip_code,

        CURRENT_TIMESTAMP() AS _stg_loaded_at

    FROM source

    -- Only drop rows missing the essentials
    WHERE job_filing_number IS NOT NULL
      AND filing_date IS NOT NULL

    -- Deduplicate: keep the most recently updated row per job filing
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY job_filing_number
        ORDER BY current_status_date DESC NULLS LAST, filing_date DESC
    ) = 1
)

SELECT * FROM cleaned