/*========================================================
 * SAMPLE QUERIES - calendar.is_scheduled_date
 * 
 * Demonstrates testing individual dates against schedule rules
 * using the optimized single-date validation function.
 *========================================================*/

-- Test dates for our examples
DECLARE @test_dates TABLE (test_date DATE, description NVARCHAR(100));
INSERT INTO @test_dates VALUES 
    ('2025-01-01', 'January 1st (Wednesday)'),
    ('2025-01-06', 'January 6th (Monday)'),  
    ('2025-01-08', 'January 8th (Wednesday)'),
    ('2025-01-10', 'January 10th (Friday)'),
    ('2025-01-15', 'January 15th (Wednesday)'),
    ('2025-01-31', 'January 31st (Friday - last day)'),
    ('2025-02-03', 'February 3rd (Monday - 1st business day)'),
    ('2025-02-14', 'February 14th (Friday)'),
    ('2025-02-28', 'February 28th (Friday - last day)');

/*========================================================
 * WEEKLY RULES
 *========================================================*/

-- Example 1: Weekly Monday/Wednesday schedule (bitmask 5 = 1+4)
SELECT 
    'Weekly Mon/Wed' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'WEEKLY',                  -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-12-31',              -- @end_date
    1,                         -- @interval_weeks (every week)
    5,                         -- @weekdays_mask (Mon=1, Wed=4, total=5)
    DEFAULT,                   -- @nth
    DEFAULT,                   -- @weekday
    DEFAULT                    -- @month_days
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

-- Example 2: Bi-weekly Friday schedule (bitmask 16)
SELECT 
    'Bi-weekly Friday' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'WEEKLY',                  -- @rule_type
    '2025-01-01',              -- @start_date (Wednesday)
    '2025-12-31',              -- @end_date
    2,                         -- @interval_weeks (every 2 weeks)
    16,                        -- @weekdays_mask (Friday=16)
    DEFAULT,                   -- @nth
    DEFAULT,                   -- @weekday
    DEFAULT                    -- @month_days
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

/*========================================================
 * WEEKLY BUSINESS RULES
 *========================================================*/

-- Example 3: Weekly business days (Monday-Friday)
SELECT 
    'Weekly Business Days' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'WEEKLY_BUSINESS',         -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-01-31',              -- @end_date
    1,                         -- @interval_weeks (every week)
    DEFAULT,                   -- @weekdays_mask (not used)
    DEFAULT,                   -- @nth
    DEFAULT,                   -- @weekday
    DEFAULT                    -- @month_days
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

/*========================================================
 * MONTHLY BY WEEKDAY RULES
 *========================================================*/

-- Example 4: First Monday of each month
SELECT 
    'First Monday' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'MONTHLY_BY_WEEKDAY',      -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-12-31',              -- @end_date
    DEFAULT,                   -- @interval_weeks (not used)
    DEFAULT,                   -- @weekdays_mask (not used)
    1,                         -- @nth (1st occurrence)
    1,                         -- @weekday (Monday=1)
    DEFAULT                    -- @month_days
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

-- Example 5: Last Friday of each month
SELECT 
    'Last Friday' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'MONTHLY_BY_WEEKDAY',      -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-12-31',              -- @end_date
    DEFAULT,                   -- @interval_weeks (not used)
    DEFAULT,                   -- @weekdays_mask (not used)
    -1,                        -- @nth (last occurrence)
    5,                         -- @weekday (Friday=5)
    DEFAULT                    -- @month_days
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

/*========================================================
 * MONTHLY BY BUSINESS DAY RULES
 *========================================================*/

-- Example 6: First business day of each month (legacy @nth parameter)
SELECT 
    'First Business Day' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'MONTHLY_BY_BUSINESS_DAY', -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-12-31',              -- @end_date
    DEFAULT,                   -- @interval_weeks (not used)
    DEFAULT,                   -- @weekdays_mask (not used)
    1,                         -- @nth (1st business day)
    DEFAULT,                   -- @weekday (not used)
    DEFAULT                    -- @month_days
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

-- Example 7: Multiple business days using @month_days (1st and 15th business days)
SELECT 
    '1st & 15th Business Days' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'MONTHLY_BY_BUSINESS_DAY', -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-12-31',              -- @end_date
    DEFAULT,                   -- @interval_weeks (not used)
    DEFAULT,                   -- @weekdays_mask (not used)
    DEFAULT,                   -- @nth (not used when @month_days provided)
    DEFAULT,                   -- @weekday (not used)
    '1,15'                     -- @month_days (1st and 15th business days)
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

-- Example 8: Last business day using @month_days
SELECT 
    'Last Business Day' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'MONTHLY_BY_BUSINESS_DAY', -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-12-31',              -- @end_date
    DEFAULT,                   -- @interval_weeks (not used)
    DEFAULT,                   -- @weekdays_mask (not used)
    DEFAULT,                   -- @nth (not used when @month_days provided)
    DEFAULT,                   -- @weekday (not used)
    '-1'                       -- @month_days (last business day)
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

/*========================================================
 * MONTHLY BY CALENDAR DAY RULES
 *========================================================*/

-- Example 9: 1st and 15th of each month (payroll schedule)
SELECT 
    '1st & 15th Calendar Days' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'MONTHLY_BY_DAY',          -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-12-31',              -- @end_date
    DEFAULT,                   -- @interval_weeks (not used)
    DEFAULT,                   -- @weekdays_mask (not used)
    DEFAULT,                   -- @nth (not used)
    DEFAULT,                   -- @weekday (not used)
    '1,15'                     -- @month_days (1st and 15th of month)
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

-- Example 10: Last day of each month
SELECT 
    'Last Day of Month' AS rule_name,
    td.description,
    td.test_date,
    isd.is_scheduled
FROM @test_dates td
CROSS APPLY calendar.is_scheduled_date(
    td.test_date,              -- @candidate_date
    'MONTHLY_BY_DAY',          -- @rule_type
    '2025-01-01',              -- @start_date
    '2025-12-31',              -- @end_date
    DEFAULT,                   -- @interval_weeks (not used)
    DEFAULT,                   -- @weekdays_mask (not used)
    DEFAULT,                   -- @nth (not used)
    DEFAULT,                   -- @weekday (not used)
    '-1'                       -- @month_days (last day of month)
) isd
WHERE isd.is_scheduled = 1
ORDER BY td.test_date;

/*========================================================
 * COMPREHENSIVE VALIDATION TEST
 *========================================================*/

-- Example 11: Test all rule types against a specific date
DECLARE @validation_date DATE = '2025-01-15';  -- Wednesday, January 15th

SELECT 
    'Validation Tests for ' + CAST(@validation_date AS NVARCHAR(10)) AS test_header,
    rule_name,
    CASE WHEN is_scheduled = 1 THEN '✓ MATCH' ELSE '✗ No match' END AS result
FROM (
    -- Weekly Monday/Wednesday
    SELECT 'Weekly Mon/Wed' AS rule_name, isd.is_scheduled
    FROM calendar.is_scheduled_date(@validation_date, 'WEEKLY', '2025-01-01', '2025-12-31', 1, 5, DEFAULT, DEFAULT, DEFAULT) isd
    
    UNION ALL
    
    -- Weekly business days
    SELECT 'Weekly Business', isd.is_scheduled
    FROM calendar.is_scheduled_date(@validation_date, 'WEEKLY_BUSINESS', '2025-01-01', '2025-12-31', 1, DEFAULT, DEFAULT, DEFAULT, DEFAULT) isd
    
    UNION ALL
    
    -- 15th of month
    SELECT '15th of Month', isd.is_scheduled
    FROM calendar.is_scheduled_date(@validation_date, 'MONTHLY_BY_DAY', '2025-01-01', '2025-12-31', DEFAULT, DEFAULT, DEFAULT, DEFAULT, '15') isd
    
    UNION ALL
    
    -- First Monday (should not match Jan 15th)
    SELECT 'First Monday', isd.is_scheduled
    FROM calendar.is_scheduled_date(@validation_date, 'MONTHLY_BY_WEEKDAY', '2025-01-01', '2025-12-31', DEFAULT, DEFAULT, 1, 1, DEFAULT) isd
    
    UNION ALL
    
    -- 15th business day (would need to calculate if Jan 15th is actually the 15th business day)
    SELECT '15th Business Day', isd.is_scheduled
    FROM calendar.is_scheduled_date(@validation_date, 'MONTHLY_BY_BUSINESS_DAY', '2025-01-01', '2025-12-31', DEFAULT, DEFAULT, DEFAULT, DEFAULT, '15') isd
) tests
ORDER BY rule_name;

/*========================================================
 * PERFORMANCE COMPARISON
 *========================================================*/

-- Example 12: Performance test - Single date vs generate_schedule + filter
SET STATISTICS TIME ON;

-- Method 1: Direct is_scheduled_date call (O(1))
SELECT 'Direct Validation' AS method, COUNT(*) AS matches
FROM (
    SELECT isd.is_scheduled
    FROM calendar.is_scheduled_date('2025-01-15', 'MONTHLY_BY_DAY', '2025-01-01', '2025-12-31', DEFAULT, DEFAULT, DEFAULT, DEFAULT, '1,15') isd
    WHERE isd.is_scheduled = 1
) direct_test;

-- Method 2: Generate all dates then filter (O(N))
SELECT 'Generate + Filter' AS method, COUNT(*) AS matches
FROM calendar.generate_schedule('MONTHLY_BY_DAY', '2025-01-01', '2025-12-31', DEFAULT, DEFAULT, DEFAULT, DEFAULT, '1,15') gs
WHERE gs.scheduled_date = '2025-01-15';

SET STATISTICS TIME OFF;

/*========================================================
 * USAGE NOTES:
 *========================================================

1. **Single Date Validation**: Use is_scheduled_date for checking individual dates
2. **Rule Type Support**: All generate_schedule rule types supported
3. **Parameter Compatibility**: Matches generate_schedule signature exactly
4. **Performance**: O(1) validation vs O(N) generation for single date checks
5. **Comma-separated Support**: @month_days supports multiple values like '1,15,-1'

COMMON USE CASES:
- Validate if today/tomorrow is a scheduled date
- Check individual dates in business logic
- Quick validation without generating full date ranges
- Input validation for scheduling systems
- Calendar integration and filtering

PARAMETER MAPPING:
- WEEKLY: Use @weekdays_mask and @interval_weeks
- WEEKLY_BUSINESS: Use @interval_weeks (automatically includes Mon-Fri)
- MONTHLY_BY_WEEKDAY: Use @nth and @weekday
- MONTHLY_BY_BUSINESS_DAY: Use @nth OR @month_days for business day positions
- MONTHLY_BY_DAY: Use @month_days for calendar day numbers

*/