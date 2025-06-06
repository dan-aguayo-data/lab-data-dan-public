show grants role GOVERNANCE_COMPANY; 

SELECT * FROM MODEL_INFO;

GRANT ALL PRIVILEGES ON SCHEMA COMPANY_GOVERNANCE.TEST TO ROLE GOVERNANCE_COMPANY; 
GRANT ALL PRIVILEGES ON VIEWS COMPANY_GOVERNANCE.TEST TO ROLE GOVERNANCE_COMPANY; 
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA COMPANY_GOVERNANCE.TEST TO ROLE GOVERNANCE_COMPANY;
GRANT ALL PRIVILEGES ON FUTURE TABLES IN SCHEMA COMPANY_GOVERNANCE.TEST TO ROLE GOVERNANCE_COMPANY;



GRANT MONITOR ON ACCOUNT UR45154  TO ROLE GOVERNANCE_COMPANY;
GRANT MONITOR ON ACCOUNT TO ROLE GOVERNANCE_COMPANY;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE GOVERNANCE_COMPANY; 

USE DATABASE COMPANY_GOVERNANCE ;

USE ROLE SF_ADMIN; 

USE ROLE SYSADMIN;

CREATE SCHEMA COMPANY_GOVERNANCE.SF_USAGE_METRICS ;

DROP VIEW SF_USAGE_METRICS.CLOUD_CREDIT_BY_WH ;

CREATE VIEW SF_USAGE_METRICS.WAREHOUSE_CLOUD_CREDITS AS

WITH date_difference AS (
    SELECT
        DATE(START_TIME) AS START_DATE,
        DATE(END_TIME) AS END_DATE,
        WAREHOUSE_ID, WAREHOUSE_NAME,
        CREDITS_USED,
        CREDITS_USED_CLOUD_SERVICES, 
        CREDITS_USED_COMPUTE,
        DATEDIFF(day, DATE(START_TIME), DATE(END_TIME)) + 1 AS DIFFERENCE
    FROM
        SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY 
    WHERE 
        YEAR(START_TIME) >= YEAR(DATEADD(year, -3, CURRENT_DATE))
),
recursive_dates AS (
    SELECT
        START_DATE,
        END_DATE,
        WAREHOUSE_ID, WAREHOUSE_NAME,
        CREDITS_USED,
        CREDITS_USED_CLOUD_SERVICES, 
        CREDITS_USED_COMPUTE,
        DIFFERENCE,
        START_DATE AS DATE,
        1 AS LEVEL
    FROM
        date_difference
    UNION ALL
    SELECT
        rd.START_DATE,
        rd.END_DATE,
        rd.WAREHOUSE_ID, rd.WAREHOUSE_NAME,
        rd.CREDITS_USED,
        rd.CREDITS_USED_CLOUD_SERVICES, 
        rd.CREDITS_USED_COMPUTE,
        rd.DIFFERENCE,
        DATEADD(day, 1, rd.DATE) AS DATE,
        rd.LEVEL + 1
    FROM
        recursive_dates rd
    WHERE
        rd.LEVEL < rd.DIFFERENCE
),
date_result AS ( SELECT
    DATE,
    WAREHOUSE_ID, WAREHOUSE_NAME,
    DIFFERENCE,
    LEVEL,
    START_DATE,
    END_DATE,
    CREDITS_USED / DIFFERENCE AS CREDITS_USED,
    CREDITS_USED_CLOUD_SERVICES / DIFFERENCE AS CREDITS_USED_CLOUD_SERVICES,
    CREDITS_USED_COMPUTE / DIFFERENCE AS CREDITS_USED_COMPUTE
FROM
    recursive_dates 
    )
    select
    DATE,
    WAREHOUSE_ID, 
    WAREHOUSE_NAME,
     SUM(CREDITS_USED)  AS CREDITS_USED,
    SUM(CREDITS_USED_CLOUD_SERVICES)  AS CREDITS_USED_CLOUD_SERVICES,
    SUM(CREDITS_USED_COMPUTE) AS CREDITS_USED_COMPUTE
FROM date_result 
GROUP BY
    DATE,
    WAREHOUSE_ID, 
    WAREHOUSE_NAME ;


DROP VIEW SF_USAGE_METRICS.WAREHOUSE_USAGE_BYTES;

CREATE VIEW SF_USAGE_METRICS.WAREHOUSE_USAGE_L7D AS

SELECT 
    warehouse_name,      
    warehouse_size,      
    -- database_name,
    ROUND(SUM(total_elapsed_time) / 1000 / 60 / 60) AS last7d_elapsed_hrs,
    ROUND(SUM(execution_time) / 1000 / 60 / 60) AS last7d_execution_hrs,
    COUNT(*) AS last7d_count_queries,
    COUNT(IFF(bytes_spilled_to_local_storage / 1024 / 1024 / 1024 > 1, 1, NULL)) AS last7d_count_spilled_queries,
    ROUND(SUM(bytes_spilled_to_local_storage) / 1024 / 1024 / 1024) AS last7d_spilled_to_local_gb,
    ROUND(SUM(bytes_spilled_to_remote_storage) / 1024 / 1024 / 1024) AS last7d_spilled_to_remote_gb,
    ROUND(SUM(queued_provisioning_time) / 1000 / 60 / 60) AS last7d_queued_provisioning_hrs,
    ROUND(SUM(queued_repair_time) / 1000 / 60 / 60) AS last7d_queued_repair_time_hrs
FROM 
    Snowflake.account_usage.query_history
WHERE 
    warehouse_size IS NOT NULL 
    AND CONVERT_TIMEZONE('UTC', 'Australia/Sydney', start_time) >= CONVERT_TIMEZONE('UTC', 'Australia/Sydney', DATEADD(day, -7, CURRENT_DATE))
GROUP BY 
    warehouse_name, 
    warehouse_size 
    -- database_name
HAVING 
    last7d_spilled_to_local_gb > 1

;
DROP VIEW COMPANY_GOVERNANCE.SF_USAGE_METRICS.DATABASE_USAGE_L6M;

CREATE or replace VIEW COMPANY_GOVERNANCE.SF_USAGE_METRICS.DATABASE_USAGE_LM AS

WITH database_usage AS (
    SELECT 
        DATABASE_NAME,
        DATABASE_ID,
        MAX(START_TIME) AS LAST_USED
    FROM 
        SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE 
        START_TIME >= DATEADD(month, -18, CURRENT_DATE)
    GROUP BY 
        DATABASE_ID,
        DATABASE_NAME
),
storage_last_month AS (
    SELECT 
        DATABASE_NAME,
        ROUND(AVG(AVERAGE_DATABASE_BYTES) / (1024 * 1024 * 1024)) AS STORAGE_GB,
        ROUND((AVG(AVERAGE_DATABASE_BYTES) / (1024 * 1024 * 1024)) / 1000) * 25 AS STORAGE_MONTHLY_COST,
        ROUND(AVG(AVERAGE_FAILSAFE_BYTES) / (1024 * 1024 * 1024)) AS STORAGE_FS_GB,
        ROUND((AVG(AVERAGE_FAILSAFE_BYTES) / (1024 * 1024 * 1024)) / 1000) * 25 AS FS_MONTHLY_COST
    FROM 
        SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
    WHERE 
        CONVERT_TIMEZONE('UTC', 'Australia/Sydney', USAGE_DATE) BETWEEN 
            DATE_TRUNC('MONTH', CONVERT_TIMEZONE('UTC', 'Australia/Sydney', DATEADD(MONTH, -1, CURRENT_DATE))) AND  
            LAST_DAY(DATE_TRUNC('MONTH', CONVERT_TIMEZONE('UTC', 'Australia/Sydney', DATEADD(MONTH, -1, CURRENT_DATE))))
    GROUP BY 
        DATABASE_NAME
),
storage_current_month AS (
    SELECT 
        DATABASE_NAME,
        ROUND(AVG(AVERAGE_DATABASE_BYTES) / (1024 * 1024 * 1024)) AS STORAGE_GB,
        ROUND((AVG(AVERAGE_DATABASE_BYTES) / (1024 * 1024 * 1024)) / 1000) * 25 AS STORAGE_MONTHLY_COST,
        ROUND(AVG(AVERAGE_FAILSAFE_BYTES) / (1024 * 1024 * 1024)) AS STORAGE_FS_GB,
        ROUND((AVG(AVERAGE_FAILSAFE_BYTES) / (1024 * 1024 * 1024)) / 1000) * 25 AS FS_MONTHLY_COST
    FROM 
        SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
    WHERE 
        CONVERT_TIMEZONE('UTC', 'Australia/Sydney', USAGE_DATE) > 
        LAST_DAY(DATE_TRUNC('MONTH', CONVERT_TIMEZONE('UTC', 'Australia/Sydney', DATEADD(MONTH, -1, CURRENT_DATE))))
    GROUP BY 
        DATABASE_NAME
)
SELECT 
    db.DATABASE_NAME,
    db.LAST_ALTERED,
    db.COMMENT,
    db.IS_TRANSIENT,
    db.DATABASE_OWNER,
    usage.DATABASE_ID,
    usage.LAST_USED AS LAST_QUERIED,
    CASE 
        WHEN DATEDIFF(day, usage.LAST_USED, CURRENT_DATE) IS NULL THEN 180
        ELSE ROUND(DATEDIFF(day, usage.LAST_USED, CURRENT_DATE))
    END AS DAYS_SINCE_LAST_QUERIED,
    slm.STORAGE_GB AS AVG_DAILY_GB_STORAGE_LM,
    scm.STORAGE_GB AS AVG_DAILY_GB_STORAGE_CM,
    slm.STORAGE_MONTHLY_COST AS MONTHLY_STORAGE_COST_LM,
    scm.STORAGE_MONTHLY_COST AS MONTHLY_STORAGE_COST_CM,
    slm.STORAGE_FS_GB AS AVG_DAILY_FS_GB_STORAGE_LM,
    scm.STORAGE_FS_GB AS AVG_DAILY_FS_GB_STORAGE_CM,
    slm.FS_MONTHLY_COST AS MONTHLY_FS_STORAGE_COST_LM,
    scm.FS_MONTHLY_COST AS MONTHLY_FS_STORAGE_COST_CM
FROM 
    SNOWFLAKE.ACCOUNT_USAGE.DATABASES db
LEFT JOIN 
    database_usage usage ON db.DATABASE_NAME = usage.DATABASE_NAME
LEFT JOIN 
    storage_last_month slm ON slm.DATABASE_NAME = db.DATABASE_NAME
LEFT JOIN 
    storage_current_month scm ON scm.DATABASE_NAME = db.DATABASE_NAME
    
WHERE db.deleted is null and usage.database_id is not null;








select top 10 * from SNOWFLAKE.ACCOUNT_USAGE.DATABASES ;

SELECT * FROM SNOWFLAKE.INFORMATION_SCHEMA.DATABASES ;
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASES;

    SELECT * FROM INFORMATION_SCHEMA.DATABASES; 

    DROP VIEW COMPANY_GOVERNANCE.SF_USAGE_METRICS.DATABASE_USAGE;


CREATE OR REPLACE VIEW COMPANY_GOVERNANCE.SF_USAGE_METRICS.DIM_DATE AS

SELECT * FROM COMMON_PROD.DWH.REF_DATE ;


CREATE OR REPLACE VIEW COMPANY_GOVERNANCE.SF_USAGE_METRICS.STAGES_ACTIVE AS

select * from snowflake.account_usage.stages where deleted is null ; 


create or replace view COMPANY_GOVERNANCE.SF_USAGE_METRICS.TABLES_ACTIVE(
	ID,
	TABLE_NAME,
	TABLE_SCHEMA_ID,
	TABLE_SCHEMA,
	TABLE_CATALOG_ID,
	TABLE_CATALOG,
	CLONE_GROUP_ID,
	IS_TRANSIENT,
    ACTIVE_GB,
    TIME_TRAVEL_GB,
    FAILSAFE_GB,
    RETAINED_FOR_CLONE_GB,
	DELETED,
	TABLE_CREATED,
	TABLE_DROPPED,
	TABLE_ENTERED_FAILSAFE,
	SCHEMA_CREATED,
	SCHEMA_DROPPED,
	CATALOG_CREATED,
	CATALOG_DROPPED,
	COMMENT,
	INSTANCE_ID
) as

SELECT 
    ID,
    TABLE_NAME,
    TABLE_SCHEMA_ID,
    TABLE_SCHEMA,
    TABLE_CATALOG_ID,
    TABLE_CATALOG,
    CLONE_GROUP_ID,
    IS_TRANSIENT,
    ACTIVE_BYTES / (1024 * 1024 * 1024) AS ACTIVE_GB,
    TIME_TRAVEL_BYTES / (1024 * 1024 * 1024) AS TIME_TRAVEL_GB,
    FAILSAFE_BYTES / (1024 * 1024 * 1024) AS FAILSAFE_GB,
    RETAINED_FOR_CLONE_BYTES / (1024 * 1024 * 1024) AS RETAINED_FOR_CLONE_GB,
    DELETED,
    TABLE_CREATED,
    TABLE_DROPPED,
    TABLE_ENTERED_FAILSAFE,
    SCHEMA_CREATED,
    SCHEMA_DROPPED,
    CATALOG_CREATED,
    CATALOG_DROPPED,
    COMMENT,
    INSTANCE_ID
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS 
WHERE ACTIVE_BYTES > 0 
  AND TABLE_DROPPED IS NULL; 





CREATE OR REPLACE VIEW COMPANY_GOVERNANCE.SF_USAGE_METRICS.STORAGE_USAGE AS

SELECT USAGE_DATE,STORAGE_BYTES,STAGE_BYTES,FAILSAFE_BYTES FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE ; 


CREATE OR REPLACE VIEW  DIM_TABLE AS
SELECT DISTINCT ID,TABLE_NAME, TABLE_SCHEMA_ID, TABLE_SCHEMA, TABLE_CATALOG_ID, TABLE_CATALOG  FROM COMPANY_GOVERNANCE.SF_USAGE_METRICS.TABLES_ACTIVE ; 

CREATE OR REPLACE VIEW DIM_WAREHOUSE AS
SELECT DISTINCT WAREHOUSE_ID, WAREHOUSE_NAME FROM COMPANY_GOVERNANCE.SF_USAGE_METRICS.WAREHOUSE_CLOUD_CREDITS ; 

CREATE OR REPLACE VIEW DIM_DATABASE AS
SELECT 
 DISTINCT     database_id,  DATABASE_NAME,
    FROM 
        SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE 
        YEAR(START_TIME) >= YEAR(DATEADD(month, -36, CURRENT_DATE)) and database_id is not null;

SELECT TOP 10 * FROM  SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY;
 CREATE OR REPLACE VIEW DIM_SCHEMA
 
 AS SELECT DISTINCT SCHEMA_ID, SCHEMA_NAME FROM SNOWFLAKE.ACCOUNT_USAGE.SCHEMATA ;
        


SELECT * FROM        COMPANY_GOVERNANCE.SF_USAGE_METRICS.DATABASE_USAGE_LM;



SELECT * FROM COMPANY_GOVERNANCE.TEST.COLLECTIONS_LINKAGES;
SELECT * FROM COMPANY_GOVERNANCE.TEST.PROPERTIES;


SHOW STAGES;


GRANT ROLE GOVERNANCE_COMPANY TO USER "USER@DUMMY.COM.AU"
