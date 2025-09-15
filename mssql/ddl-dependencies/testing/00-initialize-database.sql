-- ======================================================================================
-- DATABASE INITIALIZATION SCRIPT FOR TOGGLE SCHEMABINDING TESTING
-- ======================================================================================
-- This script creates the SchemaBindingTestDB database and all required schemas
-- Author: Joel Searcy
-- Created: September 2025
--
-- Purpose: Initialize the database and schemas before running ComplexEnterpriseSchema.sql
-- Prerequisites: SQL Server instance running with sufficient permissions
-- ======================================================================================

-- Check if we're in a supported SQL Server version
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) < 13
BEGIN
    PRINT 'ERROR: This script requires SQL Server 2016 (version 13) or later.';
    PRINT 'Current version: ' + CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50));
    RAISERROR('Unsupported SQL Server version', 16, 1);
    RETURN;
END

PRINT '======================================================================================';
PRINT 'INITIALIZING SCHEMABINDING TEST DATABASE';
PRINT 'SQL Server Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(50));
PRINT 'Edition: ' + CAST(SERVERPROPERTY('Edition') AS VARCHAR(100));
PRINT '======================================================================================';
PRINT '';

-- ======================================================================================
-- STEP 1: Create Database
-- ======================================================================================
PRINT 'Step 1: Creating SchemaBindingTestDB database...';

-- Check if database exists and drop if necessary
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SchemaBindingTestDB')
BEGIN
    PRINT 'Database SchemaBindingTestDB already exists. Dropping and recreating...';
    
    -- Set database to single user mode and drop
    ALTER DATABASE SchemaBindingTestDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SchemaBindingTestDB;
    
    PRINT 'Existing database dropped successfully.';
END

-- Create new database
CREATE DATABASE SchemaBindingTestDB
COLLATE SQL_Latin1_General_CP1_CI_AS;

PRINT 'Database SchemaBindingTestDB created successfully.';
GO

-- Switch to the new database
USE SchemaBindingTestDB;

-- Set database options for optimal testing
ALTER DATABASE SchemaBindingTestDB SET RECOVERY SIMPLE;
ALTER DATABASE SchemaBindingTestDB SET AUTO_CREATE_STATISTICS ON;
ALTER DATABASE SchemaBindingTestDB SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE SchemaBindingTestDB SET PAGE_VERIFY CHECKSUM;

PRINT 'Database options configured for testing.';
PRINT '';

-- ======================================================================================
-- STEP 2: Create Required Schemas
-- ======================================================================================
PRINT 'Step 2: Creating required schemas...';

-- Core business schemas
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Core')
BEGIN
    EXEC('CREATE SCHEMA Core AUTHORIZATION dbo');
    PRINT '✓ Core schema created';
END
ELSE
    PRINT '✓ Core schema already exists';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Financial')
BEGIN
    EXEC('CREATE SCHEMA Financial AUTHORIZATION dbo');
    PRINT '✓ Financial schema created';
END
ELSE
    PRINT '✓ Financial schema already exists';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Audit')
BEGIN
    EXEC('CREATE SCHEMA Audit AUTHORIZATION dbo');
    PRINT '✓ Audit schema created';
END
ELSE
    PRINT '✓ Audit schema already exists';

-- Analytics and reporting schemas
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Analytics')
BEGIN
    EXEC('CREATE SCHEMA Analytics AUTHORIZATION dbo');
    PRINT '✓ Analytics schema created';
END
ELSE
    PRINT '✓ Analytics schema already exists';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Sales')
BEGIN
    EXEC('CREATE SCHEMA Sales AUTHORIZATION dbo');
    PRINT '✓ Sales schema created';
END
ELSE
    PRINT '✓ Sales schema already exists';

-- Executive and strategic schemas
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Executive')
BEGIN
    EXEC('CREATE SCHEMA Executive AUTHORIZATION dbo');
    PRINT '✓ Executive schema created';
END
ELSE
    PRINT '✓ Executive schema already exists';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Research')
BEGIN
    EXEC('CREATE SCHEMA Research AUTHORIZATION dbo');
    PRINT '✓ Research schema created';
END
ELSE
    PRINT '✓ Research schema already exists';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Strategy')
BEGIN
    EXEC('CREATE SCHEMA Strategy AUTHORIZATION dbo');
    PRINT '✓ Strategy schema created';
END
ELSE
    PRINT '✓ Strategy schema already exists';

-- Risk and governance schemas
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Risk')
BEGIN
    EXEC('CREATE SCHEMA Risk AUTHORIZATION dbo');
    PRINT '✓ Risk schema created';
END
ELSE
    PRINT '✓ Risk schema already exists';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Governance')
BEGIN
    EXEC('CREATE SCHEMA Governance AUTHORIZATION dbo');
    PRINT '✓ Governance schema created';
END
ELSE
    PRINT '✓ Governance schema already exists';

-- Testing infrastructure schemas
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Performance')
BEGIN
    EXEC('CREATE SCHEMA Performance AUTHORIZATION dbo');
    PRINT '✓ Performance schema created';
END
ELSE
    PRINT '✓ Performance schema already exists';

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Validation')
BEGIN
    EXEC('CREATE SCHEMA Validation AUTHORIZATION dbo');
    PRINT '✓ Validation schema created';
END
ELSE
    PRINT '✓ Validation schema already exists';

-- DBA utilities schema (for the toggle procedures)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'DBA')
BEGIN
    EXEC('CREATE SCHEMA DBA AUTHORIZATION dbo');
    PRINT '✓ DBA schema created';
END
ELSE
    PRINT '✓ DBA schema already exists';

PRINT '';
PRINT 'All required schemas created successfully.';
PRINT '';

-- ======================================================================================
-- STEP 3: Verify Database Setup
-- ======================================================================================
PRINT 'Step 3: Verifying database setup...';

-- Check database properties
SELECT 
    'Database Properties' AS Category,
    name AS DatabaseName,
    collation_name AS Collation,
    compatibility_level AS CompatibilityLevel,
    state_desc AS State,
    recovery_model_desc AS RecoveryModel
FROM sys.databases 
WHERE name = 'SchemaBindingTestDB';

-- Check schemas
SELECT 
    'Schema Summary' AS Category,
    name AS SchemaName,
    principal_id AS OwnerID,
    SUSER_SNAME(principal_id) AS OwnerName
FROM sys.schemas 
WHERE schema_id > 4  -- Exclude system schemas
ORDER BY name;

-- Verify we're in the correct database
SELECT 
    'Current Context' AS Category,
    DB_NAME() AS CurrentDatabase,
    SUSER_SNAME() AS CurrentUser,
    GETDATE() AS SetupTime;

PRINT '';
PRINT '======================================================================================';
PRINT 'DATABASE INITIALIZATION COMPLETE';
PRINT '======================================================================================';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Run ComplexEnterpriseSchema.sql to create tables, views, and functions';
PRINT '2. Run install-original-procedures-2019-2022-2025.sql to install toggle procedures';
PRINT '3. Execute test scripts to validate the setup';
PRINT '';
PRINT 'Database is ready for ToggleSchemabinding testing!';
PRINT '';