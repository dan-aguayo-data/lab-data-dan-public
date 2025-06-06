-- SNOWFLAKE ROLE GOVERNANCE & AUDIT SCRIPT
-- Purpose: Analyze role hierarchy, privileges, grants, and metadata for RBAC management

USE DATABASE SNOWFLAKE;
USE SCHEMA ACCOUNT_USAGE;

-- View all active roles
SELECT * 
FROM ACCOUNT_USAGE.ROLES 
WHERE DELETED_ON IS NULL AND ROLE_TYPE <> 'INSTANCE_ROLE' 
ORDER BY CREATED_ON;

-- Show enabled roles for current session
SELECT * FROM INFORMATION_SCHEMA.ENABLED_ROLES;

-- Analyze direct grants of roles to SYSADMIN
SELECT 
    NAME AS ROLE_GRANTED,
    GRANTEE_NAME AS GRANTEE_ROLE
FROM ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME = 'SYSADMIN'
  AND GRANTED_ON = 'ROLE'
  AND DELETED_ON IS NULL;

-- Role privilege exploration
SELECT * 
FROM ACCOUNT_USAGE.GRANTS_TO_ROLES 
WHERE DELETED_ON IS NULL 
ORDER BY GRANTEE_NAME;

-- Show users and their roles
SELECT * 
FROM ACCOUNT_USAGE.USERS 
LIMIT 100;

-- Role-to-user mapping
SELECT 
    ROLE AS ROLE_NAME, 
    COUNT(*) AS USER_COUNT
FROM ACCOUNT_USAGE.GRANTS_TO_USERS 
WHERE DELETED_ON IS NULL 
  AND GRANTED_TO = 'USER' 
GROUP BY ROLE;

-- Role-to-role mapping (hierarchy)
SELECT 
    NAME AS PARENT_ROLE,
    GRANTEE_NAME AS CHILD_ROLE
FROM ACCOUNT_USAGE.GRANTS_TO_ROLES 
WHERE DELETED_ON IS NULL 
  AND GRANTED_ON = 'ROLE' 
  AND PRIVILEGE = 'USAGE';

-- Recursive role hierarchy analysis (alternative - simplified)
WITH RECURSIVE role_hierarchy AS (
    SELECT
        ROLE_NAME,
        ROLE_OWNER AS PARENT_ROLE
    FROM INFORMATION_SCHEMA.ENABLED_ROLES
    WHERE ROLE_OWNER IS NOT NULL

    UNION ALL

    SELECT
        er.ROLE_NAME,
        rh.ROLE_NAME AS PARENT_ROLE
    FROM INFORMATION_SCHEMA.ENABLED_ROLES er
    JOIN role_hierarchy rh ON er.ROLE_OWNER = rh.ROLE_NAME
)
SELECT
    ROLE_NAME,
    PARENT_ROLE
FROM role_hierarchy
ORDER BY PARENT_ROLE, ROLE_NAME;

-- Role privilege audit (joined to users)
WITH All
