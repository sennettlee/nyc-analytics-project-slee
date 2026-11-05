-- Clean and standardize DOB job application filings
-- Grain: one row per job number + document number

WITH source AS (
    SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
),

cleaned AS (
    SELECT
        * EXCEPT (
            job__, doc__, bin__, house__, pre__filing_date, latest_action_date,
            job_status, job_status_descrp, job_type, building_type, job_description,
            initial_cost, borough, street_name, block, lot, zip,
            gis_latitude, gis_longitude
        ),

        -- Renamed identifiers
        CAST(job__ AS STRING) AS job_number,
        CAST(doc__ AS STRING) AS document_number,
        CAST(bin__ AS STRING) AS building_identification_number,

        -- Renamed job details
        UPPER(TRIM(CAST(job_type AS STRING))) AS job_type,
        UPPER(TRIM(CAST(job_status AS STRING))) AS job_status_code,
        CAST(job_status_descrp AS STRING) AS job_status_description,
        CAST(building_type AS STRING) AS building_type,
        CAST(job_description AS STRING) AS job_description,

        -- Renamed dates (stored as MM/DD/YYYY strings in the legacy dataset)
        SAFE.PARSE_DATE('%m/%d/%Y', CAST(pre__filing_date AS STRING)) AS filing_date,
        SAFE.PARSE_DATE('%m/%d/%Y', CAST(latest_action_date AS STRING)) AS latest_action_date,

        SAFE_CAST(REGEXP_REPLACE(CAST(initial_cost AS STRING), r'[$,]', '') AS NUMERIC) AS initial_cost,

        -- Location
        CASE
            WHEN UPPER(TRIM(borough)) IN ('MANHATTAN', 'NEW YORK COUNTY') THEN 'Manhattan'
            WHEN UPPER(TRIM(borough)) IN ('BRONX', 'THE BRONX') THEN 'Bronx'
            WHEN UPPER(TRIM(borough)) IN ('BROOKLYN', 'KINGS COUNTY') THEN 'Brooklyn'
            WHEN UPPER(TRIM(borough)) IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY') THEN 'Queens'
            WHEN UPPER(TRIM(borough)) IN ('STATEN ISLAND', 'RICHMOND COUNTY') THEN 'Staten Island'
            ELSE 'UNKNOWN'
        END AS borough,
        CAST(house__ AS STRING) AS house_number,
        CAST(street_name AS STRING) AS street_name,
        CAST(block AS STRING) AS tax_block,
        CAST(lot AS STRING) AS tax_lot,
        SAFE_CAST(gis_latitude AS FLOAT64) AS latitude,
        SAFE_CAST(gis_longitude AS FLOAT64) AS longitude,

        -- Zip code cleaning: keep only a valid 5-digit zip, otherwise NULL
        CASE
            WHEN UPPER(TRIM(CAST(zip AS STRING))) IN ('', 'N/A', 'NA', 'NONE', 'ANONYMOUS') THEN NULL
            WHEN REGEXP_CONTAINS(TRIM(CAST(zip AS STRING)), r'^\d{5}$')
                THEN TRIM(CAST(zip AS STRING))
            -- ZIP+4 with or without hyphen (12345-6789 or 123456789): keep first 5
            WHEN REGEXP_CONTAINS(TRIM(CAST(zip AS STRING)), r'^\d{5}-?\d{4}$')
                THEN SUBSTR(TRIM(CAST(zip AS STRING)), 1, 5)
            ELSE NULL  -- wrong length, letters, or junk like 00000 (filtered below)
        END AS zip_code_raw,

        CURRENT_TIMESTAMP() AS _stg_loaded_at

    FROM source

    -- Only drop rows missing the essentials (keeps most of the data)
    WHERE job__ IS NOT NULL
      AND doc__ IS NOT NULL
      AND SAFE.PARSE_DATE('%m/%d/%Y', CAST(pre__filing_date AS STRING)) IS NOT NULL

    -- Deduplicate: keep the most recently updated row per job + document
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY job__, doc__
        ORDER BY SAFE.PARSE_DATE('%m/%d/%Y', CAST(latest_action_date AS STRING)) DESC NULLS LAST
    ) = 1
),

final AS (
    SELECT
        * EXCEPT (zip_code_raw),
        -- Placeholder zeros are not real zip codes
        IF(zip_code_raw = '00000', NULL, zip_code_raw) AS zip_code
    FROM cleaned
)

SELECT * FROM final
-- All should be part of this table after running: stg_nyc_dob_job_filings
