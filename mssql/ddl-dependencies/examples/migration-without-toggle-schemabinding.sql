SET NOEXEC OFF;
SET ANSI_NULL_DFLT_ON ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

/*USE SchemaBindingTestDB;*/

PRINT CONCAT
(
	'/***********************************************/', CAST(0x0D0A AS CHAR(2)),
	'Login:		', ORIGINAL_LOGIN(), CAST(0x0D0A AS CHAR(2)),
	'Server:		', @@SERVERNAME, CAST(0x0D0A AS CHAR(2)),
	'Database:	', DB_NAME(), CAST(0x0D0A AS CHAR(2)),
	'Processed:	', SYSDATETIMEOFFSET(), CAST(0x0D0A AS CHAR(2)),
	'/***********************************************/'
);

/*========================================================
 * Migration Script - Manual Schema Binding Management
 * 
 * Purpose: Increase CustomerName column length from VARCHAR(100) to VARCHAR(150)
 * 
 * Dependency Chain (Top to Bottom):
 * - fn_CustomerAnalytics (Inline TVF) - depends on vw_CustomerSummary
 * - vw_CustomerSummary (View) - depends on vw_CustomerDetails  
 * - vw_CustomerDetails (Indexed View with SCHEMABINDING) - depends on Customers table
 * - Customers (Base Table) - contains CustomerName VARCHAR(100) column
 *
 * Manual Process: Remove schema binding from dependent objects in descending order,
 * modify table, then re-create objects with schema binding in ascending order.
 *========================================================*/

PRINT 'Starting manual schema binding migration...';
PRINT 'Target: Increase Customers.CustomerName from VARCHAR(100) to VARCHAR(150)';
PRINT '';

-- ======================================================================================
-- STEP 1: Remove schema binding from dependent objects (descending dependency order)
-- ======================================================================================

PRINT 'STEP 1: Removing schema binding from dependent objects...';

-- Drop fn_CustomerAnalytics (highest level dependency)
PRINT 'Dropping function: fn_CustomerAnalytics';
DROP FUNCTION IF EXISTS dbo.fn_CustomerAnalytics;

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

-- Drop vw_CustomerSummary (mid-level dependency)
PRINT 'Dropping view: vw_CustomerSummary';
DROP VIEW IF EXISTS dbo.vw_CustomerSummary;

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

-- Alter vw_CustomerDetails to remove SCHEMABINDING (altering an indexed view drops indexes)
PRINT 'Removing SCHEMABINDING from vw_CustomerDetails...';
GO
ALTER VIEW dbo.vw_CustomerDetails
AS
    SELECT 
        c.CustomerID,
        c.CustomerName,
        c.ContactName,
        c.Country,
        c.Region,
        c.City,
        c.CustomerSince,
        DATEDIFF(YEAR, c.CustomerSince, GETDATE()) AS YearsAsCustomer,
        CASE 
            WHEN DATEDIFF(YEAR, c.CustomerSince, GETDATE()) >= 10 THEN 'Platinum'
            WHEN DATEDIFF(YEAR, c.CustomerSince, GETDATE()) >= 5 THEN 'Gold'
            WHEN DATEDIFF(YEAR, c.CustomerSince, GETDATE()) >= 2 THEN 'Silver'
            ELSE 'Bronze'
        END AS CustomerTier
    FROM Core.Customers c
    WHERE c.CustomerName IS NOT NULL;

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

PRINT 'Step 1 completed: All schema binding removed from dependent objects.';
PRINT '';

-- ======================================================================================
-- STEP 2: Modify the base table column
-- ======================================================================================

PRINT 'STEP 2: Modifying base table column...';
PRINT 'Altering Customers.CustomerName: VARCHAR(100) -> VARCHAR(150)';

ALTER TABLE Core.Customers 
ALTER COLUMN CustomerName VARCHAR(150);

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

PRINT 'Step 2 completed: Table column modified successfully.';
PRINT '';

-- ======================================================================================
-- STEP 3: Re-create dependent objects with schema binding (ascending dependency order)
-- ======================================================================================

PRINT 'STEP 3: Re-creating dependent objects with schema binding...';

-- Re-create vw_CustomerDetails with SCHEMABINDING (lowest level dependency)
PRINT 'Re-creating vw_CustomerDetails with SCHEMABINDING...';
GO
ALTER VIEW dbo.vw_CustomerDetails
WITH SCHEMABINDING
AS
    SELECT 
        c.CustomerID,
        c.CustomerName,
        c.ContactName,
        c.Country,
        c.Region,
        c.City,
        c.CustomerSince,
        DATEDIFF(YEAR, c.CustomerSince, GETDATE()) AS YearsAsCustomer,
        CASE 
            WHEN DATEDIFF(YEAR, c.CustomerSince, GETDATE()) >= 10 THEN 'Platinum'
            WHEN DATEDIFF(YEAR, c.CustomerSince, GETDATE()) >= 5 THEN 'Gold'
            WHEN DATEDIFF(YEAR, c.CustomerSince, GETDATE()) >= 2 THEN 'Silver'
            ELSE 'Bronze'
        END AS CustomerTier
    FROM Core.Customers c
    WHERE c.CustomerName IS NOT NULL;

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

-- Re-create indexes on vw_CustomerDetails (required for indexed views)
PRINT 'Re-creating indexes on vw_CustomerDetails...';

-- Clustered index (required first for indexed views)
CREATE UNIQUE CLUSTERED INDEX IX_CustomerDetails_CustomerID 
ON dbo.vw_CustomerDetails (CustomerID);

-- Non-clustered indexes
CREATE NONCLUSTERED INDEX IX_CustomerDetails_CustomerName 
ON dbo.vw_CustomerDetails (CustomerName);

CREATE NONCLUSTERED INDEX IX_CustomerDetails_Region 
ON dbo.vw_CustomerDetails (Region, Country);

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

-- Re-create vw_CustomerSummary (mid-level dependency)
PRINT 'Re-creating vw_CustomerSummary...';
GO
CREATE VIEW dbo.vw_CustomerSummary
WITH SCHEMABINDING
AS
    SELECT 
        cd.CustomerID,
        cd.CustomerName,
        cd.Country,
        cd.Region,
        cd.CustomerTier,
        cd.YearsAsCustomer,
        CASE 
            WHEN cd.YearsAsCustomer >= 10 THEN 'Long-term'
            WHEN cd.YearsAsCustomer >= 5 THEN 'Established'
            WHEN cd.YearsAsCustomer >= 2 THEN 'Growing'
            ELSE 'New'
        END AS CustomerCategory,
        -- Calculate customer value score
        CASE cd.CustomerTier
            WHEN 'Platinum' THEN 100
            WHEN 'Gold' THEN 75
            WHEN 'Silver' THEN 50
            ELSE 25
        END AS CustomerScore
    FROM dbo.vw_CustomerDetails cd;

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

-- Re-create fn_CustomerAnalytics (highest level dependency)
PRINT 'Re-creating fn_CustomerAnalytics...';
GO
CREATE FUNCTION dbo.fn_CustomerAnalytics(@MinYears INT = 0)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT 
        cs.CustomerID,
        cs.CustomerName,
        cs.Country,
        cs.Region,
        cs.CustomerTier,
        cs.CustomerCategory,
        cs.CustomerScore,
        cs.YearsAsCustomer,
        -- Calculate analytics metrics
        CASE 
            WHEN cs.CustomerScore >= 75 THEN 'High Value'
            WHEN cs.CustomerScore >= 50 THEN 'Medium Value'
            ELSE 'Standard Value'
        END AS ValueSegment,
        -- Risk assessment
        CASE 
            WHEN cs.YearsAsCustomer < 1 THEN 'High Risk'
            WHEN cs.YearsAsCustomer < 3 THEN 'Medium Risk'
            ELSE 'Low Risk'
        END AS ChurnRisk
    FROM dbo.vw_CustomerSummary cs
    WHERE cs.YearsAsCustomer >= @MinYears
);

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

PRINT 'Step 3 completed: All dependent objects re-created with schema binding.';
PRINT '';

-- ======================================================================================
-- STEP 4: Validate the migration
-- ======================================================================================

PRINT 'STEP 4: Validating migration results...';

-- Test the modified column
DECLARE @column_info TABLE (
    table_name SYSNAME,
    column_name SYSNAME,
    data_type NVARCHAR(128),
    max_length INT,
    is_nullable BIT
);

INSERT INTO @column_info
SELECT 
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    CASE IS_NULLABLE WHEN 'YES' THEN 1 ELSE 0 END
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_SCHEMA = 'Core' 
  AND TABLE_NAME = 'Customers' 
  AND COLUMN_NAME = 'CustomerName';

PRINT 'Column modification validation:';
SELECT 
    'Core.Customers.CustomerName' AS ColumnPath,
    data_type AS DataType,
    max_length AS MaxLength,
    CASE WHEN max_length = 150 THEN 'SUCCESS' ELSE 'FAILED' END AS ValidationResult
FROM @column_info;

-- Test schema binding status
PRINT 'Schema binding validation:';
SELECT 
    SCHEMA_NAME(o.schema_id) + '.' + o.name AS ObjectName,
    o.type_desc AS ObjectType,
    CASE 
        WHEN sm.uses_ansi_nulls = 1 AND sm.uses_quoted_identifier = 1 
             AND CHARINDEX('SCHEMABINDING', sm.definition) > 0 
        THEN 'WITH SCHEMABINDING'
        ELSE 'WITHOUT SCHEMABINDING'
    END AS SchemaBindingStatus
FROM sys.objects o
INNER JOIN sys.sql_modules sm ON o.object_id = sm.object_id
WHERE o.name IN ('vw_CustomerDetails', 'vw_CustomerSummary', 'fn_CustomerAnalytics')
ORDER BY o.name;

-- Test functional connectivity
PRINT 'Functional connectivity test:';
SELECT 
    COUNT(*) AS CustomerCount,
    COUNT(DISTINCT CustomerTier) AS TierCount,
    COUNT(DISTINCT ValueSegment) AS ValueSegmentCount
FROM dbo.fn_CustomerAnalytics(0);

PRINT '';
PRINT 'Manual migration completed successfully!';
PRINT 'Summary: Modified CustomerName column length and manually managed schema binding dependencies.';

PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
--PRINT 'COMMIT'; COMMIT WORK;

/*
Manual Schema Binding Migration Notes:
======================================

This script demonstrates the traditional approach to managing schema binding 
during table modifications. Key characteristics:

CHALLENGES:
1. Complex dependency tracking - Must manually identify all dependent objects
2. Risk-prone process - Easy to miss dependencies or make errors in recreation
3. Extensive downtime - Objects unavailable during entire migration process
4. Index management - Must manually drop and recreate all indexes on indexed views
5. Definition management - Must maintain exact object definitions for recreation
6. Error recovery - Complex rollback process if something goes wrong mid-migration

STEPS REQUIRED:
1. Manual dependency analysis to determine correct drop/create order
2. Drop/alter all dependent objects from top to bottom of dependency chain
3. Modify the base table
4. Recreate all dependent objects from bottom to top with exact same definitions
5. Recreate all indexes with exact same specifications
6. Validate functionality and performance

RISKS:
- Human error in dependency identification
- Object definition drift during recreation
- Index specification errors
- Partial failures leaving system in inconsistent state
- Extended maintenance window requirements

This approach works but is labor-intensive and error-prone for complex dependency chains.
The "with toggle schemabinding" version demonstrates a much simpler approach.
*/