/*
	PROJECT: NYC Motor Vehicle Collisions Pipeline
	MODULE 02: DATA PROFILING & DIAGNOSTIC EDA
	AUTHOR: Daniel Pérez Lázaro
	PREREQUISITES: Populated 'nyc_collisions' raw staging table (Module 01)
	OBJECTIVE: Audit raw dataset anomalies, nulls, duplicates, and data types
			   prior to transformation and dimensional modeling.
*/


-- AUDIT: Verify primary key uniqueness and identify null values in collision_id
SELECT
	COUNT(collision_id) as total_records,
	COUNT(DISTINCT collision_id) as unique_ids,
	COUNT(CASE WHEN collision_id IS NULL THEN 1 END) as null_ids
FROM nyc_collisions;

-- AUDIT: Inspect date field temporal distribution and format consistency
SELECT
	crash_date,
	COUNT(*) as record_count
FROM nyc_collisions
GROUP BY crash_date
ORDER BY record_count DESC;

-- AUDIT: Assess borough categorical values and missing entries
SELECT
	borough,
	COUNT(*) as record_count
FROM nyc_collisions
GROUP BY borough;

-- AUDIT: Detect variations in street naming conventions (e.g., Broadway)
SELECT
	on_street_name,
	COUNT(*) as occurrence_count
FROM nyc_collisions
WHERE on_street_name ILIKE '%broadway%'
GROUP BY on_street_name
ORDER BY COUNT(*) DESC;

-- AUDIT: Evaluate coordinate integrity and identify zero/nulls anomalies
SELECT
	latitude,
	longitude,
	COUNT(*) as anomaly_count
FROM nyc_collisions
WHERE latitude = '0' OR longitude = '0' OR latitude IS NULL OR longitude IS NULL
GROUP BY latitude, longitude;

-- AUDIT: Profile contributing factors for non_standardized categorical inputs
SELECT
	contributing_factor_vehicle_1,
	COUNT(*) as frequency
FROM nyc_collisions
GROUP BY contributing_factor_vehicle_1
ORDER BY COUNT(*) DESC;

-- AUDIT: Check zip_code anomalies (whitspace, invalid characters)
SELECT
	COUNT(zip_code) as total_zip_codes,
	COUNT(CASE WHEN TRIM(zip_code) = '' THEN 1 END) as empty_zip_codes,
	COUNT(CASE WHEN zip_code IS NULL THEN 1 END) as null_zip_codes
FROM nyc_collisions;

-- AUDIT: Detect numeric-only values in vehicle type fields (vehicle_type_code_1)
SELECT
	vehicle_type_code_1,
	COUNT(*) as frequency
FROM nyc_collisions
WHERE vehicle_type_code_1 ~ '^[0-9]+$'
GROUP BY vehicle_type_code_1
ORDER BY frequency DESC;