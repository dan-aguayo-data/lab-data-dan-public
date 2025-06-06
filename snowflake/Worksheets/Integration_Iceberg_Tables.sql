-- Example Snowflake SQL Setup for External Volumes and Iceberg Tables

-- USE A SAFE DATABASE
USE DATABASE BRONZE_DEV;

-- CREATE A SCHEMA FOR TESTING
CREATE SCHEMA IF NOT EXISTS BRONZE_DEV.TEST;

-- EXAMPLE TABLE REFERENCE (DUMMY SOURCE)
SELECT * FROM BRONZE_DEV.FINANCE.EXAMPLE_BALANCES;

-- OPTIONAL FILE FORMAT (PARQUET)
-- CREATE OR REPLACE FILE FORMAT BRONZE_DEV.TEST.PARQUET_GENERIC
--    TYPE = PARQUET;

-- CREATE STORAGE INTEGRATION WITH DUMMY PLACEHOLDERS
-- DO NOT INCLUDE SCHEMA OR DB NAME IN THE INTEGRATION NAME
-- Adjust ARNs and bucket paths before use
DROP STORAGE INTEGRATION IF EXISTS INT_ICEBERG_DEMO;

-- CREATE OR REPLACE STORAGE INTEGRATION INT_ICEBERG_DEMO
--   TYPE = EXTERNAL_STAGE
--   STORAGE_PROVIDER = 'S3'
--   ENABLED = TRUE
--   STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake_iceberg_access'
--   STORAGE_ALLOWED_LOCATIONS = ('s3://demo-bucket/iceberg-data/');

-- USE ROLES APPROPRIATELY
USE ROLE SYSADMIN;
USE SCHEMA TEST;

-- EXTERNAL VOLUME EXAMPLE (WITH PLACEHOLDER ARNs & URLs)
CREATE OR REPLACE EXTERNAL VOLUME exvol_iceberg_demo
  STORAGE_LOCATIONS = (
    (
      NAME = 'my-s3-iceberg-bucket'
      STORAGE_PROVIDER = 'S3'
      STORAGE_BASE_URL = 's3://demo-bucket/iceberg-data/'
      STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake_iceberg_access'
      -- ENCRYPTION=(TYPE='AWS_SSE_KMS' KMS_KEY_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx')
    )
  );

-- GRANT PRIVILEGES TO ROLES
GRANT ALL PRIVILEGES ON EXTERNAL VOLUME exvol_iceberg_demo TO ROLE SYSADMIN;

-- CREATE ICEBERG TABLE USING SNOWFLAKE CATALOG
USE ROLE SYSADMIN;
USE SCHEMA TEST;

CREATE OR REPLACE ICEBERG TABLE ref_codes_iceberg (
    REF_CODE_ID NUMBER(38,0),
    SCHEME_ID NUMBER(38,0),
    CATEGORY VARCHAR,
    CODE VARCHAR,
    VALUE VARCHAR,
    DESCRIPTION VARCHAR,
    EFFECTIVE_FROM TIMESTAMP_NTZ(6),
    EFFECTIVE_TO TIMESTAMP_NTZ(6),
    CREATED_BY VARCHAR,
    CREATED_ON TIMESTAMP_NTZ(6),
    LAST_MODIFIED_BY VARCHAR,
    LAST_MODIFIED_ON TIMESTAMP_NTZ(6),
    ROW_EDITING_ENABLED VARCHAR,
    ROW_DISPLAY_ENABLED VARCHAR
)
CATALOG = 'SNOWFLAKE'
EXTERNAL_VOLUME = 'exvol_iceberg_demo'
BASE_LOCATION = '';

-- SAMPLE DATA INSERT (DUMMY SOURCE)
INSERT INTO ref_codes_iceberg
SELECT * FROM BRONZE_DEV.FINANCE.REF_CODES_SAMPLE;

-- VALIDATE THE TABLE
SELECT * FROM BRONZE_DEV.ERP.EXAMPLE_FLEXFIELDS;
