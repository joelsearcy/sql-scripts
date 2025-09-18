SET NOEXEC OFF;
SET ANSI_NULL_DFLT_ON ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

PRINT CONCAT
(
	'/***********************************************/', CAST(0x0D0A AS CHAR(2)),
	'Login:		', ORIGINAL_LOGIN(), CAST(0x0D0A AS CHAR(2)),
	'Server:		', @@SERVERNAME, CAST(0x0D0A AS CHAR(2)),
	'Database:	', DB_NAME(), CAST(0x0D0A AS CHAR(2)),
	'Processed:	', SYSDATETIMEOFFSET(), CAST(0x0D0A AS CHAR(2)),
	'/***********************************************/'
);

IF (TYPE_ID('dbo.tvp_DatePeriod') IS NULL)
BEGIN
	-- This is outside of the transaction because creating the type inside the same transaction as a referencing object results in a deadlock.
	-- Feel free to move this inside the transaction if you want to see the deadlock happen. :)
	CREATE TYPE dbo.tvp_DatePeriod AS TABLE
	(
		partitionId INT NOT NULL,
		startDate DATE NOT NULL,
		endDate DATE NOT NULL
	);

	GRANT EXECUTE ON TYPE::dbo.tvp_DatePeriod TO [public];
END;

BEGIN TRANSACTION

CREATE TABLE dbo.DatePeriod
(
    datePeriodId INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_DatePeriod_datePeriodId PRIMARY KEY,
    customerId INT NOT NULL,
        -- CONSTRAINT FK_DatePeriod_Customer_customerId
        --     FOREIGN KEY REFERENCES dbo.Customer(customerId),
    startDate DATE NOT NULL,
    endDate DATE NOT NULL,
    rowCreatedAtTimeUtc DATETIME2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    rowUpdatedAtTimeUtc DATETIME2(3) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (rowCreatedAtTimeUtc, rowUpdatedAtTimeUtc),
    CONSTRAINT CK_VL_DatePeriod_ValidRange CHECK (endDate >= startDate)
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
 * Create date: 2025-09-16
 * Description: Flattens (or merges) overlapping and adjacent date periods.
 *========================================================*/
CREATE VIEW dbo.V_FlattenedDatePeriod
WITH SCHEMABINDING
AS
SELECT
	IntervalGroup.customerId,
	MIN(IntervalGroup.boundaryValue) AS startDate,
	MAX(IntervalGroup.boundaryValue) AS endDate
FROM
	(
		SELECT
			Interval.customerId,
			-- Adjust dates using the boundaryValueOffset
			DATEADD
			(
				DAY,
				IIF(Interval.boundaryValue = DATEFROMPARTS(9999, 12, 31), 0, Interval.boundaryValueOffset),
				Interval.boundaryValue
			) AS boundaryValue,
			(
				-- Converts the sequence of dates into groups of start and end boundary dates.
				((DENSE_RANK() OVER
				(
					PARTITION BY
						Interval.customerId
					ORDER BY
						Interval.boundaryValue
				) - 1) / 2) + 1
			) AS groupingId
		FROM
			(
				SELECT
					IntervalBoundary.customerId,
					IntervalBoundary.boundaryType,
					IntervalBoundary.boundaryValue,
					IntervalBoundary.boundaryValueOffset,
					SUM(IntervalBoundary.boundaryType) OVER
					(
						PARTITION BY
							IntervalBoundary.customerId
						ORDER BY
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryType DESC
						ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
					) - IntervalBoundary.offset AS overlapCount
				FROM
					(
						SELECT
							DatePeriod.customerId,
							IntervalBoundary.boundaryType,
							IntervalBoundary.offset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							dbo.DatePeriod
							OUTER APPLY
							(VALUES
								-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
								-- For start dates, apply an offset of 1 so that a start date doesn't count against itself in the running aggregate check.
								(+1, 1, 1, DATEADD(DAY, -1, DatePeriod.startDate)),
								(-1, 0, 0, DatePeriod.endDate)
							) AS IntervalBoundary
								(boundaryType, offset, boundaryValueOffset, boundaryValue)
					) AS IntervalBoundary
			) AS Interval
		WHERE
			Interval.overlapCount = 0
	) AS IntervalGroup
GROUP BY
	IntervalGroup.customerId,
	IntervalGroup.groupingId;
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
 * Create date: 2025-09-16
 * Description: Flattens (or merges) overlapping and adjacent date periods.
 *========================================================*/
CREATE VIEW dbo.V_FlattenedDatePeriod_WithCTE
WITH SCHEMABINDING
AS
WITH IntervalBoundary AS
(
    SELECT
        DatePeriod.customerId,
        IntervalBoundary.boundaryType,
        IntervalBoundary.offset,
        IntervalBoundary.boundaryValue,
        IntervalBoundary.boundaryValueOffset
    FROM
        dbo.DatePeriod
        OUTER APPLY
        (VALUES
            -- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
            -- For start dates, apply an offset of 1 so that a start date doesn't count against itself in the running aggregate check.
            (+1, 1, 1, DATEADD(DAY, -1, DatePeriod.startDate)),
            (-1, 0, 0, DatePeriod.endDate)
        ) AS IntervalBoundary
            (boundaryType, offset, boundaryValueOffset, boundaryValue)
),
Interval AS
(
    SELECT
        IntervalBoundary.customerId,
        IntervalBoundary.boundaryType,
        IntervalBoundary.boundaryValue,
        IntervalBoundary.boundaryValueOffset,
        SUM(IntervalBoundary.boundaryType) OVER
        (
            PARTITION BY
                IntervalBoundary.customerId
            ORDER BY
                IntervalBoundary.boundaryValue,
                IntervalBoundary.boundaryType DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) - IntervalBoundary.offset AS overlapCount
    FROM IntervalBoundary
),
IntervalGroup AS
(
    SELECT
        Interval.customerId,
        -- Adjust dates using the boundaryValueOffset
        DATEADD
        (
            DAY,
            IIF(Interval.boundaryValue = DATEFROMPARTS(9999, 12, 31), 0, Interval.boundaryValueOffset),
            Interval.boundaryValue
        ) AS boundaryValue,
        (
            -- Converts the sequence of dates into groups of start and end boundary dates.
            ((DENSE_RANK() OVER
            (
                PARTITION BY
                    Interval.customerId
                ORDER BY
                    Interval.boundaryValue
            ) - 1) / 2) + 1
        ) AS groupingId
    FROM Interval
    WHERE
        Interval.overlapCount = 0
)
SELECT
	IntervalGroup.customerId,
	MIN(IntervalGroup.boundaryValue) AS startDate,
	MAX(IntervalGroup.boundaryValue) AS endDate
FROM IntervalGroup
GROUP BY
	IntervalGroup.customerId,
	IntervalGroup.groupingId;
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
 * Create date: 2025-09-16
 * Description: Flattens (or merges) overlapping and adjacent date periods.
 *========================================================*/
CREATE FUNCTION dbo.udf_FlattenDatePeriod
(
	@DatePeriod dbo.tvp_DatePeriod READONLY
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		IntervalGroup.partitionId,
		MIN(IntervalGroup.boundaryValue) AS startDate,
		MAX(IntervalGroup.boundaryValue) AS endDate
	FROM
		(
			SELECT
				Interval.partitionId,
				-- Adjust dates using the boundaryValueOffset
				DATEADD
				(
					DAY,
					IIF(Interval.boundaryValue = DATEFROMPARTS(9999, 12, 31), 0, Interval.boundaryValueOffset),
					Interval.boundaryValue
				) AS boundaryValue,
				(
					-- Converts the sequence of dates into groups of start and end boundary dates.
					((DENSE_RANK() OVER
					(
						PARTITION BY
							Interval.partitionId
						ORDER BY
							Interval.boundaryValue
					) - 1) / 2) + 1
				) AS groupingId
			FROM
				(
					SELECT
						IntervalBoundary.partitionId,
						IntervalBoundary.boundaryType,
						IntervalBoundary.boundaryValue,
						IntervalBoundary.boundaryValueOffset,
						SUM(IntervalBoundary.boundaryType) OVER
						(
							PARTITION BY
								IntervalBoundary.partitionId
							ORDER BY
								IntervalBoundary.boundaryValue,
								IntervalBoundary.boundaryType DESC
							ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
						) - IntervalBoundary.offset AS overlapCount
					FROM
						(
							SELECT
								DatePeriod.partitionId,
								IntervalBoundary.boundaryType,
								IntervalBoundary.offset,
								IntervalBoundary.boundaryValue,
								IntervalBoundary.boundaryValueOffset
							FROM
								@DatePeriod AS DatePeriod
								OUTER APPLY
								(VALUES
									-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
									-- For start dates, apply an offset of 1 so that a start date doesn't count against itself in the running aggregate check.
									(+1, 1, 1, DATEADD(DAY, -1, DatePeriod.startDate)),
									(-1, 0, 0, DatePeriod.endDate)
								) AS IntervalBoundary
									(boundaryType, offset, boundaryValueOffset, boundaryValue)
						) AS IntervalBoundary
				) AS Interval
			WHERE
				Interval.overlapCount = 0
		) AS IntervalGroup
	GROUP BY
		IntervalGroup.partitionId,
		IntervalGroup.groupingId
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

INSERT INTO dbo.DatePeriod (customerId, startDate, endDate)
VALUES
	(1, '2020-01-01', '2020-01-01'),
	(1, '2021-01-02', '2021-03-31'),
	(1, '2020-01-01', '2020-12-31'),
	(1, '2021-01-01', '2022-12-31'),
	(1, '2023-01-01', '2023-12-31');

DECLARE @DatePeriod dbo.tvp_DatePeriod;
INSERT INTO @DatePeriod (partitionId, startDate, endDate)
SELECT
	customerId,
	startDate,
	endDate
FROM dbo.DatePeriod;
	
SET STATISTICS IO,TIME ON;

SELECT
	customerId,
	startDate,
	endDate
FROM dbo.V_FlattenedDatePeriod
ORDER BY
	customerId, startDate;

SELECT
	partitionId AS customerId,
	startDate,
	endDate
FROM dbo.udf_FlattenDatePeriod (@DatePeriod)
ORDER BY
	partitionId, startDate;

SET STATISTICS IO,TIME OFF;

PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
--PRINT 'COMMIT'; COMMIT WORK;
/*

*/