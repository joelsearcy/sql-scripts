-- Fixed Performance Comparison Script
-- Tests Original vs Enhanced ToggleSchemabinding Procedures
-- Uses existing objects in SchemaBindingTestDB

USE SchemaBindingTestDB;
GO

-- Ensure we have clean execution plan cache for fair testing
DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;
GO

PRINT '========================================';
PRINT 'Performance Comparison: Original vs Enhanced Procedures';
PRINT 'Testing SQL Server 2017+ Feature Impact';
PRINT CONCAT('Test Date: ', GETDATE());
PRINT CONCAT('SQL Server Version: ', @@VERSION);
PRINT '========================================';
PRINT '';

-- Performance tracking table
CREATE TABLE #PerformanceResults (
    TestName NVARCHAR(100),
    ProcedureVersion NVARCHAR(50),
    TestNumber INT,
    StartTime DATETIME2(7),
    EndTime DATETIME2(7),
    DurationMS DECIMAL(10,3),
    ObjectName NVARCHAR(200)
);

-- Test parameters
DECLARE @testIterations INT = 10;
DECLARE @startTime DATETIME2(7);
DECLARE @endTime DATETIME2(7);
DECLARE @i INT;

PRINT 'Identifying available test objects...';

-- Get existing objects that support schema binding
CREATE TABLE #TestObjects (
    SchemaName SYSNAME,
    ObjectName SYSNAME,
    FullObjectName AS CONCAT(SchemaName, '.', ObjectName),
    ObjectType NVARCHAR(50)
);

INSERT INTO #TestObjects (SchemaName, ObjectName, ObjectType)
SELECT 
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS ObjectName,
    o.type_desc AS ObjectType
FROM sys.objects o
WHERE o.type IN ('V', 'FN', 'IF', 'TF')  -- Views and functions that can have schema binding
    AND SCHEMA_NAME(o.schema_id) IN ('Financial', 'Analytics', 'Core')  -- Focus on main schemas
    AND o.name IN ('TestView1', 'vw_AccountHierarchy', 'fn_GetAccountBalance', 'fn_CalculateOrderTotal', 'vw_EmployeeDetails')
ORDER BY SCHEMA_NAME(o.schema_id), o.name;

-- Display available test objects
SELECT 
    FullObjectName,
    ObjectType,
    CASE 
        WHEN EXISTS (SELECT 1 FROM sys.sql_modules sm WHERE sm.object_id = OBJECT_ID(FullObjectName) AND sm.is_schema_bound = 1)
        THEN 'Schema Bound'
        ELSE 'Not Schema Bound'
    END AS CurrentBinding
FROM #TestObjects
ORDER BY FullObjectName;

PRINT '';
PRINT 'Available test objects identified.';
PRINT '';

-- Test 1: Single Object Toggle Performance (Original vs Enhanced)
PRINT '==========================================';
PRINT 'TEST 1: Single Object Toggle Performance';
PRINT '==========================================';

-- Test Original Version
PRINT 'Testing Original hsp_ToggleSchemaBinding...';
SET @i = 1;
WHILE @i <= @testIterations
BEGIN
    -- Clear cache for fair testing every few iterations
    IF @i = 1 OR @i = 6  
    BEGIN
        DBCC FREEPROCCACHE;
    END

    -- Test with Financial.TestView1
    BEGIN TRY
        SET @startTime = SYSDATETIME();
        EXEC DBA.hsp_ToggleSchemaBinding @objectName = 'Financial.TestView1', @newIsSchemaBound = 1;
        EXEC DBA.hsp_ToggleSchemaBinding @objectName = 'Financial.TestView1', @newIsSchemaBound = 0;
        SET @endTime = SYSDATETIME();

        INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
        VALUES ('Single Object Toggle', 'Original', @i, @startTime, @endTime, 
                DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, 'Financial.TestView1');
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Error in Original test iteration ', @i, ': ', ERROR_MESSAGE());
        -- Try with a function instead
        BEGIN TRY
            SET @startTime = SYSDATETIME();
            EXEC DBA.hsp_ToggleSchemaBinding @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 1;
            EXEC DBA.hsp_ToggleSchemaBinding @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 0;
            SET @endTime = SYSDATETIME();

            INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
            VALUES ('Single Object Toggle', 'Original', @i, @startTime, @endTime, 
                    DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, 'Financial.fn_GetAccountBalance');
        END TRY
        BEGIN CATCH
            PRINT CONCAT('Error in Original test iteration ', @i, ' (fallback): ', ERROR_MESSAGE());
        END CATCH
    END CATCH

    SET @i = @i + 1;
END

-- Test Enhanced Version
PRINT 'Testing Enhanced hsp_ToggleSchemaBinding_enhanced...';
SET @i = 1;
WHILE @i <= @testIterations
BEGIN
    -- Clear cache for fair testing every few iterations
    IF @i = 1 OR @i = 6
    BEGIN
        DBCC FREEPROCCACHE;
    END

    -- Test with Financial.TestView1
    BEGIN TRY
        SET @startTime = SYSDATETIME();
        EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = 'Financial.TestView1', @newIsSchemaBound = 1;
        EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = 'Financial.TestView1', @newIsSchemaBound = 0;
        SET @endTime = SYSDATETIME();

        INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
        VALUES ('Single Object Toggle', 'Enhanced', @i, @startTime, @endTime, 
                DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, 'Financial.TestView1');
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Error in Enhanced test iteration ', @i, ': ', ERROR_MESSAGE());
        -- Try with a function instead
        BEGIN TRY
            SET @startTime = SYSDATETIME();
            EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 1;
            EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 0;
            SET @endTime = SYSDATETIME();

            INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
            VALUES ('Single Object Toggle', 'Enhanced', @i, @startTime, @endTime, 
                    DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, 'Financial.fn_GetAccountBalance');
        END TRY
        BEGIN CATCH
            PRINT CONCAT('Error in Enhanced test iteration ', @i, ' (fallback): ', ERROR_MESSAGE());
        END CATCH
    END CATCH

    SET @i = @i + 1;
END

-- Test 2: Multiple Object Performance (Enhanced Batch Only)
PRINT '';
PRINT '==========================================';
PRINT 'TEST 2: Enhanced Batch Processing Performance';
PRINT '==========================================';

-- Test Enhanced Batch Version
PRINT 'Testing Enhanced hsp_ToggleSchemaBindingBatch_enhanced...';

DECLARE @batchObjectList NVARCHAR(MAX) = 'Financial.fn_GetAccountBalance,Core.fn_CalculateOrderTotal,Financial.vw_AccountHierarchy';

SET @i = 1;
WHILE @i <= 5
BEGIN
    IF @i = 1 OR @i = 3
    BEGIN
        DBCC FREEPROCCACHE;
    END

    DECLARE @unbindSql NVARCHAR(MAX), @rebindSql NVARCHAR(MAX);
    
    BEGIN TRY
        SET @startTime = SYSDATETIME();
        EXEC DBA.hsp_ToggleSchemaBindingBatch_enhanced 
            @objectList = @batchObjectList,
            @mode = 'VARIABLE',
            @unbindSql = @unbindSql OUTPUT,
            @rebindSql = @rebindSql OUTPUT;
        SET @endTime = SYSDATETIME();

        INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
        VALUES ('Batch Processing', 'Enhanced', @i, @startTime, @endTime, 
                DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, @batchObjectList);
    END TRY
    BEGIN CATCH
        PRINT CONCAT('Error in Batch test iteration ', @i, ': ', ERROR_MESSAGE());
    END CATCH

    SET @i = @i + 1;
END

-- Test 3: Cold vs Warm Performance Analysis
PRINT '';
PRINT '==========================================';
PRINT 'TEST 3: Cold vs Warm Performance Analysis';
PRINT '==========================================';

-- Cold performance test (Original)
PRINT 'Testing Cold Performance - Original...';
DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;

BEGIN TRY
    SET @startTime = SYSDATETIME();
    EXEC DBA.hsp_ToggleSchemaBinding @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 1;
    EXEC DBA.hsp_ToggleSchemaBinding @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 0;
    SET @endTime = SYSDATETIME();

    INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
    VALUES ('Cold Performance', 'Original', 1, @startTime, @endTime, 
            DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, 'Financial.fn_GetAccountBalance');
END TRY
BEGIN CATCH
    PRINT CONCAT('Error in Cold Original test: ', ERROR_MESSAGE());
END CATCH

-- Warm performance test (Original)
PRINT 'Testing Warm Performance - Original...';
BEGIN TRY
    SET @startTime = SYSDATETIME();
    EXEC DBA.hsp_ToggleSchemaBinding @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 1;
    EXEC DBA.hsp_ToggleSchemaBinding @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 0;
    SET @endTime = SYSDATETIME();

    INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
    VALUES ('Warm Performance', 'Original', 1, @startTime, @endTime, 
            DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, 'Financial.fn_GetAccountBalance');
END TRY
BEGIN CATCH
    PRINT CONCAT('Error in Warm Original test: ', ERROR_MESSAGE());
END CATCH

-- Cold performance test (Enhanced)
PRINT 'Testing Cold Performance - Enhanced...';
DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;

BEGIN TRY
    SET @startTime = SYSDATETIME();
    EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 1;
    EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 0;
    SET @endTime = SYSDATETIME();

    INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
    VALUES ('Cold Performance', 'Enhanced', 1, @startTime, @endTime, 
            DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, 'Financial.fn_GetAccountBalance');
END TRY
BEGIN CATCH
    PRINT CONCAT('Error in Cold Enhanced test: ', ERROR_MESSAGE());
END CATCH

-- Warm performance test (Enhanced)
PRINT 'Testing Warm Performance - Enhanced...';
BEGIN TRY
    SET @startTime = SYSDATETIME();
    EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 1;
    EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = 'Financial.fn_GetAccountBalance', @newIsSchemaBound = 0;
    SET @endTime = SYSDATETIME();

    INSERT INTO #PerformanceResults (TestName, ProcedureVersion, TestNumber, StartTime, EndTime, DurationMS, ObjectName)
    VALUES ('Warm Performance', 'Enhanced', 1, @startTime, @endTime, 
            DATEDIFF(MICROSECOND, @startTime, @endTime) / 1000.0, 'Financial.fn_GetAccountBalance');
END TRY
BEGIN CATCH
    PRINT CONCAT('Error in Warm Enhanced test: ', ERROR_MESSAGE());
END CATCH

-- Generate Performance Analysis Report
PRINT '';
PRINT '========================================';
PRINT 'PERFORMANCE ANALYSIS RESULTS';
PRINT '========================================';

-- Check if we have results to analyze
IF EXISTS (SELECT 1 FROM #PerformanceResults)
BEGIN

    -- Single Object Performance Summary
    PRINT '';
    PRINT 'Single Object Toggle Performance Summary:';
    PRINT '-----------------------------------------';

    WITH SingleObjectStats AS (
        SELECT 
            ProcedureVersion,
            COUNT(*) as TestCount,
            AVG(DurationMS) as AvgDurationMS,
            MIN(DurationMS) as MinDurationMS,
            MAX(DurationMS) as MaxDurationMS,
            STDEV(DurationMS) as StdDevMS
        FROM #PerformanceResults 
        WHERE TestName = 'Single Object Toggle'
        GROUP BY ProcedureVersion
    ),
    PerformanceComparison AS (
        SELECT 
            *,
            LAG(AvgDurationMS) OVER (ORDER BY ProcedureVersion DESC) as CompareToMS
        FROM SingleObjectStats
    )
    SELECT 
        ProcedureVersion,
        TestCount,
        CONCAT(CAST(ROUND(AvgDurationMS, 2) AS VARCHAR(20)), ' ms') as AvgDuration,
        CONCAT(CAST(ROUND(MinDurationMS, 2) AS VARCHAR(20)), ' ms') as MinDuration,
        CONCAT(CAST(ROUND(MaxDurationMS, 2) AS VARCHAR(20)), ' ms') as MaxDuration,
        CASE 
            WHEN CompareToMS IS NOT NULL AND CompareToMS > 0 THEN 
                CONCAT(
                    CAST(ROUND(((CompareToMS - AvgDurationMS) / CompareToMS * 100), 2) AS VARCHAR(20)), 
                    '% ', 
                    CASE WHEN AvgDurationMS < CompareToMS THEN 'FASTER' ELSE 'SLOWER' END
                )
            ELSE 'BASELINE'
        END as PerformanceImprovement
    FROM PerformanceComparison
    ORDER BY ProcedureVersion;

    -- Cold vs Warm Performance Analysis
    PRINT '';
    PRINT 'Cold vs Warm Performance Analysis:';
    PRINT '----------------------------------';

    SELECT 
        TestName,
        ProcedureVersion,
        CONCAT(CAST(ROUND(DurationMS, 2) AS VARCHAR(20)), ' ms') as Duration,
        ObjectName,
        CASE TestName
            WHEN 'Cold Performance' THEN 'First execution (cold cache)'
            WHEN 'Warm Performance' THEN 'Subsequent execution (warm cache)'
        END as Description
    FROM #PerformanceResults 
    WHERE TestName IN ('Cold Performance', 'Warm Performance')
    ORDER BY ProcedureVersion, TestName;

    -- Detailed Performance Breakdown
    PRINT '';
    PRINT 'Detailed Performance Breakdown (First 20 Tests):';
    PRINT '------------------------------------------------';

    SELECT TOP 20
        TestName,
        ProcedureVersion,
        TestNumber,
        CONCAT(CAST(ROUND(DurationMS, 2) AS VARCHAR(20)), ' ms') as Duration,
        ObjectName,
        FORMAT(StartTime, 'HH:mm:ss.fffffff') as StartTime
    FROM #PerformanceResults 
    ORDER BY TestName, ProcedureVersion, TestNumber;

    -- SQL Server 2017+ Feature Impact Analysis
    PRINT '';
    PRINT 'SQL Server 2017+ Feature Impact Analysis:';
    PRINT '-----------------------------------------';

    WITH FeatureImpact AS (
        SELECT 
            'Overall Average Performance' as Metric,
            AVG(CASE WHEN ProcedureVersion = 'Original' THEN DurationMS END) as OriginalMS,
            AVG(CASE WHEN ProcedureVersion = 'Enhanced' THEN DurationMS END) as EnhancedMS
        FROM #PerformanceResults
        WHERE TestName = 'Single Object Toggle'
    )
    SELECT 
        Metric,
        CONCAT(CAST(ROUND(ISNULL(OriginalMS, 0), 2) AS VARCHAR(20)), ' ms') as OriginalAverage,
        CONCAT(CAST(ROUND(ISNULL(EnhancedMS, 0), 2) AS VARCHAR(20)), ' ms') as EnhancedAverage,
        CASE 
            WHEN OriginalMS IS NOT NULL AND EnhancedMS IS NOT NULL AND OriginalMS > 0 THEN
                CONCAT(
                    CAST(ROUND(((OriginalMS - EnhancedMS) / OriginalMS * 100), 2) AS VARCHAR(20)), 
                    '% ', 
                    CASE WHEN EnhancedMS < OriginalMS THEN 'IMPROVEMENT' ELSE 'REGRESSION' END
                )
            ELSE 'INSUFFICIENT DATA'
        END as PerformanceImpact
    FROM FeatureImpact;

END
ELSE
BEGIN
    PRINT 'No performance results were collected. Check for errors above.';
END

PRINT '';
PRINT 'Key SQL Server 2017+ Features Tested:';
PRINT '- CONCAT function vs traditional string concatenation';
PRINT '- IIF function vs CASE statements';  
PRINT '- STRING_AGG vs cursor-based aggregation';
PRINT '- STRING_SPLIT vs manual parsing';
PRINT '- Enhanced CTE patterns and query optimization';
PRINT '- Modern variable declaration patterns';
PRINT '';

-- Show errors if any
IF EXISTS (SELECT 1 FROM #PerformanceResults WHERE DurationMS IS NULL)
BEGIN
    PRINT 'Some tests failed - check error messages above for details.';
END

-- Cleanup
DROP TABLE #PerformanceResults;
DROP TABLE #TestObjects;

PRINT 'Performance comparison complete!';
PRINT CONCAT('Test completed at: ', GETDATE());
GO