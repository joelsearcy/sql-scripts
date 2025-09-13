-- Performance Benchmark for calendar.datetrunc
-- This script benchmarks the performance of the calendar.datetrunc table-valued function.
-- It creates a test table, populates it with a large number of datetime2 values,
-- and measures the execution time of the function over the dataset.


SET NOCOUNT ON;

-- Table to store benchmark results
DROP TABLE IF EXISTS #BenchResults;
CREATE TABLE #BenchResults (
    test_name NVARCHAR(100) NOT NULL,
    duration_ms INT NOT NULL
);

-- 1. Create test table
DROP TABLE IF EXISTS #TestDates;
CREATE TABLE #TestDates (
    id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    dt DATETIME2 NOT NULL
);

-- 2. Populate with 1,000,000 rows (adjust as needed)

DECLARE @start DATETIME2 = '2010-01-01';
DECLARE @i INT = 0;
WHILE @i < 1000000
BEGIN
    INSERT INTO #TestDates (dt) VALUES (DATEADD(MINUTE, @i, @start));
    SET @i += 1;
END


-- Helper to run and time a test

DECLARE @t1 DATETIME2, @t2 DATETIME2, @elapsed INT;


-- CALENDAR.DATETRUNC (MONTH)
SET @t1 = SYSDATETIME();
SELECT COUNT(*)
FROM #TestDates t
CROSS APPLY calendar.datetrunc('month', t.dt) AS d;
SET @t2 = SYSDATETIME();
SET @elapsed = DATEDIFF(MS, @t1, @t2);
INSERT INTO #BenchResults(test_name, duration_ms) VALUES (N'calendar.datetrunc (month)', @elapsed);


-- CALENDAR.DATETRUNC (DAY)
SET @t1 = SYSDATETIME();
SELECT COUNT(*)
FROM #TestDates t
CROSS APPLY calendar.datetrunc('day', t.dt) AS d;
SET @t2 = SYSDATETIME();
SET @elapsed = DATEDIFF(MS, @t1, @t2);
INSERT INTO #BenchResults(test_name, duration_ms) VALUES (N'calendar.datetrunc (day)', @elapsed);


-- NATIVE T-SQL (MONTH) - DATEFROMPARTS
SET @t1 = SYSDATETIME();
SELECT COUNT(*)
FROM #TestDates t
CROSS APPLY (SELECT DATEFROMPARTS(YEAR(t.dt), MONTH(t.dt), 1) AS truncated_date) AS d;
SET @t2 = SYSDATETIME();
SET @elapsed = DATEDIFF(MS, @t1, @t2);
INSERT INTO #BenchResults(test_name, duration_ms) VALUES (N'Native T-SQL (month) - DATEFROMPARTS', @elapsed);


-- INLINED DATEADD/DATEDIFF (MONTH)
SET @t1 = SYSDATETIME();
SELECT COUNT(*)
FROM #TestDates t
CROSS APPLY (SELECT DATEADD(MONTH, DATEDIFF(MONTH, 0, t.dt), 0) AS truncated_date) AS d;
SET @t2 = SYSDATETIME();
SET @elapsed = DATEDIFF(MS, @t1, @t2);
INSERT INTO #BenchResults(test_name, duration_ms) VALUES (N'Inlined DATEADD/DATEDIFF (month)', @elapsed);


-- Output quartile distributions for each test

SELECT DISTINCT
    test_name,
    MIN(duration_ms) OVER (PARTITION BY test_name) AS p00_ms,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_ms) OVER (PARTITION BY test_name) AS p25_ms,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_ms) OVER (PARTITION BY test_name) AS p50_ms,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_ms) OVER (PARTITION BY test_name) AS p75_ms,
    MAX(duration_ms) OVER (PARTITION BY test_name) AS p100_ms
FROM #BenchResults;

DROP TABLE #TestDates;
DROP TABLE #BenchResults;
