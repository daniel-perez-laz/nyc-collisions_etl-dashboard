/*
	PROJECT: NYC Motor Vehicle Collisions Pipeline
	MODULE 01: RAW SCHEMA SETUP & DATA INGESTION
	AUTHOR: Daniel Pérez Lázaro
	PREREQUISITES: Raw NYC Collisions CSV dataset
	OBJECTIVE: Initialize the database environment, define the raw table schema, and
			   ingest the uncleaned NYC Collisions CSV dataset into staging.
*/
		  	  

-- Creates initial staging table for raw NYC collisions data
DROP TABLE IF EXISTS nyc_collisions CASCADE;

CREATE TABLE nyc_collisions (
	crash_date VARCHAR(50),
	crash_time VARCHAR(50),
	borough VARCHAR(100),
	zip_code VARCHAR(50),
	latitude VARCHAR(50),
	longitude VARCHAR(50),
	location VARCHAR(255),
	on_street_name VARCHAR(255),
	cross_street_name VARCHAR(255),
	off_street_name VARCHAR(255),
	number_of_persons_injured VARCHAR(50),
	number_of_persons_killed VARCHAR(50),
	number_of_pedestrians_injured VARCHAR(50),
	number_of_pedestrians_killed VARCHAR(50),
	number_of_cyclist_injured VARCHAR(50),
	number_of_cyclist_killed VARCHAR(50),
	number_of_motorist_injured VARCHAR(50),
	number_of_motorist_killed VARCHAR(50),
	contributing_factor_vehicle_1 VARCHAR(255),
	contributing_factor_vehicle_2 VARCHAR(255),
	contributing_factor_vehicle_3 VARCHAR(255),
	contributing_factor_vehicle_4 VARCHAR(255),
	contributing_factor_vehicle_5 VARCHAR(255),
	collision_id VARCHAR(50),
	vehicle_type_code_1 VARCHAR(255),
	vehicle_type_code_2 VARCHAR(255),
	vehicle_type_code_3 VARCHAR(255),
	vehicle_type_code_4 VARCHAR(255),
	vehicle_type_code_5 VARCHAR(255)
);

-- Bulk load raw dataset into staging table
-- Un-comment and replace '/path_to_file/' with your local directory before execution
/*
	COPY nyc_collisions
	FROM '/path_to_file/nyc_collisions_data.csv'
	WITH (FORMAT csv, HEADER true, DELIMITER ',');
*/