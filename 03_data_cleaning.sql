/*
	PROJECT: NYC Motor Vehicle Collisions Pipeline
	MODULE 03: DATA TRANSFORMATION & DIMENSIONAL MODELING
	AUTHOR: Daniel Pérez Lázaro
	PREREQUISITES: Executed diagnostic profiling (Module 02) and 'nyc_collisions' staging
	OBJECTIVE: Clean raw staging data, enforce data integrity, and transform flat records into a star schema (dimension
			   tables and fact_collisions).
*/


/*
	OBJECT: VIEW: vw_nyc_collisions
	LAYER: Staging / Data Cleaning
	LOGIC: Centralize raw data cleaning, type casting, and string standardization using regex
		   operations and explicit null handling before dimensional loading.
*/

-- TEARDOWN (Clean existing objects)
DROP VIEW IF EXISTS vw_nyc_collisions CASCADE;
DROP TABLE IF EXISTS dim_factors CASCADE;
DROP TABLE IF EXISTS dim_locations CASCADE;
DROP TABLE IF EXISTS dim_vehicles CASCADE;
DROP TABLE IF EXISTS fact_collisions CASCADE;

CREATE OR REPLACE VIEW vw_nyc_collisions AS
WITH date_cte AS (
	SELECT
		*,
		crash_date::date as date_clean
	FROM nyc_collisions
),
time_cte AS (
	SELECT
		*,
		crash_time::time as time_clean
	FROM date_cte
),
borough_cte AS (
	SELECT
		*,
		CASE
			WHEN TRIM(borough) = '' OR borough IS NULL THEN 'NOT SPECIFIED'
			ELSE UPPER(TRIM(borough))
		END AS borough_clean
	FROM time_cte
),
zip_cte AS (
	SELECT
		*,
		-- Explicitly cast zip_code to TEXT preventing leading zero truncation and join mismatch
		NULLIF(TRIM(zip_code), '')::text as zip_code_clean
	FROM borough_cte
),
latitude_cte AS (
	SELECT
		*,
		CASE
			WHEN TRIM(latitude) LIKE '0%' THEN NULL
			ELSE latitude::numeric(9,6)
		END as latitude_clean	
	FROM zip_cte
),
longitude_cte AS (
	SELECT
		*,
		CASE
			WHEN TRIM(longitude) LIKE '0%' THEN NULL
			ELSE longitude::numeric(9,6)
		END as longitude_clean
	FROM latitude_cte
),
location_cte AS (
	SELECT
		*,
		CASE
			WHEN latitude_clean IS NULL OR longitude_clean IS NULL THEN NULL
			ELSE CONCAT_WS(', ',latitude_clean, longitude_clean)
		END as location_clean
	FROM longitude_cte
),
main_street_cte AS (
	SELECT
		*,
		CASE
			WHEN TRIM(on_street_name) = '' OR on_street_name IS NULL THEN 'NOT SPECIFIED'
			ELSE
				regexp_replace(
					regexp_replace(
						regexp_replace(
							regexp_replace(
								regexp_replace(
									regexp_replace(
										regexp_replace(
											UPPER(TRIM(on_street_name)), '\s+(EX|EXPY|EXY|EXPWY|EXWAY|XWAY)$', ' EXPRESSWAY'
										), '\s+(BLV|BLVD)$', ' BOULEVARD' 
									), '\s+PKWY$', ' PARKWAY'
								), '\s+AVE$', ' AVENUE'				
							), '\s+PL$', ' PLACE'
						), '\ySR\y', ' SERVICE ROAD', 'g'
					), '\yRD\y', 'ROAD', 'g'
				)
		END as street_clean
	FROM location_cte
),
cross_street_cte AS (
	SELECT
		*,
		CASE
			WHEN TRIM(cross_street_name) = '' OR cross_street_name IS NULL THEN 'NOT SPECIFIED'
			ELSE
				regexp_replace(
					regexp_replace(
						regexp_replace(
							regexp_replace(
								regexp_replace(
									regexp_replace(
										regexp_replace(
											UPPER(TRIM(cross_street_name)), '\s+(EX|EXPY|EXY|EXPWY|EXWAY|XWAY)$', ' EXPRESSWAY'
										), '\s+(BLV|BLVD)$', ' BOULEVARD'
									), '\s+PKWY$', ' PARKWAY'
								), '\s+AVE$', ' AVENUE'
							), '\s+PL$', ' PLACE'
						), '\ySR\y', ' SERVICE ROAD', 'g'
					), '\yRD\y', 'ROAD', 'g'
				)
		END as cross_street_clean
	FROM main_street_cte
),
off_street_cte AS (
	SELECT
		*,
		CASE
			WHEN TRIM(off_street_name) = '' OR off_street_name IS NULL THEN 'NOT SPECIFIED'
			ELSE
				regexp_replace(
					regexp_replace(
						regexp_replace(
							regexp_replace(
								regexp_replace(
									regexp_replace(
										regexp_replace(
											regexp_replace(UPPER(TRIM(off_street_name)), '\s+', ' ', 'g'), '\s+(EX|EXPY|EXY|EXPWY|EXWAY|XWAY)$', ' EXPRESSWAY'
										), '\s+(BLV|BLVD)$', ' BOULEVARD'
									), '\s+PKWY$', ' PARKWAY'
								), '\s+AVE$', ' AVENUE'
							), '\s+PL$', ' PLACE'
						), '\ySR\y', ' SERVICE ROAD', 'g'
					), '\yRD\y', 'ROAD', 'g'
				)
		END as off_street_clean
	FROM cross_street_cte
),
injured_count_cte AS (
	SELECT
		*,
		number_of_persons_injured::int as injured_count
	FROM off_street_cte
),
kill_count_cte AS (
	SELECT
		*,
		number_of_persons_killed::int as kill_count
	FROM injured_count_cte
),
pedestrians_injured_cte AS (
	SELECT
		*,
		number_of_pedestrians_injured::int as pedestrians_injured
	FROM kill_count_cte
),
pedestrians_killed_cte AS (
	SELECT
		*,
		number_of_pedestrians_killed::int as pedestrians_killed
	FROM pedestrians_injured_cte
),
cyclist_injured_cte AS (
	SELECT
		*,
		number_of_cyclist_injured::int as cyclist_injured
	FROM pedestrians_killed_cte
),
cyclist_killed_cte AS (
	SELECT
		*,
		number_of_cyclist_killed::int as cyclist_killed
	FROM cyclist_injured_cte
),
motorist_injured_cte AS (
	SELECT
		*,
		number_of_motorist_injured::int as motorist_injured
	FROM cyclist_killed_cte
),
motorist_killed_cte AS (
	SELECT
		*,
		number_of_motorist_killed::int as motorist_killed
	FROM motorist_injured_cte
),
factor_1_cte AS (
	SELECT
		*,
		CASE
			WHEN contributing_factor_vehicle_1 IS NULL
				OR TRIM(contributing_factor_vehicle_1) = ''
				OR UPPER(TRIM(contributing_factor_vehicle_1)) = 'UNSPECIFIED'
				OR contributing_factor_vehicle_1 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE UPPER(TRIM(contributing_factor_vehicle_1))
		END as factor_1_clean
	FROM motorist_killed_cte
),
factor_2_cte AS (
	SELECT
		*,
		CASE
			WHEN contributing_factor_vehicle_2 IS NULL
				OR TRIM(contributing_factor_vehicle_2) = ''
				OR UPPER(TRIM(contributing_factor_vehicle_2)) = 'UNSPECIFIED'
				OR contributing_factor_vehicle_2 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE UPPER(TRIM(contributing_factor_vehicle_2))
		END as factor_2_clean
	FROM factor_1_cte
),
factor_3_cte AS (
	SELECT
		*,
		CASE
			WHEN contributing_factor_vehicle_3 IS NULL
				OR TRIM(contributing_factor_vehicle_3) = ''
				OR UPPER(TRIM(contributing_factor_vehicle_3)) = 'UNSPECIFIED'
				OR contributing_factor_vehicle_3 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE UPPER(TRIM(contributing_factor_vehicle_3))
		END as factor_3_clean
	FROM factor_2_cte
),
factor_4_cte AS (
	SELECT
		*,
		CASE
			WHEN contributing_factor_vehicle_4 IS NULL
				OR TRIM(contributing_factor_vehicle_4) = ''
				OR UPPER(TRIM(contributing_factor_vehicle_4)) = 'UNSPECIFIED'
				OR contributing_factor_vehicle_4 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE UPPER(TRIM(contributing_factor_vehicle_4))
		END as factor_4_clean
	FROM factor_3_cte
),
factor_5_cte AS (
	SELECT
		*,
		CASE
			WHEN contributing_factor_vehicle_5 IS NULL
				OR TRIM(contributing_factor_vehicle_5) = ''
				OR UPPER(TRIM(contributing_factor_vehicle_5)) = 'UNSPECIFIED'
				OR contributing_factor_vehicle_5 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE UPPER(TRIM(contributing_factor_vehicle_5))
		END as factor_5_clean
	FROM factor_4_cte
),
id_cte AS (
	SELECT
		*,
		collision_id::integer as collision_id_new
	FROM factor_5_cte
),
vehicle_type_1_cte AS (
	SELECT
		*,
		CASE
			WHEN vehicle_type_code_1 IS NULL
				OR TRIM(vehicle_type_code_1) = ''
				OR UPPER(TRIM(vehicle_type_code_1)) IN ('UNSPECIFIED', 'UNKNOWN')
				OR vehicle_type_code_1 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE regexp_replace(UPPER(TRIM(vehicle_type_code_1)), '\s+', ' ', 'g')
		END as vehicle_type_1_clean
	FROM id_cte
),
vehicle_type_2_cte AS (
	SELECT
		*,
		CASE
			WHEN vehicle_type_code_2 IS NULL
				OR TRIM(vehicle_type_code_2) = ''
				OR UPPER(TRIM(vehicle_type_code_2)) IN ('UNSPECIFIED', 'UNKNOWN')
				OR vehicle_type_code_2 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE regexp_replace(UPPER(TRIM(vehicle_type_code_2)), '\s+', ' ', 'g')
		END as vehicle_type_2_clean
	FROM vehicle_type_1_cte
),
vehicle_type_3_cte AS (
	SELECT
		*,
		CASE
			WHEN vehicle_type_code_3 IS NULL
				OR TRIM(vehicle_type_code_3) = ''
				OR UPPER(TRIM(vehicle_type_code_3)) IN ('UNSPECIFIED', 'UNKNOWN')
				OR vehicle_type_code_3 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE regexp_replace(UPPER(TRIM(vehicle_type_code_3)), '\s+', ' ', 'g')
		END as vehicle_type_3_clean
	FROM vehicle_type_2_cte
),
vehicle_type_4_cte AS (
	SELECT
		*,
		CASE
			WHEN vehicle_type_code_4 IS NULL
				OR TRIM(vehicle_type_code_4) = ''
				OR UPPER(TRIM(vehicle_type_code_4)) IN ('UNSPECIFIED', 'UNKNOWN')
				OR vehicle_type_code_4 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE regexp_replace(UPPER(TRIM(vehicle_type_code_4)), '\s+', ' ', 'g')
		END as vehicle_type_4_clean
	FROM vehicle_type_3_cte
),
vehicle_type_5_cte AS (
	SELECT
		*,
		CASE
			WHEN vehicle_type_code_5 IS NULL
				OR TRIM(vehicle_type_code_5) = ''
				OR UPPER(TRIM(vehicle_type_code_5)) IN ('UNSPECIFIED', 'UNKNOWN')
				OR vehicle_type_code_5 ~ '^[0-9]+$' THEN 'NOT SPECIFIED'
			ELSE regexp_replace(UPPER(TRIM(vehicle_type_code_5)), '\s+', ' ', 'g')
		END as vehicle_type_5_clean
	FROM vehicle_type_4_cte
)
SELECT
	collision_id_new,
	date_clean,
	time_clean,
	borough_clean,
	street_clean,
	cross_street_clean,
	off_street_clean,	
	zip_code_clean,
	latitude_clean,
	longitude_clean,
	location_clean,
	injured_count,
	kill_count,
	pedestrians_injured,
	pedestrians_killed,
	cyclist_injured,
	cyclist_killed,
	motorist_injured,
	motorist_killed,
	vehicle_type_1_clean,
	vehicle_type_2_clean,
	vehicle_type_3_clean,
	vehicle_type_4_clean,
	vehicle_type_5_clean,
	factor_1_clean,
	factor_2_clean,
	factor_3_clean,
	factor_4_clean,
	factor_5_clean	
FROM vehicle_type_5_cte;

/*
	OBJECT: DIMENSION: dim_locations
	LAYER: Dimensional Model (Star Schema)
	LOGIC: Deduplicate geographic entities by grouping standardized address attributes.
		   Enforce street order symmetry using LEAST/GREATEST functions, aggregate GPS coordinates
		   with MAX() to resolve sensor micro-variations, and apply COALESCE() to manage unknown locations
		   strings without altering numerical aggregation.
*/

CREATE TABLE IF NOT EXISTS dim_locations (
	location_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	borough VARCHAR(100),
	main_street VARCHAR(255),
	cross_street VARCHAR(255),
	off_street VARCHAR(255),
	zip_code VARCHAR(255),
	latitude NUMERIC(9,6),
	longitude NUMERIC(9,6),
	location VARCHAR(100)
);

INSERT INTO dim_locations (borough, main_street, cross_street, off_street, zip_code, latitude, longitude, location)
SELECT
	borough_clean as borough,
	LEAST(street_clean, cross_street_clean) as street_a,
	GREATEST(street_clean, cross_street_clean) as street_b,
	off_street_clean as off_street,
	zip_code_clean as zip_code,
	MAX(latitude_clean) as latitude,
	MAX(longitude_clean) as longitude,
	COALESCE(MAX(location_clean), 'UNKNOWN') as location
FROM vw_nyc_collisions
GROUP BY borough_clean, LEAST(street_clean, cross_street_clean), GREATEST(street_clean, cross_street_clean), off_street_clean, zip_code_clean;

/*
	OBJECT: DIMENSION: dim_vehicles
	LAYER: Dimensional Model (Star Schema)
	LOGIC: Consolidate distinct vehicle types across five raw attributes using UNION,
		   then map heterogeneous string descriptions into standardized macro-categories
		   using CASE conditional logic and pattern matching (ILIKE/IN).
*/

CREATE TABLE IF NOT EXISTS dim_vehicles (
	vehicle_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	vehicle_og VARCHAR(100),
	vehicle_category VARCHAR(100)
);

INSERT INTO dim_vehicles (vehicle_og, vehicle_category)
WITH vehicles_universe AS (
	SELECT vehicle_type_1_clean as vehicle FROM vw_nyc_collisions
	UNION
	SELECT vehicle_type_2_clean FROM vw_nyc_collisions
	UNION
	SELECT vehicle_type_3_clean FROM vw_nyc_collisions
	UNION
	SELECT vehicle_type_4_clean FROM vw_nyc_collisions
	UNION
	SELECT vehicle_type_5_clean FROM vw_nyc_collisions
)
SELECT
	vehicle as vehicle_og,
	CASE
		WHEN vehicle ILIKE ANY(ARRAY['%SEDAN%']) THEN 'SEDAN'
		WHEN vehicle IN ('STATION WAGON/SPORT UTILITY VEHICLE', 'SPORT UTILITY / STATION WAGON') THEN 'SUV/STATION WAGON'
		WHEN vehicle = 'TAXI' THEN 'TAXI'
		WHEN vehicle ILIKE '%PICK-UP%' THEN 'PICK-UP'
		WHEN vehicle IN ('BUS', 'LIVERY VEHICLE') THEN 'TRANSPORTATION VEHICLE'
		WHEN vehicle IN ('VAN', 'BOX TRUCK', 'CARRY ALL') THEN 'CARGO TRUCK'
		WHEN vehicle IN ('LARGE COM VEH(6 OR MORE TIRES)', 'TRACTOR TRUCK DIESEL', 'FLAT BED', 'DUMP', 'GARBAGE OR REFUSE', 'TRACTOR TRUCK GASOLINE') THEN 'HEAVY DUTY'
		WHEN vehicle IN ('SMALL COM VEH(4 TIRES)', 'PK') THEN 'LIGHT DUTY'
		WHEN vehicle IN ('MOTORCYCLE', 'E-SCOOTER', 'MOPED') THEN 'MOTORCYCLE'
		WHEN vehicle IN ('E-BIKE', 'BIKE', 'BICYCLE') THEN 'BICYCLE'
		WHEN vehicle = 'CONVERTIBLE' THEN 'CONVERTIBLE'
		WHEN vehicle = 'AMBULANCE' THEN 'AMBULANCE'
		WHEN vehicle IN ('NOT SPECIFIED', 'UNKNOWN') THEN 'NOT SPECIFIED'
		WHEN vehicle = 'OTHER' THEN 'OTHER'
		ELSE 'OTHER'
	END AS vehicle_category
FROM vehicles_universe
WHERE vehicle IS NOT NULL;

/*
	OBJECT: DIMENSION: dim_factors
	LAYER: Dimensional Model (Star Schema)
	LOGIC: Consolidate distinct factor types across five raw attributes using UNION,
		   then map heterogeneous string descriptions into standardized macro-categories
		   using CASE conditional logic and explicit set membership (IN).	
*/

CREATE TABLE IF NOT EXISTS dim_factors (
	factor_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	factor_og VARCHAR(100),
	factor_category VARCHAR(100)
);

INSERT INTO dim_factors (factor_og, factor_category)
WITH factors_universe AS (
	SELECT factor_1_clean as factor FROM vw_nyc_collisions
	UNION
	SELECT factor_2_clean FROM vw_nyc_collisions
	UNION
	SELECT factor_3_clean FROM vw_nyc_collisions
	UNION
	SELECT factor_4_clean FROM vw_nyc_collisions
	UNION
	SELECT factor_5_clean FROM vw_nyc_collisions
)
SELECT
	factor as factor_og,
	CASE
		WHEN factor IN ('CELL PHONE (HANDS-FREE)', 'CELL PHONE (HAND-HELD)', 'TEXTING',  'DRIVER INATTENTION/DISTRACTION', 'OUTSIDE CAR DISTRACTION', 'PASSENGER DISTRACTION', 'PEDESTRIAN/BICYCLIST/OTHER PEDESTRIAN ERROR/CONFUSION') THEN 'DISTRACTION'
		WHEN factor IN ('FAILURE TO YIELD RIGHT-OF-WAY', 'FOLLOWING TOO CLOSELY', 'BACKING UNSAFELY', 'PASSING OR LANE USAGE IMPROPER', 'PASSING TOO CLOSELY', 'TURNING IMPROPERLY', 'UNSAFE LANE CHANGING', 'UNSAFE SPEED', 'TRAFFIC CONTROL DISREGARDED') THEN 'NEGLIGENCE'
		WHEN factor IN ('DRIVER INEXPERIENCE', 'OVERSIZED VEHICLE', 'REACTION TO UNINVOLVED VEHICLE', 'REACTION TO OTHER UNINVOLVED VEHICLE') THEN 'INEXPERIENCE'
		WHEN factor IN ('ALCOHOL INVOLVEMENT') THEN 'ALCOHOL INVOLVEMENT'
		WHEN factor IN ('FATIGUED/DROWSY', 'LOST CONSCIOUSNESS', 'PRESCRIPTION MEDICATION', 'FELL ASLEEP') THEN 'FATIGUE/LOST CONSCIOUSNESS'
		WHEN factor IN ('PHYSICAL DISABILITY', 'ILLNES') THEN 'INAPPROPRIATE PHYSICAL STATE'
		WHEN factor IN ('AGGRESSIVE DRIVING/ROAD RAGE') THEN 'INAPPROPRIATE MENTAL STATE'
		WHEN factor = 'DRUGS (ILLEGAL)' THEN 'DRUGS'
		WHEN factor IN ('OBSTRUCTION/DEBRIS', 'GLARE', 'PAVEMENT SLIPPERY', 'VIEW OBSTRUCTED/LIMITED', 'OTHER VEHICULAR') THEN 'EXTERNAL FACTORS'
		WHEN factor IN ('TIRE FAILURE/INADEQUATE', 'BRAKES DEFECTIVE', 'STEERING FAILURE', 'HEADLIGHTS DEFECTIVE', 'WINDSHIELD INADEQUATE', 'TOW HITCH DEFECTIVE', 'TRAFFIC CONTROL DEVICE IMPROPER/NON-WORKING', 'ACCELERATOR DEFECTIVE') THEN 'TECHNICAL ISSUES'
		WHEN factor IN ('UNKNOWN', 'NOT SPECIFIED') THEN 'NOT SPECIFIED'
		WHEN factor IN ('OTHER', 'OTRO', 'OTROS') THEN 'OTHER'
		ELSE 'OTHER'
	END as factor_category
FROM factors_universe;

/*
	OBJECT: FACTS: fact_collision
	LAYER: Dimensional Model (Star Schema)
	LOGIC: Populate central fact table from cleaned staging data by resolving surrogate keys
		   via LEFT JOIN on natural business keys, preserving all collision records regardless
		   of missing dimensional references
*/

CREATE TABLE IF NOT EXISTS fact_collisions (
	collision_id INT PRIMARY KEY,
	collision_date DATE,
	collision_time TIME,
	location_id INT,
	vehicle_1_id INT,
	vehicle_2_id INT,
	vehicle_3_id INT,
	vehicle_4_id INT,
	vehicle_5_id INT,
	factor_1_id INT,
	factor_2_id INT,
	factor_3_id INT,
	factor_4_id INT,
	factor_5_id INT,
	persons_injured INT,
	persons_killed INT,
	pedestrians_injured INT,
	pedestrians_killed INT,
	cyclists_injured INT,
	cyclists_killed INT,
	motorists_injured INT,
	motorists_killed INT
);
INSERT INTO fact_collisions (collision_id, collision_date, collision_time, location_id, vehicle_1_id, vehicle_2_id, vehicle_3_id, vehicle_4_id, vehicle_5_id, factor_1_id, factor_2_id, factor_3_id, factor_4_id, factor_5_id, persons_injured, persons_killed, pedestrians_injured, pedestrians_killed, cyclists_injured, cyclists_killed, motorists_injured, motorists_killed)
-- Precalculates street ordering in CTE to avoid function evaluation during the JOIN.
WITH prep_locations AS (
	SELECT
		*,
		LEAST(street_clean, cross_street_clean) as main_street_calc,
		GREATEST(street_clean, cross_street_clean) as cross_street_calc
	FROM vw_nyc_collisions
)
SELECT
	v.collision_id_new,
	v.date_clean,
	v.time_clean,
	loc.location_id,
	vh1.vehicle_id,
	vh2.vehicle_id,
	vh3.vehicle_id,
	vh4.vehicle_id,
	vh5.vehicle_id,
	f1.factor_id,
	f2.factor_id,
	f3.factor_id,
	f4.factor_id,
	f5.factor_id,
	v.injured_count,
	v.kill_count,
	v.pedestrians_injured,
	v.pedestrians_killed,
	v.cyclist_injured,
	v.cyclist_killed,
	v.motorist_injured,
	v.motorist_killed
FROM prep_locations v
LEFT JOIN dim_locations loc 
	-- Applies COALESCE with '=' to handle NULLs while forcing a fast Hash Join
	ON COALESCE(v.borough_clean, '') = COALESCE(loc.borough, '')
	AND COALESCE(v.main_street_calc, '') = COALESCE(loc.main_street, '')
	AND COALESCE(v.cross_street_calc, '') = COALESCE(loc.cross_street, '')
	AND COALESCE(v.off_street_clean, '') = COALESCE(loc.off_street, '')
	AND COALESCE(v.zip_code_clean, '') = COALESCE(loc.zip_code, '')
LEFT JOIN dim_vehicles vh1 ON v.vehicle_type_1_clean = vh1.vehicle_og
LEFT JOIN dim_vehicles vh2 ON v.vehicle_type_2_clean = vh2.vehicle_og
LEFT JOIN dim_vehicles vh3 ON v.vehicle_type_3_clean = vh3.vehicle_og
LEFT JOIN dim_vehicles vh4 ON v.vehicle_type_4_clean = vh4.vehicle_og
LEFT JOIN dim_vehicles vh5 ON v.vehicle_type_5_clean = vh5.vehicle_og
LEFT JOIN dim_factors f1 ON v.factor_1_clean = f1.factor_og
LEFT JOIN dim_factors f2 ON v.factor_2_clean = f2.factor_og
LEFT JOIN dim_factors f3 ON v.factor_3_clean = f3.factor_og
LEFT JOIN dim_factors f4 ON v.factor_4_clean = f4.factor_og
LEFT JOIN dim_factors f5 ON v.factor_5_clean = f5.factor_og;

/*
	OBJECT: CONSTRAINTS: Foreign Keys
	LAYER: Schema Integrity
	LOGIC: Enforce referential integrity between fact_collisions and dimension tables by defining
		   Foreign Key Constraints, preventing orphaned records and guaranteeing database-level consistency.
*/

ALTER TABLE fact_collisions
	ADD CONSTRAINT fk_fact_collisions_dim_locations
		FOREIGN KEY (location_id) REFERENCES dim_locations(location_id),
	ADD CONSTRAINT fk_fact_collisions_dim_factors_1
		FOREIGN KEY (factor_1_id) REFERENCES dim_factors(factor_id),
	ADD CONSTRAINT fk_fact_collisions_dim_factors_2
		FOREIGN KEY (factor_2_id) REFERENCES dim_factors(factor_id),
	ADD CONSTRAINT fk_fact_collisions_dim_factors_3
		FOREIGN KEY (factor_3_id) REFERENCES dim_factors(factor_id),
	ADD CONSTRAINT fk_fact_collisions_dim_factors_4
		FOREIGN KEY (factor_4_id) REFERENCES dim_factors(factor_id),
	ADD CONSTRAINT fk_fact_collisions_dim_factors_5
		FOREIGN KEY (factor_5_id) REFERENCES dim_factors(factor_id),	
	ADD CONSTRAINT fk_fact_collisions_dim_vehicles_1
		FOREIGN KEY (vehicle_1_id) REFERENCES dim_vehicles(vehicle_id),
	ADD CONSTRAINT fk_fact_collisions_dim_vehicles_2
		FOREIGN KEY (vehicle_2_id) REFERENCES dim_vehicles(vehicle_id),
	ADD CONSTRAINT fk_fact_collisions_dim_vehicles_3
		FOREIGN KEY (vehicle_3_id) REFERENCES dim_vehicles(vehicle_id),
	ADD CONSTRAINT fk_fact_collisions_dim_vehicles_4
		FOREIGN KEY (vehicle_4_id) REFERENCES dim_vehicles(vehicle_id),
	ADD CONSTRAINT fk_fact_collisions_dim_vehicles_5
		FOREIGN KEY (vehicle_5_id) REFERENCES dim_vehicles(vehicle_id);