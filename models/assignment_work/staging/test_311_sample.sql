 -- Quick test to verify source connection works
 SELECT
     unique_key,
     created_date,
     complaint_type,
     borough
 FROM {{ source('raw', 'sennettlee-cis9440-baruch.nyc_homework_raw_data.source_service_requests_homework') }}
 LIMIT 10