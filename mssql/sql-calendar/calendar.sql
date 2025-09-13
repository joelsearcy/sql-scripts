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

/*USE ?;*/

PRINT CONCAT
(
	'/***********************************************/', CAST(0x0D0A AS CHAR(2)),
	'Login:		', ORIGINAL_LOGIN(), CAST(0x0D0A AS CHAR(2)),
	'Server:		', @@SERVERNAME, CAST(0x0D0A AS CHAR(2)),
	'Database:	', DB_NAME(), CAST(0x0D0A AS CHAR(2)),
	'Processed:	', SYSDATETIMEOFFSET(), CAST(0x0D0A AS CHAR(2)),
	'/***********************************************/'
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
CREATE SCHEMA calendar AUTHORIZATION dbo;
GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO
/*========================================================
 * Authors:     Joel Searcy
 * Create date: 2025-09-12
 * Description: Truncates a date to the specified datepart,
 *              prior to SQL Server 2022, which introduced
 *              the DATETRUNC function.
 *========================================================*/
CREATE FUNCTION calendar.datetrunc
(
    @datepart NVARCHAR(20),
    @date DATETIME2
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT
        CASE LOWER(@datepart)
            WHEN 'year' THEN DATEFROMPARTS(YEAR(@date), 1, 1)
            WHEN 'quarter' THEN DATEFROMPARTS(YEAR(@date), ((DATEPART(QUARTER, @date) - 1) * 3) + 1, 1)
            WHEN 'month' THEN DATEFROMPARTS(YEAR(@date), MONTH(@date), 1)
            WHEN 'week' THEN DATEADD(DAY, 1 - DATEPART(WEEKDAY, @date), CAST(@date AS DATE)) -- Assuming week starts on Sunday
            WHEN 'day' THEN CAST(@date AS DATE)
            WHEN 'hour' THEN DATEADD(HOUR, DATEPART(HOUR, @date), CAST(CAST(@date AS DATE) AS DATETIME2))
            WHEN 'minute' THEN DATEADD(MINUTE, DATEPART(MINUTE, @date), DATEADD(HOUR, DATEPART(HOUR, @date), CAST(CAST(@date AS DATE) AS DATETIME2)))
            WHEN 'second' THEN DATEADD(SECOND, DATEPART(SECOND, @date), DATEADD(MINUTE, DATEPART(MINUTE, @date), DATEADD(HOUR, DATEPART(HOUR, @date), CAST(CAST(@date AS DATE) AS DATETIME2))))
            ELSE NULL
        END AS truncated_date
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
/*========================================================
 * Authors:     Joel Searcy
 * Create date: 2025-09-12
 * Description: Gets metadata about the day of week
 *              including ISO weekday, day name, and whether it's a weekend,
 *              taking into account the current @@DATEFIRST setting.
 *========================================================*/
CREATE FUNCTION calendar.day_of_week_metadata
(
    @date DATETIME2
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT
        @date AS input_date,
        DATENAME(WEEKDAY, @date) AS day_name,
        ((DATEPART(WEEKDAY, @date) + @@DATEFIRST - 2) % 7 + 1) AS iso_day_of_week,
        CASE ((DATEPART(WEEKDAY, @date) + @@DATEFIRST - 2) % 7 + 1)
            WHEN 6 THEN 1
            WHEN 7 THEN 1
            ELSE 0
        END AS is_weekend,
        CASE ((DATEPART(WEEKDAY, @date) + @@DATEFIRST - 2) % 7 + 1)
            WHEN 1 THEN 'M'
            WHEN 2 THEN 'T'
            WHEN 3 THEN 'W'
            WHEN 4 THEN 'Th'
            WHEN 5 THEN 'F'
            WHEN 6 THEN 'Sa'
            WHEN 7 THEN 'Su'
            ELSE NULL
        END AS abbreviated_day_name,
        CASE ((DATEPART(WEEKDAY, @date) + @@DATEFIRST - 2) % 7 + 1)
            WHEN 1 THEN 'Mon'
            WHEN 2 THEN 'Tue'
            WHEN 3 THEN 'Wed'
            WHEN 4 THEN 'Thu'
            WHEN 5 THEN 'Fri'
            WHEN 6 THEN 'Sat'
            WHEN 7 THEN 'Sun'
            ELSE NULL
        END AS short_day_name,
        CASE ((DATEPART(WEEKDAY, @date) + @@DATEFIRST - 2) % 7 + 1)
            WHEN 1 THEN 'Monday'
            WHEN 2 THEN 'Tuesday'
            WHEN 3 THEN 'Wednesday'
            WHEN 4 THEN 'Thursday'
            WHEN 5 THEN 'Friday'
            WHEN 6 THEN 'Saturday'
            WHEN 7 THEN 'Sunday'
            ELSE NULL
        END AS long_day_name
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
-- While this is more maintainable than the above version, it is about 33% slower in testing.
-- /*========================================================
--  * Authors:     Joel Searcy
--  * Create date: 2025-09-12
--  * Description: Gets the ISO day of week (1=Monday, 7=Sunday),
--  *              day name, and whether it's a weekend,
--  *              taking into account the current @@DATEFIRST setting.
--  *========================================================*/
-- CREATE FUNCTION calendar.day_of_week_metadata_table
-- (
--     @date DATETIME2
-- )
-- RETURNS TABLE
-- WITH SCHEMABINDING
-- AS
-- RETURN
-- (
--     SELECT
--         @date AS input_date,
--         DATENAME(WEEKDAY, @date) AS day_name,
--         metadata.iso_day_of_week,
--         metadata.is_weekend,
--         metadata.abbreviated_day_name,
--         metadata.short_day_name,
--         metadata.long_day_name
--     FROM 
--     (VALUES
--         -- ISO weekday: 1=Monday, 7=Sunday
--         (1, 2, 0, 'M', 'Mon', 'Monday'),
--         (2, 3, 0, 'T', 'Tue', 'Tuesday'),
--         (3, 4, 0, 'W', 'Wed', 'Wednesday'),
--         (4, 5, 0, 'Th', 'Thu', 'Thursday'),
--         (5, 6, 0, 'F', 'Fri', 'Friday'),
--         (6, 7, 1, 'Sa', 'Sat', 'Saturday'),
--         (7, 1, 1, 'Su', 'Sun', 'Sunday')
--     ) AS metadata (iso_day_of_week, us_date_of_week, is_weekend, abbreviated_day_name, short_day_name, long_day_name)
--     WHERE
--         metadata.iso_day_of_week = ((DATEPART(WEEKDAY, @date) + @@DATEFIRST - 2) % 7 + 1)
-- );
GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO
/*========================================================
 * Authors:     Joel Searcy
 * Create date: 2025-09-12
 * Description: Determines if a candidate date matches the specified schedule rules.
 *========================================================*/
CREATE FUNCTION calendar.is_scheduled_date
(
    @candidate_date DATE,
    @rule_type NVARCHAR(50), /* 'WEEKLY', 'WEEKLY_BUSINESS', 'MONTHLY_BY_WEEKDAY', 'MONTHLY_BY_BUSINESS_DAY', 'MONTHLY_BY_DAY' */
    @start_date DATE,
    @end_date DATE,
    @interval_weeks INT = 1, 
    @weekdays_mask INT = NULL, /* Bitmask: 1=Mon, 2=Tue, 4=Wed, 8=Thu, 16=Fri, 32=Sat, 64=Sun */
    @nth INT = NULL, /* 1=1st, 2=2nd, ..., -1=last */
    @weekday INT = NULL, /* 1=Mon, 7=Sun */
    @month_days NVARCHAR(100) = NULL /* Comma-separated days of the month: '1,15' or '15,-1' (-1 = last day) */
)
RETURNS TABLE
AS
RETURN
(
    WITH
    -- Basic validation and date calculations
    date_info AS (
        SELECT 
            @candidate_date AS candidate_date,
            CASE WHEN @candidate_date BETWEEN @start_date AND @end_date THEN 1 ELSE 0 END AS in_range,
            ((DATEPART(WEEKDAY, @candidate_date) + @@DATEFIRST - 2) % 7) + 1 AS iso_weekday,
            ((DATEPART(WEEKDAY, @candidate_date) + @@DATEFIRST - 1) % 7) + 1 AS usa_weekday,
            DATEFROMPARTS(YEAR(@candidate_date), MONTH(@candidate_date), 1) AS month_start,
            EOMONTH(@candidate_date) AS month_end
    ),
    
    -- Weekly rule evaluation
    weekly_check AS (
        SELECT 
            CASE 
                WHEN @rule_type = 'WEEKLY' AND d.in_range = 1 AND @weekdays_mask IS NOT NULL
                    AND ((@weekdays_mask & POWER(2, d.iso_weekday - 1)) <> 0)
                    AND (DATEDIFF(WEEK, @start_date, @candidate_date) % @interval_weeks = 0)
                THEN 1 
                ELSE 0 
            END AS matches
        FROM date_info d
    ),
    
    -- Weekly business days rule evaluation (Monday-Friday only)
    weekly_business_check AS (
        SELECT 
            CASE 
                WHEN @rule_type = 'WEEKLY_BUSINESS' AND d.in_range = 1 
                    AND d.iso_weekday BETWEEN 1 AND 5  -- Monday through Friday
                    AND (DATEDIFF(WEEK, @start_date, @candidate_date) % @interval_weeks = 0)
                THEN 1 
                ELSE 0 
            END AS matches
        FROM date_info d
    ),
    
    -- Monthly by weekday rule evaluation
    monthly_weekday_check AS (
        SELECT 
            CASE 
                WHEN @rule_type = 'MONTHLY_BY_WEEKDAY' AND d.in_range = 1 AND @weekday IS NOT NULL AND @nth IS NOT NULL
                THEN
                    CASE 
                        WHEN d.iso_weekday = @weekday AND @nth <> -1
                        THEN
                            -- Check if candidate_date is the nth occurrence of the weekday in the month
                            CASE WHEN @candidate_date = DATEADD(DAY, 
                                (@weekday - ((DATEPART(WEEKDAY, d.month_start) + @@DATEFIRST - 2) % 7) - 1 + 7) % 7 + (@nth - 1) * 7, 
                                d.month_start) 
                            THEN 1 ELSE 0 END
                        WHEN d.iso_weekday = @weekday AND @nth = -1
                        THEN
                            -- Check if candidate_date is the last occurrence of the weekday in the month
                            CASE WHEN DATEADD(DAY, 7, @candidate_date) > d.month_end THEN 1 ELSE 0 END
                        ELSE 0
                    END
                ELSE 0 
            END AS matches
        FROM date_info d
    ),
    
    -- Monthly by business day rule evaluation  
    monthly_business_check AS (
        SELECT 
            CASE 
                WHEN @rule_type = 'MONTHLY_BY_BUSINESS_DAY' AND d.in_range = 1 
                    AND d.iso_weekday BETWEEN 1 AND 5 -- Must be a business day
                    AND (@nth IS NOT NULL OR @month_days IS NOT NULL)
                THEN
                    CASE 
                        -- Single @nth parameter (legacy support)
                        WHEN @nth IS NOT NULL AND @month_days IS NULL
                        THEN
                            CASE 
                                WHEN @nth = -1
                                THEN
                                    -- Check if candidate_date is the last business day of the month
                                    CASE WHEN EXISTS (
                                        SELECT 1 FROM (
                                            SELECT DATEADD(DAY, v.n, d.month_start) AS d,
                                                   ROW_NUMBER() OVER (ORDER BY DATEADD(DAY, v.n, d.month_start) DESC) AS reverse_rn
                                            FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM sys.all_objects) v
                                            WHERE v.n <= DATEDIFF(DAY, d.month_start, d.month_end)
                                              AND ((DATEPART(WEEKDAY, DATEADD(DAY, v.n, d.month_start)) + @@DATEFIRST - 2) % 7) + 1 BETWEEN 1 AND 5
                                        ) bd
                                        WHERE bd.d = @candidate_date AND bd.reverse_rn = 1
                                    ) THEN 1 ELSE 0 END
                                ELSE
                                    -- Check if candidate_date is the nth business day of the month
                                    CASE WHEN EXISTS (
                                        SELECT 1 FROM (
                                            SELECT DATEADD(DAY, v.n, d.month_start) AS d,
                                                   ROW_NUMBER() OVER (ORDER BY DATEADD(DAY, v.n, d.month_start)) AS rn
                                            FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM sys.all_objects) v
                                            WHERE v.n <= DATEDIFF(DAY, d.month_start, d.month_end)
                                              AND ((DATEPART(WEEKDAY, DATEADD(DAY, v.n, d.month_start)) + @@DATEFIRST - 2) % 7) + 1 BETWEEN 1 AND 5
                                        ) bd
                                        WHERE bd.d = @candidate_date AND bd.rn = @nth
                                    ) THEN 1 ELSE 0 END
                            END
                        -- Comma-separated @month_days parameter
                        WHEN @month_days IS NOT NULL
                        THEN
                            CASE WHEN EXISTS (
                                SELECT 1 FROM (
                                    -- Generate business days with numbering
                                    SELECT bd.d,
                                           ROW_NUMBER() OVER (ORDER BY bd.d) AS forward_rn,
                                           ROW_NUMBER() OVER (ORDER BY bd.d DESC) AS reverse_rn
                                    FROM (
                                        SELECT DATEADD(DAY, v.n, d.month_start) AS d
                                        FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM sys.all_objects) v
                                        WHERE v.n <= DATEDIFF(DAY, d.month_start, d.month_end)
                                          AND ((DATEPART(WEEKDAY, DATEADD(DAY, v.n, d.month_start)) + @@DATEFIRST - 2) % 7) + 1 BETWEEN 1 AND 5
                                    ) bd
                                ) numbered_bd
                                WHERE numbered_bd.d = @candidate_date
                                  AND (numbered_bd.forward_rn IN (
                                        SELECT CAST(TRIM(value) AS INT)
                                        FROM STRING_SPLIT(@month_days, ',')
                                        WHERE TRIM(value) <> '' 
                                          AND ISNUMERIC(TRIM(value)) = 1
                                          AND CAST(TRIM(value) AS INT) BETWEEN 1 AND 23
                                      )
                                      OR (numbered_bd.reverse_rn = 1 AND EXISTS (
                                        SELECT 1 FROM STRING_SPLIT(@month_days, ',')
                                        WHERE TRIM(value) = '-1'
                                      )))
                            ) THEN 1 ELSE 0 END
                        ELSE 0
                    END
                ELSE 0 
            END AS matches
        FROM date_info d
    ),
    
    -- Monthly by calendar day rule evaluation
    monthly_calendar_check AS (
    SELECT 
        MAX(CASE 
            WHEN @rule_type = 'MONTHLY_BY_DAY' AND d.in_range = 1 AND @month_days IS NOT NULL
            THEN CASE 
                    WHEN cd.day_num = -1 AND @candidate_date = d.month_end THEN 1
                    WHEN cd.day_num > 0 AND cd.day_num <= DAY(d.month_end) 
                            AND @candidate_date = DATEFROMPARTS(YEAR(@candidate_date), MONTH(@candidate_date), cd.day_num) THEN 1
                    ELSE 0 
                END
            ELSE 0 
        END) AS matches
    FROM date_info d
    OUTER APPLY (
        SELECT CAST(TRIM(value) AS INT) AS day_num
        FROM STRING_SPLIT(@month_days, ',')
        WHERE TRIM(value) <> '' 
            AND ISNUMERIC(TRIM(value)) = 1
            AND (CAST(TRIM(value) AS INT) BETWEEN 1 AND 31 OR CAST(TRIM(value) AS INT) = -1)
    ) cd
)
    
    -- Final result
    SELECT CAST(
        CASE 
            WHEN (SELECT matches FROM weekly_check) = 1 THEN 1
            WHEN (SELECT matches FROM weekly_business_check) = 1 THEN 1
            WHEN (SELECT matches FROM monthly_weekday_check) = 1 THEN 1  
            WHEN (SELECT matches FROM monthly_business_check) = 1 THEN 1
            WHEN (SELECT matches FROM monthly_calendar_check) = 1 THEN 1
            ELSE 0
        END AS BIT
    ) AS is_scheduled
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
/*========================================================
 * Authors:     Joel Searcy
 * Create date: 2025-09-12
 * Description: Efficiently generates all dates matching schedule rules using set-based calculations.
 *========================================================*/
CREATE FUNCTION calendar.generate_schedule
(
    @rule_type NVARCHAR(50), /* 'WEEKLY', 'MONTHLY_BY_WEEKDAY', 'MONTHLY_BY_BUSINESS_DAY', 'MONTHLY_BY_DAY' */
    @start_date DATE,
    @end_date DATE,
    @interval_weeks INT = 1, 
    @weekdays_mask INT = NULL, /* Bitmask: 1=Mon, 2=Tue, 4=Wed, 8=Thu, 16=Fri, 32=Sat, 64=Sun */
    @nth INT = NULL, /* 1=1st, 2=2nd, ..., -1=last */
    @weekday INT = NULL, /* 1=Mon, 7=Sun */
    @month_days NVARCHAR(100) = NULL /* Comma-separated days of the month: '1,15' or '15,-1' (-1 = last day) */
)
RETURNS TABLE
AS
RETURN
(
    WITH
    -- Generate minimal candidate dates based on rule type
    candidates AS (
        -- For WEEKLY_BUSINESS: Optimized Monday-Friday generation (single calculation)
        SELECT candidate_date
        FROM (
            SELECT DATEADD(DAY, 
                (wd.weekday_num - ((DATEPART(WEEKDAY, @start_date) + @@DATEFIRST - 2) % 7) - 1 + 7) % 7 + (v.n * 7 * @interval_weeks), 
                @start_date) AS candidate_date
            FROM (
                SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n 
                FROM sys.all_objects a
            ) v
            CROSS JOIN (
                SELECT 1 AS weekday_num  -- Monday
                UNION ALL SELECT 2       -- Tuesday  
                UNION ALL SELECT 3       -- Wednesday
                UNION ALL SELECT 4       -- Thursday
                UNION ALL SELECT 5       -- Friday
            ) wd
            WHERE @rule_type = 'WEEKLY_BUSINESS'
              AND v.n <= DATEDIFF(DAY, @start_date, @end_date) / (@interval_weeks * 7) + 1
        ) business_dates
        WHERE candidate_date BETWEEN @start_date AND @end_date

        UNION ALL

        -- For WEEKLY: generate dates for each weekday in the bitmask
        SELECT candidate_date
        FROM (
            SELECT DATEADD(DAY, 
                (wd.weekday_num - ((DATEPART(WEEKDAY, @start_date) + @@DATEFIRST - 2) % 7) - 1 + 7) % 7 + (v.n * 7 * @interval_weeks), 
                @start_date) AS candidate_date
            FROM (
                SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n 
                FROM sys.all_objects a
            ) v
            CROSS JOIN (
                SELECT weekday_num
                FROM (VALUES 
                    (1, 1),    -- Monday, bitmask 1
                    (2, 2),    -- Tuesday, bitmask 2  
                    (3, 4),    -- Wednesday, bitmask 4
                    (4, 8),    -- Thursday, bitmask 8
                    (5, 16),   -- Friday, bitmask 16
                    (6, 32),   -- Saturday, bitmask 32
                    (7, 64)    -- Sunday, bitmask 64
                ) AS weekdays(weekday_num, bitmask_value)
                WHERE (@weekdays_mask & bitmask_value) <> 0
            ) wd
            WHERE @rule_type = 'WEEKLY' AND @weekdays_mask IS NOT NULL
              AND v.n <= DATEDIFF(DAY, @start_date, @end_date) / (@interval_weeks * 7) + 1
        ) weekly_dates
        WHERE candidate_date BETWEEN @start_date AND @end_date
        
        UNION ALL
        
        -- For MONTHLY_BY_WEEKDAY: generate one date per month
        SELECT candidate_date
        FROM (
            SELECT 
                CASE 
                    WHEN @nth = -1 THEN
                        -- Last occurrence: start from end of month and go back
                        DATEADD(DAY, 
                            -(((DATEPART(WEEKDAY, EOMONTH(month_first)) + @@DATEFIRST - 2) % 7) + 1 - @weekday + 7) % 7,
                            EOMONTH(month_first))
                    ELSE
                        -- Nth occurrence: calculate from start of month
                        DATEADD(DAY, 
                            (@weekday - ((DATEPART(WEEKDAY, month_first) + @@DATEFIRST - 2) % 7) - 1 + 7) % 7 + (@nth - 1) * 7, 
                            month_first)
                END AS candidate_date
            FROM (
                SELECT DATEFROMPARTS(YEAR(@start_date) + (v.n / 12), MONTH(@start_date) + (v.n % 12), 1) AS month_first
                FROM (
                    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n 
                    FROM sys.all_objects
                ) v
                WHERE @rule_type = 'MONTHLY_BY_WEEKDAY' AND @weekday IS NOT NULL AND @nth IS NOT NULL
                  AND v.n <= DATEDIFF(MONTH, @start_date, @end_date) + 1
            ) months
        ) monthly_weekday_dates
        WHERE candidate_date BETWEEN @start_date AND @end_date
        
        UNION ALL
        
        -- For MONTHLY_BY_BUSINESS_DAY: generate business days per month
        SELECT candidate_date
        FROM (
            SELECT 
                CASE 
                    WHEN bd.nth_position = -1 THEN
                        -- Last business day of month
                        (SELECT MAX(bd_calc.d)
                         FROM (
                             SELECT DATEADD(DAY, bd_v.n, month_first) AS d
                             FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM sys.all_objects) bd_v
                             WHERE bd_v.n <= DATEDIFF(DAY, month_first, EOMONTH(month_first))
                               AND ((DATEPART(WEEKDAY, DATEADD(DAY, bd_v.n, month_first)) + @@DATEFIRST - 2) % 7) + 1 BETWEEN 1 AND 5
                         ) bd_calc)
                    ELSE
                        -- Nth business day of month
                        (SELECT bd_calc.d
                         FROM (
                             SELECT DATEADD(DAY, bd_v.n, month_first) AS d,
                                    ROW_NUMBER() OVER (ORDER BY DATEADD(DAY, bd_v.n, month_first)) AS rn
                             FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n FROM sys.all_objects) bd_v
                             WHERE bd_v.n <= DATEDIFF(DAY, month_first, EOMONTH(month_first))
                               AND ((DATEPART(WEEKDAY, DATEADD(DAY, bd_v.n, month_first)) + @@DATEFIRST - 2) % 7) + 1 BETWEEN 1 AND 5
                         ) bd_calc
                         WHERE bd_calc.rn = bd.nth_position)
                END AS candidate_date
            FROM (
                SELECT DATEFROMPARTS(YEAR(@start_date) + (v.n / 12), MONTH(@start_date) + (v.n % 12), 1) AS month_first
                FROM (
                    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n 
                    FROM sys.all_objects
                ) v
                WHERE @rule_type = 'MONTHLY_BY_BUSINESS_DAY' 
                  AND (@nth IS NOT NULL OR @month_days IS NOT NULL)
                  AND v.n <= DATEDIFF(MONTH, @start_date, @end_date) + 1
            ) months
            CROSS JOIN (
                -- Support both single @nth and comma-separated @month_days
                SELECT @nth AS nth_position
                WHERE @nth IS NOT NULL AND @month_days IS NULL
                
                UNION ALL
                
                -- Parse comma-separated business day positions
                SELECT CAST(TRIM(value) AS INT) AS nth_position
                FROM STRING_SPLIT(@month_days, ',')
                WHERE @month_days IS NOT NULL
                  AND TRIM(value) <> '' 
                  AND ISNUMERIC(TRIM(value)) = 1
                  AND (CAST(TRIM(value) AS INT) BETWEEN 1 AND 23 OR CAST(TRIM(value) AS INT) = -1)
            ) bd
        ) monthly_business_dates
        WHERE candidate_date BETWEEN @start_date AND @end_date
          AND candidate_date IS NOT NULL
          
        UNION ALL
        
        -- For MONTHLY_BY_DAY: generate specific calendar days per month
        SELECT candidate_date
        FROM (
            SELECT 
                CASE 
                    WHEN cd.day_num = -1 THEN
                        -- Last day of month
                        EOMONTH(month_first)
                    ELSE
                        -- Specific day of month (handle invalid dates gracefully)
                        CASE 
                            WHEN cd.day_num <= DAY(EOMONTH(month_first)) THEN
                                DATEFROMPARTS(YEAR(month_first), MONTH(month_first), cd.day_num)
                            ELSE NULL  -- Invalid date (e.g., Feb 30)
                        END
                END AS candidate_date
            FROM (
                SELECT DATEFROMPARTS(YEAR(@start_date) + (v.n / 12), MONTH(@start_date) + (v.n % 12), 1) AS month_first
                FROM (
                    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n 
                    FROM sys.all_objects
                ) v
                WHERE @rule_type = 'MONTHLY_BY_DAY' AND @month_days IS NOT NULL
                  AND v.n <= DATEDIFF(MONTH, @start_date, @end_date) + 1
            ) months
            CROSS JOIN (
                -- Parse comma-separated calendar days
                SELECT CAST(TRIM(value) AS INT) AS day_num
                FROM STRING_SPLIT(@month_days, ',')
                WHERE TRIM(value) <> '' 
                  AND ISNUMERIC(TRIM(value)) = 1
                  AND (CAST(TRIM(value) AS INT) BETWEEN 1 AND 31 OR CAST(TRIM(value) AS INT) = -1)
            ) cd
        ) monthly_calendar_dates
        WHERE candidate_date BETWEEN @start_date AND @end_date
          AND candidate_date IS NOT NULL
    )
    
    SELECT DISTINCT candidate_date AS scheduled_date
    FROM candidates
    WHERE candidate_date IS NOT NULL
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

-- PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
PRINT 'COMMIT'; COMMIT WORK;
/*

*/