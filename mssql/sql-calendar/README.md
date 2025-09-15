# SQL Calendar

A high-performance calendar utility implementation for SQL Server with comprehensive date calculations, business logic, and scheduling functionality.

## Overview

The `calendar` schema provides an optimized recurring date schedule generator and validator for fast date-based queries, business day calculations, and scheduling operations. It eliminates the need for complex date arithmetic in application code by providing ready-to-use date functions.

## Files

### Core Implementation
- **`calendar.sql`** - Generate calendar schema and inline table-valued utility functions

### Performance Benchmarks
- **`benches/calendar_datetrunc_benchmark.sql`** - Date truncation performance comparison
- **`benches/day_of_week_metadata_benchmark.sql`** - Day-of-week calculation optimization tests

### Usage Examples
- **`examples/generate_schedule_examples.sql`** - Recurring schedule generation patterns
- **`examples/is_scheduled_date_examples.sql`** - Business rule date validation examples

## Quick Start

### 1. Create Calendar Schema

Run `calendar.sql` script on the target database and apply appropriate permissions based on intended use.

### 2. Basic Usage Examples

```sql
-- Date truncation (replaces DATETRUNC for pre-2022 SQL Server)
SELECT truncated_date 
FROM calendar.datetrunc('month', '2025-09-15 14:30:00');
-- Returns: 2025-09-01

-- Get day of week metadata
SELECT day_name, iso_day_of_week, is_weekend, short_day_name
FROM calendar.day_of_week_metadata('2025-09-15');
-- Returns: Monday, 1, 0, Mon

-- Check if a date matches a schedule rule
SELECT is_scheduled
FROM calendar.is_scheduled_date(
    '2025-09-15',     -- candidate date (Monday)
    'WEEKLY',         -- rule type
    '2025-01-01',     -- start date
    '2025-12-31',     -- end date
    1,                -- every week
    5,                -- Monday(1) + Wednesday(4) bitmask = 5
    DEFAULT, DEFAULT, DEFAULT
);
-- Returns: 1 (true - matches Monday/Wednesday weekly schedule)
```

## Real-World Examples

### Recurring Schedule Generation

Based on [`examples/generate_schedule_examples.sql`](examples/generate_schedule_examples.sql):

```sql
-- Generate all Mondays and Wednesdays for Q1 2025
SELECT 'Weekly Mon/Wed' AS schedule_type, scheduled_date
FROM calendar.generate_schedule(
    'WEEKLY',         -- rule type
    '2025-01-01',     -- start date
    '2025-03-31',     -- end date
    1,                -- every week
    5,                -- Monday(1) + Wednesday(4) = 5
    DEFAULT, DEFAULT, DEFAULT
)
ORDER BY scheduled_date;

-- Generate first Monday of each month for 2025
SELECT 'First Monday' AS schedule_type, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_WEEKDAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT,          -- interval_weeks not used
    DEFAULT,          -- weekdays_mask not used  
    1,                -- 1st occurrence
    1,                -- Monday (1=Mon, 7=Sun)
    DEFAULT
)
ORDER BY scheduled_date;

-- Generate last business day of each month
SELECT 'Month-end Processing' AS schedule_type, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_BUSINESS_DAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    '-1'              -- last business day
)
ORDER BY scheduled_date;

-- Bi-weekly payroll (every other Friday)
SELECT 'Payroll Schedule' AS schedule_type, scheduled_date
FROM calendar.generate_schedule(
    'WEEKLY',
    '2025-01-03',     -- Start on first Friday
    '2025-12-31',
    2,                -- every 2 weeks
    16,               -- Friday bitmask (16)
    DEFAULT, DEFAULT, DEFAULT
)
ORDER BY scheduled_date;
```

### Date Validation and Business Rules

Based on [`examples/is_scheduled_date_examples.sql`](examples/is_scheduled_date_examples.sql):

```sql
-- Test if specific dates match a weekly Monday/Wednesday schedule
DECLARE @test_dates TABLE (test_date DATE, description NVARCHAR(100));
INSERT INTO @test_dates VALUES 
    ('2025-01-06', 'January 6th (Monday)'),
    ('2025-01-08', 'January 8th (Wednesday)'),
    ('2025-01-10', 'January 10th (Friday)');

SELECT 
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,
    'WEEKLY',
    '2025-01-01',
    '2025-12-31',
    1,                -- every week
    5,                -- Monday + Wednesday bitmask
    DEFAULT, DEFAULT, DEFAULT
) isd
ORDER BY td.test_date;
-- Results: Monday=1, Wednesday=1, Friday=0

-- Validate third Thursday maintenance schedule
SELECT 
    '2025-01-16' AS candidate_date,
    is_scheduled AS matches_third_thursday
FROM calendar.is_scheduled_date(
    '2025-01-16',     -- January 16th, 2025 (Thursday)
    'MONTHLY_BY_WEEKDAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT, DEFAULT,
    3,                -- 3rd occurrence
    4,                -- Thursday
    DEFAULT
);
-- Returns: 1 (true - Jan 16 is the 3rd Thursday)
```

## Advanced Scheduling Examples

### Complex Business Rules

```sql
-- Monthly reporting schedule: 2nd and 4th Monday, plus month-end
SELECT 'Monthly Reports' AS schedule_type, scheduled_date
FROM (
    -- 2nd Monday of each month
    SELECT scheduled_date FROM calendar.generate_schedule(
        'MONTHLY_BY_WEEKDAY', '2025-01-01', '2025-12-31',
        DEFAULT, DEFAULT, 2, 1, DEFAULT
    )
    UNION
    -- 4th Monday of each month  
    SELECT scheduled_date FROM calendar.generate_schedule(
        'MONTHLY_BY_WEEKDAY', '2025-01-01', '2025-12-31',
        DEFAULT, DEFAULT, 4, 1, DEFAULT
    )
    UNION
    -- Last business day of month
    SELECT scheduled_date FROM calendar.generate_schedule(
        'MONTHLY_BY_BUSINESS_DAY', '2025-01-01', '2025-12-31',
        DEFAULT, DEFAULT, DEFAULT, DEFAULT, '-1'
    )
) combined
ORDER BY scheduled_date;

-- Quarterly maintenance: First Saturday of each quarter
SELECT 'Quarterly Maintenance' AS schedule_type, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_WEEKDAY',
    '2025-01-01',
    '2025-12-31', 
    DEFAULT, DEFAULT,
    1,                -- 1st occurrence
    6,                -- Saturday
    DEFAULT
)
WHERE MONTH(scheduled_date) IN (1, 4, 7, 10)  -- Quarter months only
ORDER BY scheduled_date;
```

### Application Integration

```sql
-- ETL job scheduling validation
DECLARE @job_run_date DATE = GETDATE();
DECLARE @is_scheduled_run BIT;

SELECT @is_scheduled_run = is_scheduled
FROM calendar.is_scheduled_date(
    @job_run_date,
    'WEEKLY',
    '2025-01-01',
    '2025-12-31',
    1,                -- every week
    31,               -- Mon(1)+Tue(2)+Wed(4)+Thu(8)+Fri(16) = 31 (weekdays only)
    DEFAULT, DEFAULT, DEFAULT
);

IF @is_scheduled_run = 1
    EXEC sp_StartETLProcess;
ELSE
    PRINT 'ETL job not scheduled for today';

-- Dynamic report generation based on schedule
SELECT 
    r.report_name,
    r.schedule_rule,
    CASE 
        WHEN isd.is_scheduled = 1 THEN 'Run Report'
        ELSE 'Skip'
    END AS action
FROM Reports r
CROSS APPLY calendar.is_scheduled_date(
    GETDATE(),
    r.rule_type,
    r.start_date,
    r.end_date,
    r.interval_weeks,
    r.weekdays_mask,
    r.nth_occurrence,
    r.target_weekday,
    r.month_days
) isd
WHERE r.is_active = 1;
```

## Function Reference

### calendar.datetrunc(@datepart, @date)

Truncates a date to the specified datepart (replaces SQL Server 2022's DATETRUNC function).

**Parameters:**
- `@datepart NVARCHAR(20)` - 'year', 'quarter', 'month', 'week', 'day', 'hour', 'minute', 'second'
- `@date DATETIME2` - Input date to truncate

**Returns:** Table with `truncated_date` column

**Example:**
```sql
SELECT truncated_date FROM calendar.datetrunc('month', '2025-09-15 14:30:00');
-- Returns: 2025-09-01 00:00:00.0000000
```

### calendar.day_of_week_metadata(@date)

Gets comprehensive day-of-week information respecting @@DATEFIRST setting.

**Parameters:**
- `@date DATETIME2` - Input date

**Returns:** Table with columns:
- `input_date` - Original input date
- `day_name` - Full day name (e.g., 'Monday')
- `iso_day_of_week` - ISO weekday (1=Monday, 7=Sunday)
- `is_weekend` - Weekend flag (1=Saturday/Sunday, 0=weekday)
- `abbreviated_day_name` - Single letter ('M', 'T', 'W', 'Th', 'F', 'Sa', 'Su')
- `short_day_name` - Three letter abbreviation ('Mon', 'Tue', etc.)
- `long_day_name` - Full day name

**Example:**
```sql
SELECT * FROM calendar.day_of_week_metadata('2025-09-15');
-- Returns: Monday metadata with all format variations
```

### calendar.is_scheduled_date() - Date Validation

Validates if a specific date matches schedule rules.

**Parameters:**
- `@candidate_date DATE` - Date to test
- `@rule_type NVARCHAR(50)` - 'WEEKLY', 'WEEKLY_BUSINESS', 'MONTHLY_BY_WEEKDAY', 'MONTHLY_BY_BUSINESS_DAY', 'MONTHLY_BY_DAY'
- `@start_date DATE` - Schedule start date
- `@end_date DATE` - Schedule end date
- `@interval_weeks INT` - Week interval (default: 1)
- `@weekdays_mask INT` - Bitmask for weekdays (Mon=1, Tue=2, Wed=4, Thu=8, Fri=16, Sat=32, Sun=64)
- `@nth INT` - Occurrence in month (1=first, -1=last)
- `@weekday INT` - Target weekday (1=Monday, 7=Sunday)
- `@month_days NVARCHAR(100)` - Comma-separated month days

**Returns:** Table with `is_scheduled BIT` column

### calendar.generate_schedule() - Schedule Generation

Generates all dates matching schedule rules within a date range.

**Same parameters as is_scheduled_date (excluding candidate_date)**

**Returns:** Table with `scheduled_date DATE` column

**Bitmask Reference:**
- Monday: 1
- Tuesday: 2  
- Wednesday: 4
- Thursday: 8
- Friday: 16
- Saturday: 32
- Sunday: 64

**Common Combinations:**
- Weekdays only: 1+2+4+8+16 = 31
- Weekends only: 32+64 = 96
- Mon/Wed/Fri: 1+4+16 = 21
- Tue/Thu: 2+8 = 10

## Performance Characteristics

Based on benchmark testing in [`benches/`](benches/):

**calendar.datetrunc vs. manual date arithmetic:**
- Eliminates repetitive DATEPART/DATEFROMPARTS calls
- Consistent performance across different datepart values

**calendar.day_of_week_metadata vs. DATENAME/DATEPART:**
- Handles @@DATEFIRST variations automatically
- Single function call returns all common formats

**Schedule functions vs. application logic:**
- 100x+ faster than cursor-based date generation
- Eliminates complex WHILE loops in stored procedures
- Set-based operations optimize for large date ranges
```
