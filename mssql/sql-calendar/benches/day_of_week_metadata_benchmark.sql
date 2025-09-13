-- Benchmark: calendar.day_of_week_metadata_v1 vs v2
-- Creates test data, runs multiple iterations of each function, captures durations,
-- and outputs summary statistics (min, max, avg, p25, p50, p75).

SET NOCOUNT ON;

-- Parameters - adjust as needed
DECLARE @rows INT = 100000;          -- number of test rows
DECLARE @iterations INT = 5;         -- how many times to run each test (for distribution)
DECLARE @start DATETIME2 = '2024-01-01';

-- Prepare results table
IF OBJECT_ID('tempdb..#BenchResults') IS NOT NULL DROP TABLE #BenchResults;
CREATE TABLE #BenchResults (
    test_name NVARCHAR(100),
    iteration INT,
    duration_ms INT
);

-- Prepare test data
IF OBJECT_ID('tempdb..#TestDates') IS NOT NULL DROP TABLE #TestDates;
CREATE TABLE #TestDates (
    id INT IDENTITY(1,1) PRIMARY KEY,
    dt DATETIME2 NOT NULL
);

-- Populate test dates using set-based method for speed
;WITH nums AS (
    SELECT TOP (@rows) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO #TestDates (dt)
SELECT DATEADD(MINUTE, n, @start)
FROM nums;

-- Helper variables
DECLARE @i INT = 1;
DECLARE @t1 DATETIME2, @t2 DATETIME2, @elapsed INT;

-- Run benchmarks
WHILE @i <= @iterations
BEGIN
    -- v1
    SET @t1 = SYSDATETIME();
    SELECT COUNT(*)
    FROM #TestDates t
    CROSS APPLY calendar.day_of_week_metadata(t.dt) m;
    SET @t2 = SYSDATETIME();
    SET @elapsed = DATEDIFF(MS, @t1, @t2);
    INSERT INTO #BenchResults(test_name, iteration, duration_ms) VALUES (N'v1', @i, @elapsed);

    -- v2
    SET @t1 = SYSDATETIME();
    SELECT COUNT(*)
    FROM #TestDates t
    CROSS APPLY calendar.day_of_week_metadata_table(t.dt) m;
    SET @t2 = SYSDATETIME();
    SET @elapsed = DATEDIFF(MS, @t1, @t2);
    INSERT INTO #BenchResults(test_name, iteration, duration_ms) VALUES (N'v2', @i, @elapsed);

    SET @i += 1;
END

-- Output summary statistics
SELECT DISTINCT
    test_name,
    MIN(duration_ms) OVER (PARTITION BY test_name) AS p00_ms,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_ms) OVER (PARTITION BY test_name) AS p25_ms,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_ms) OVER (PARTITION BY test_name) AS p50_ms,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_ms) OVER (PARTITION BY test_name) AS p75_ms,
    MAX(duration_ms) OVER (PARTITION BY test_name) AS p100_ms
FROM #BenchResults;

-- Cleanup
DROP TABLE #TestDates;
DROP TABLE #BenchResults;

PRINT 'Benchmark complete.';
