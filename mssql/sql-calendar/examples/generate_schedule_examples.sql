
/*========================================================
 * SAMPLE QUERIES - calendar.generate_schedule
 *========================================================*/

-- Example 1: Weekly schedule - Every Monday and Wednesday for 3 months
-- Bitmask: Monday=1, Wednesday=4, so mask = 1+4 = 5
SELECT 'Weekly - Mon/Wed' AS example, scheduled_date
FROM calendar.generate_schedule(
    'WEEKLY',
    '2025-01-01',
    '2025-03-31', 
    1,  -- every week
    5,  -- Monday (1) + Wednesday (4) bitmask
    DEFAULT, DEFAULT, DEFAULT
)
ORDER BY scheduled_date;

-- Example 2: Bi-weekly schedule - Every Friday, every other week
-- Bitmask: Friday=16
SELECT 'Bi-weekly Friday' AS example, scheduled_date
FROM calendar.generate_schedule(
    'WEEKLY',
    '2025-01-01',
    '2025-06-30',
    2,  -- every 2 weeks 
    16, -- Friday bitmask
    DEFAULT, DEFAULT, DEFAULT
)
ORDER BY scheduled_date;

-- Example 3: Monthly - First Monday of each month
SELECT 'First Monday' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_WEEKDAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT, -- interval_weeks not used
    DEFAULT, -- weekdays_mask not used
    1,       -- 1st occurrence
    1,       -- Monday (1=Mon, 7=Sun)
    DEFAULT
)
ORDER BY scheduled_date;

-- Example 4: Monthly - Last Friday of each month
SELECT 'Last Friday' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_WEEKDAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT, -- interval_weeks not used
    DEFAULT, -- weekdays_mask not used
    -1,      -- last occurrence
    5,       -- Friday
    DEFAULT
)
ORDER BY scheduled_date;

-- Example 5: Monthly - Third Thursday of each month
SELECT 'Third Thursday' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_WEEKDAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT, DEFAULT, 
    3,       -- 3rd occurrence
    4,       -- Thursday
    DEFAULT
)
ORDER BY scheduled_date;

-- Example 6: Monthly - First business day of each month
SELECT 'First Business Day' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_BUSINESS_DAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    '1'     -- @month_days (position 8) - 1st business day
)
ORDER BY scheduled_date;

-- Example 7: Monthly - Last business day of each month
SELECT 'Last Business Day' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_BUSINESS_DAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    '-1'    -- @month_days (position 8) - last business day
)
ORDER BY scheduled_date;

-- Example 8: Monthly - 15th business day of each month (payroll example)
SELECT '15th Business Day' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_BUSINESS_DAY',
    '2025-01-01',
    '2025-12-31',
    DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    '15'    -- @month_days (position 8) - 15th business day
)
ORDER BY scheduled_date;

-- Example 9: Complex weekly - Tuesday, Thursday, Saturday every 3 weeks
-- Bitmask: Tuesday=2, Thursday=8, Saturday=32, so mask = 2+8+32 = 42
SELECT 'Tue/Thu/Sat every 3 weeks' AS example, scheduled_date
FROM calendar.generate_schedule(
    'WEEKLY',
    '2025-01-01',
    '2025-06-30',
    3,  -- every 3 weeks
    42, -- Tuesday + Thursday + Saturday
    DEFAULT, DEFAULT, DEFAULT
)
ORDER BY scheduled_date;

-- Example 10: Optimized Monday-Friday using WEEKLY_BUSINESS
SELECT 'Weekly Business (M-F optimized)' AS example, scheduled_date
FROM calendar.generate_schedule(
    'WEEKLY_BUSINESS',
    '2025-01-01',
    '2025-01-31',
    1,  -- every week  
    DEFAULT, DEFAULT, DEFAULT, DEFAULT
)
ORDER BY scheduled_date;

-- Example 11: Monthly calendar days - 1st and 15th (payroll)
SELECT '1st and 15th of month' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_DAY',           -- @rule_type (updated rule name)
    '2025-01-01',               -- @start_date
    '2025-06-30',               -- @end_date
    DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    '1,15'                     -- @month_days (position 8) - 1st and 15th of each month
)
ORDER BY scheduled_date;

-- Example 12: Monthly calendar days - 15th and last day (billing)
SELECT '15th and last day' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_DAY',           -- @rule_type (updated rule name)
    '2025-01-01',               -- @start_date
    '2025-06-30',               -- @end_date
    DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    '15,-1'                    -- @month_days (position 8) - 15th and last day of each month
)
ORDER BY scheduled_date;

-- Example 13: Multiple business days - 1st and 15th business days (enhanced payroll)
SELECT '1st and 15th business days' AS example, scheduled_date
FROM calendar.generate_schedule(
    'MONTHLY_BY_BUSINESS_DAY',  -- @rule_type
    '2025-01-01',               -- @start_date
    '2025-06-30',               -- @end_date
    DEFAULT, DEFAULT, DEFAULT, DEFAULT,
    '1,15'                     -- @month_days (position 8) - 1st and 15th business days
)
ORDER BY scheduled_date;