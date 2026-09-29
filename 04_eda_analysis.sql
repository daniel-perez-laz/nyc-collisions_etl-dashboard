/*
	PROJECT: NYC Motor Vehicle Collisions Pipeline
	MODULE 04: ANALYTICAL EDA & MODEL VALIDATION
	AUTHOR: Daniel Pérez Lázaro
	PREREQUISITES: Executed dimensional model script (Module 03)
	OBJECTIVE: Validate dimensional integrity, verify surrogate keys, and run business
			   analysis queries over the star schema.
*/

-- TEARDOWN (Clean existing objects)
DROP VIEW IF EXISTS vw_fact_factors CASCADE;
DROP VIEW IF EXISTS vw_fact_vehicles CASCADE;

-- AUDIT: Validate record count consistency between staging table and fact table
SELECT
	(SELECT COUNT(*) FROM nyc_collisions) as original_records,
	(SELECT COUNT(*) FROM fact_collisions) as cleaned_records,
	(SELECT COUNT(*) FROM nyc_collisions) - (SELECT COUNT(*) FROM fact_collisions) as difference;

-- AUDIT: Verify primary key uniqueness and ensure no duplicate collisions
SELECT
	COUNT(*) as total_rows,
	COUNT(DISTINCT collision_id) as unique_collisions,
	COUNT(*) - COUNT(DISTINCT collision_id) as duplicate_rows
FROM fact_collisions;

-- AUDIT: Check for orphaned records in fact_collisions pointing to missing locations
SELECT
	COUNT(*) as orphaned_location_records
FROM fact_collisions f
LEFT JOIN dim_locations d
	ON d.location_id = f.location_id
WHERE f.location_id IS NOT NULL AND d.location_id IS NULL;

-- AUDIT: Inspect top location record distribution and identify high-frequency hotspots
SELECT 
    location_id, 
    COUNT(*) AS records
FROM fact_collisions 
GROUP BY location_id 
ORDER BY records DESC 
LIMIT 10;

-- AUDIT: Ensure zero unmapped location_ids remain in fact_collisions
SELECT
	COUNT(*) as unmapped_location_records
FROM fact_collisions
WHERE location_id IS NULL;

/*
	BRIDGE VIEWS FOR UNPIVOTED RELATIONS (FACTORS & VEHICLES)
*/

CREATE OR REPLACE VIEW vw_fact_factors AS 
SELECT collision_id, location_id, collision_date, collision_time, factor_1_id as factor_id FROM fact_collisions WHERE factor_1_id IS NOT NULL
UNION ALL
SELECT collision_id, location_id, collision_date, collision_time, factor_2_id FROM fact_collisions WHERE factor_2_id IS NOT NULL
UNION ALL
SELECT collision_id, location_id, collision_date, collision_time, factor_3_id FROM fact_collisions WHERE factor_3_id IS NOT NULL
UNION ALL
SELECT collision_id, location_id, collision_date, collision_time, factor_4_id FROM fact_collisions WHERE factor_4_id IS NOT NULL
UNION ALL
SELECT collision_id, location_id, collision_date, collision_time, factor_5_id FROM fact_collisions WHERE factor_5_id IS NOT NULL;

CREATE OR REPLACE VIEW vw_fact_vehicles AS
SELECT collision_id, location_id, collision_date, collision_time, vehicle_1_id as vehicle_id FROM fact_collisions WHERE vehicle_1_id IS NOT NULL
UNION ALL
SELECT collision_id, location_id, collision_date, collision_time, vehicle_2_id FROM fact_collisions WHERE vehicle_2_id IS NOT NULL
UNION ALL
SELECT collision_id, location_id, collision_date, collision_time, vehicle_3_id FROM fact_collisions WHERE vehicle_3_id IS NOT NULL
UNION ALL
SELECT collision_id, location_id, collision_date, collision_time, vehicle_4_id FROM fact_collisions WHERE vehicle_4_id IS NOT NULL
UNION ALL
SELECT collision_id, location_id, collision_date, collision_time, vehicle_5_id FROM fact_collisions WHERE vehicle_5_id IS NOT NULL;

-- EDA: Identify top 10 contributing factors in collisions
SELECT
	df.factor_category as factor,
	COUNT(*) as total_records
FROM vw_fact_factors vf
JOIN dim_factors df ON vf.factor_id = df.factor_id
WHERE df.factor_category NOT IN ('UNSPECIFIED', 'NOT SPECIFIED')
GROUP BY df.factor_category
ORDER BY total_records DESC
LIMIT 10;

-- EDA: Identify top 20 collision blackspots (high-risks intersections)
SELECT
	dl.main_street,
	dl.cross_street,
	COUNT(*) as total_records,
	SUM(fc.persons_injured) as total_injured,
	SUM(fc.persons_killed) as total_killed
FROM fact_collisions fc
INNER JOIN dim_locations dl
	ON dl.location_id = fc.location_id
WHERE dl.main_street != 'NOT SPECIFIED' AND dl.cross_street != 'NOT SPECIFIED'
GROUP BY dl.main_street, dl.cross_street
ORDER BY total_records DESC
LIMIT 20;

-- EDA: Identify top 10 vehicle types involved in collisions
SELECT
	dv.vehicle_category,
	COUNT(*) as total_records
FROM dim_vehicles dv
INNER JOIN vw_fact_vehicles vfv
	ON vfv.vehicle_id = dv.vehicle_id
WHERE vehicle_category != 'NOT SPECIFIED'
GROUP BY dv.vehicle_category
ORDER BY total_records DESC
LIMIT 10;

-- EDA: Identify top 10 contributing factors in late-night collisions (2 AM - 4 AM)
SELECT
	df.factor_category,
	COUNT(*) as total_records
FROM vw_fact_factors vff
INNER JOIN dim_factors df
	ON df.factor_id = vff.factor_id
WHERE df.factor_category != 'NOT SPECIFIED' AND EXTRACT(HOUR from vff.collision_time) BETWEEN 2 AND 4
GROUP BY df.factor_category
ORDER BY total_records DESC
LIMIT 10;

-- EDA: Identify top 3 contributing factors in the highest_risk borough
WITH top_injury_borough AS (
	SELECT
		dl.borough
	FROM fact_collisions fc
	INNER JOIN dim_locations dl
		ON dl.location_id = fc.location_id
	WHERE dl.borough != 'NOT SPECIFIED'
	GROUP BY borough
	ORDER BY SUM(fc.persons_injured) DESC
	LIMIT 1
)
SELECT
	dl.borough,
	df.factor_category,
	COUNT(*) as total_records
FROM vw_fact_factors vff
INNER JOIN dim_factors df
	ON df.factor_id = vff.factor_id
INNER JOIN dim_locations dl
	ON dl.location_id = vff.location_id
WHERE dl.borough = (SELECT borough FROM top_injury_borough) AND df.factor_category != 'NOT SPECIFIED'
GROUP BY dl.borough, df.factor_category
ORDER BY total_records DESC
LIMIT 3;

-- SEVERITY: Fatality rate per 1000 collisions by borough
SELECT
	dl.borough,
	ROUND((SUM(fc.persons_killed * 1000.0) / COUNT(fc.collision_id)),2) as fatality_rate_per_1k
FROM fact_collisions fc
JOIN dim_locations dl ON dl.location_id = fc.location_id
WHERE fc.persons_killed IS NOT NULL AND dl.borough != 'NOT SPECIFIED'
GROUP BY dl.borough
ORDER BY fatality_rate_per_1k DESC;

-- SEVERITY: Percentage of late-night collisions (2 AM - 4 AM) involving alcohol
WITH late_night_collisions AS (
	SELECT
		COUNT(*) as total_late_night
	FROM fact_collisions
	WHERE EXTRACT(HOUR from collision_time) BETWEEN 2 AND 4
),
late_night_alcohol AS (
	SELECT
		COUNT(DISTINCT vff.collision_id) as total_alcohol
	FROM vw_fact_factors vff
	INNER JOIN dim_factors df
		ON vff.factor_id = df.factor_id
	WHERE EXTRACT(HOUR from vff.collision_time) BETWEEN 2 AND 4
		AND df.factor_category = 'ALCOHOL INVOLVEMENT'
)
SELECT
	lnc.total_late_night,
	lna.total_alcohol,
	ROUND(lna.total_alcohol::numeric / NULLIF(lnc.total_late_night, 0) * 100, 2) as alcohol_percentage
FROM late_night_collisions lnc, late_night_alcohol lna;

-- SEVERITY: Injury ratio by vehicle category
SELECT
	dv.vehicle_category,
	COUNT(vfv.vehicle_id) as total_vehicles_involved,
	SUM(fc.persons_injured) as total_injuries,
	ROUND(SUM(fc.persons_injured)::numeric / NULLIF(COUNT(vfv.vehicle_id), 0), 2) as injury_ratio
FROM vw_fact_vehicles vfv
INNER JOIN fact_collisions fc
	ON fc.collision_id = vfv.collision_id
INNER JOIN dim_vehicles dv
	ON dv.vehicle_id = vfv.vehicle_id
WHERE dv.vehicle_category NOT IN ('UNSPECIFIED', 'NOT SPECIFIED')
GROUP BY vehicle_category
ORDER BY injury_ratio DESC
LIMIT 5;

-- SEVERITY: Percentage of pedestrian injuries relative to total injuries
SELECT
	SUM(persons_injured) as total_injuries,
	SUM(pedestrians_injured) as total_pedestrians_injured,
	ROUND((SUM(pedestrians_injured)::numeric / NULLIF(SUM(persons_injured), 0) * 100.0), 2) as pedestrians_percentage
FROM fact_collisions;

-- SEVERITY: Percentage of late-night collisions (2 AM - 4 AM) resulting in at least one fatality
SELECT
	COUNT(*) as total_occurrences,
	COUNT(CASE WHEN persons_killed >= 1 THEN 1 END) as total_fatalities,
	ROUND((COUNT(CASE WHEN persons_killed >= 1 THEN 1 END)::numeric / NULLIF(COUNT(*), 0) * 100.0), 2) as percentage
FROM fact_collisions
WHERE EXTRACT(HOUR FROM collision_time) BETWEEN 2 AND 4;

-- SEVERITY: Cyclist fatality rate among total affected cyclists
SELECT
	SUM(cyclists_killed + cyclists_injured) as cyclists_affected,
	SUM(cyclists_killed) as total_cyclists_killed,
	ROUND((SUM(cyclists_killed)::numeric / NULLIF(SUM(cyclists_injured + cyclists_killed), 0) * 100.0), 2) as kill_percentage
FROM fact_collisions;

-- SEVERITY: Proportion of collisions with multiple injuries (2 or more injured)
SELECT
	COUNT(*) as total_collisions,
	COUNT(CASE WHEN persons_injured >= 2 THEN 1 END) as multiple_injury_collisions,
	ROUND(COUNT(CASE WHEN persons_injured >= 2 THEN 1 END)::numeric / NULLIF(COUNT(*), 0) * 100.0, 2) as multiple_injury_percentage
FROM fact_collisions;