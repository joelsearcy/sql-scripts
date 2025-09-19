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

IF (TYPE_ID('dbo.tvp_DatePeriodWithDateReason') IS NULL)
BEGIN
	-- This is outside of the transaction because creating the type inside the same transaction as a referencing object results in a deadlock.
	-- Feel free to move this inside the transaction if you want to see the deadlock happen. :)
	CREATE TYPE dbo.tvp_DatePeriodWithDateReason AS TABLE
	(
		partitionId INT NOT NULL,
		startDate DATE NOT NULL,
		endDate DATE NOT NULL,
		dateReasonId TINYINT NOT NULL
	);

	GRANT EXECUTE ON TYPE::dbo.tvp_DatePeriodWithDateReason TO [public];
END;

BEGIN TRANSACTION

CREATE TABLE dbo.DateReason
(
    dateReasonId TINYINT NOT NULL
        CONSTRAINT PK_DateReason_dateReasonId PRIMARY KEY,
    dateReasonName NVARCHAR(100) NOT NULL
        CONSTRAINT UC_DateReason_dateReasonName UNIQUE,
    precedenceOrder TINYINT NOT NULL
        CONSTRAINT UC_DateReason_precedenceOrder UNIQUE
);

INSERT INTO dbo.DateReason (dateReasonId, dateReasonName, precedenceOrder)
VALUES
    (1, 'Death', 1),
    (2, 'Divorice', 2),
    (3, 'Loss of Eligibility', 3),
	(4, 'Planned end', 4),
    (10, 'Disqualified', 5),
    (11, 'Manual Exclusion', 6),
    (99, 'Open-ended', 99);

CREATE TABLE dbo.DatePeriod
(
    datePeriodId INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_DatePeriod_datePeriodId PRIMARY KEY,
    customerId INT NOT NULL,
        -- CONSTRAINT FK_DatePeriod_Customer_customerId
        --     FOREIGN KEY REFERENCES dbo.Customer(customerId),
    startDate DATE NOT NULL,
    endDate DATE NOT NULL,
    endDateReasonId TINYINT NOT NULL
        CONSTRAINT FK_DatePeriod_DateReason_endDateReasonId
            FOREIGN KEY REFERENCES dbo.DateReason(dateReasonId),
    rowCreatedAtTimeUtc DATETIME2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    rowUpdatedAtTimeUtc DATETIME2(3) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (rowCreatedAtTimeUtc, rowUpdatedAtTimeUtc),
    CONSTRAINT CK_VL_DatePeriod_ValidRange CHECK (endDate >= startDate)
);

CREATE TABLE dbo.ExcludedDatePeriod
(
    datePeriodId INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_ExcludedDatePeriod_datePeriodId PRIMARY KEY,
    customerId INT NOT NULL,
        -- CONSTRAINT FK_ExcludedDatePeriod_Customer_customerId
        --     FOREIGN KEY REFERENCES dbo.Customer(customerId),
    startDate DATE NOT NULL,
    endDate DATE NOT NULL,
    exclusionReasonId TINYINT NOT NULL
        CONSTRAINT FK_ExcludedDatePeriod_DateReason_exclusionReasonId
            FOREIGN KEY REFERENCES dbo.DateReason(dateReasonId),
    rowCreatedAtTimeUtc DATETIME2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    rowUpdatedAtTimeUtc DATETIME2(3) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (rowCreatedAtTimeUtc, rowUpdatedAtTimeUtc),
    CONSTRAINT CK_VL_ExcludedDatePeriod_ValidRange CHECK (endDate >= startDate)
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
 * Description: Flattens (or merges) overlapping and adjacent date periods,
 *              differencing out excluded date periods.
 *              Keeps the endDateReasonId from the original DatePeriod table,
 *              choosing the highest precedence endDateReasonId when multiple
 *              end reasons apply to the same flattened date period.
 *========================================================*/
CREATE VIEW dbo.V_DifferenceDatePeriod_WithDateReason
WITH SCHEMABINDING
AS
SELECT
	IntervalGroup.customerId,
	IntervalGroup.startDate,
	IntervalGroup.endDate,
    IntervalGroup.endDateReasonId,
	IntervalGroup.dateReasonPrecedenceOrder
FROM
	(
		SELECT
			Interval.customerId,
            Interval.endDateReasonId,
            Interval.dateReasonPrecedenceOrder,
			-- Adjust dates using the boundaryValueOffset
			-- Pulls the start date forward to pair with the end date.
            LAG
            (
                DATEADD
                (
                    DAY,
                    IIF(Interval.boundaryValue = DATEFROMPARTS(9999, 12, 31), 0, Interval.boundaryValueOffset),
                    Interval.boundaryValue
                )
            ) OVER
                (
                    PARTITION BY
                        Interval.customerId
                    ORDER BY
                        Interval.boundaryValue,
						Interval.negativeBoundaryType
                ) AS startDate,
			DATEADD
			(
				DAY,
				IIF(Interval.boundaryValue = DATEFROMPARTS(9999, 12, 31), 0, Interval.boundaryValueOffset),
				Interval.boundaryValue
			) AS endDate,
			(
				-- Converts the sequence of dates into groups of start and end boundary dates.
				((DENSE_RANK() OVER
				(
					PARTITION BY
						Interval.customerId
					ORDER BY
						Interval.boundaryValue,
						Interval.negativeBoundaryType
				) - 1) % 2) + 1
			) AS groupingId
		FROM
			(
				SELECT
					IntervalBoundary.customerId,
                    IntervalBoundary.endDateReasonId,
                    IntervalBoundary.dateReasonPrecedenceOrder,
					IntervalBoundary.boundaryValue,
					IntervalBoundary.boundaryValueOffset,
					IntervalBoundary.negativeBoundaryType,
					SUM(IntervalBoundary.boundaryType) OVER
                    (
                        PARTITION BY
                            IntervalBoundary.customerId
                        ORDER BY
                            IntervalBoundary.boundaryValue,
                            IntervalBoundary.negativeBoundaryType,
                            IntervalBoundary.boundaryType DESC,
							IntervalBoundary.dateReasonPrecedenceOrder
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                    ) - IntervalBoundary.offset AS overlapCount,
					SUM(IntervalBoundary.negativeBoundaryType) OVER
					(
						PARTITION BY
							IntervalBoundary.customerId
						ORDER BY
							IntervalBoundary.boundaryValue,
							IntervalBoundary.negativeBoundaryType,
							IntervalBoundary.boundaryType DESC,
							IntervalBoundary.dateReasonPrecedenceOrder
						ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
					) - IntervalBoundary.negativeOffset AS negativeOverlapCount
				FROM
					(
						SELECT
							DatePeriod.customerId,
							DatePeriod.endDateReasonId,
                            IntervalBoundary.dateReasonPrecedenceOrder,
							IntervalBoundary.boundaryType,
							IntervalBoundary.offset,
							IntervalBoundary.negativeBoundaryType,
							IntervalBoundary.negativeOffset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							dbo.DatePeriod AS DatePeriod
                            INNER JOIN dbo.DateReason
                                ON DatePeriod.endDateReasonId = DateReason.dateReasonId
							OUTER APPLY
							(VALUES
								-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
								-- For positive start dates, apply an offset of 1 so that a start date doesn't count against itself in the running aggregate check.
								(+1, 1, 0, 0, 1, DATEADD(DAY, -1, DatePeriod.startDate), 0),
								(-1, 0, 0, 0, 0, DatePeriod.endDate, DateReason.precedenceOrder)
							) AS IntervalBoundary
								(boundaryType, offset, negativeBoundaryType, negativeOffset, boundaryValueOffset, boundaryValue, dateReasonPrecedenceOrder)
                            

						UNION ALL

						SELECT
							DatePeriod.customerId,
							DatePeriod.exclusionReasonId AS endDateReasonId,
                            IntervalBoundary.dateReasonPrecedenceOrder,
							IntervalBoundary.boundaryType,
							IntervalBoundary.offset,
							IntervalBoundary.negativeBoundaryType,
							IntervalBoundary.negativeOffset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							dbo.ExcludedDatePeriod AS DatePeriod
                            INNER JOIN dbo.DateReason
                                ON DatePeriod.exclusionReasonId = DateReason.dateReasonId
							OUTER APPLY
							(VALUES
								-- For excluded intervals, leave the start date as-is to avoid conflicts with inclusion end dates.
								-- Instead, shift the end date forward a day to detect adjacent intervals.
								-- In the final output, the start date will be adjusted to an end date.
								(+2, +2, +1, 1, -1, DatePeriod.startDate, DateReason.precedenceOrder),
								(-2,  0, -1, 0,  0, DATEADD(DAY, IIF(DATEFROMPARTS(9999, 12, 31) = DatePeriod.endDate, 0, 1), DatePeriod.endDate), 0)
							) AS IntervalBoundary
								(boundaryType, offset, negativeBoundaryType, negativeOffset, boundaryValueOffset, boundaryValue, dateReasonPrecedenceOrder)
					) AS IntervalBoundary
			) AS Interval
		WHERE
			(
				-- Any positive value that has no overlap with another interval is a true boundary value.
				ABS(Interval.negativeBoundaryType) = 0
				AND Interval.overlapCount = 0
				AND Interval.negativeOverlapCount = 0
			)
			OR
			(
				-- Any negative value that has no overlap with another negative interval, but does overlap with a positive interval, is a true boundary value.
				ABS(Interval.negativeBoundaryType) = 1
				AND Interval.overlapCount > 0
				AND Interval.negativeOverlapCount = 0
			)
	) AS IntervalGroup
WHERE
    IntervalGroup.groupingId = 2 /* ends a grouping pair */
	-- safety filter
	AND IntervalGroup.startDate <= IntervalGroup.endDate;
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
 * Description: Flattens (or merges) overlapping and adjacent date periods,
 *              differencing out excluded date periods.
 *              Keeps the endDateReasonId from the original DatePeriod table,
 *              choosing the highest precedence endDateReasonId when multiple
 *              end reasons apply to the same flattened date period.
 *========================================================*/
CREATE FUNCTION dbo.udf_DifferenceDatePeriod_WithDateReason
(
	@DatePeriod dbo.tvp_DatePeriodWithDateReason READONLY,
    @ExcludedDatePeriod dbo.tvp_DatePeriodWithDateReason READONLY
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
	SELECT
		IntervalGroup.partitionId,
		IntervalGroup.startDate,
		IntervalGroup.endDate,
		IntervalGroup.endDateReasonId,
		IntervalGroup.dateReasonPrecedenceOrder
	FROM
		(
			SELECT
				Interval.partitionId,
				Interval.endDateReasonId,
				Interval.dateReasonPrecedenceOrder,
				-- Adjust dates using the boundaryValueOffset
				-- Pulls the start date forward to pair with the end date.
				LAG
				(
					DATEADD
					(
						DAY,
						IIF(Interval.boundaryValue = DATEFROMPARTS(9999, 12, 31), 0, Interval.boundaryValueOffset),
						Interval.boundaryValue
					)
				) OVER
					(
						PARTITION BY
							Interval.partitionId
						ORDER BY
							Interval.boundaryValue,
							Interval.negativeBoundaryType
					) AS startDate,
				DATEADD
				(
					DAY,
					IIF(Interval.boundaryValue = DATEFROMPARTS(9999, 12, 31), 0, Interval.boundaryValueOffset),
					Interval.boundaryValue
				) AS endDate,
				(
					-- Converts the sequence of dates into groups of start and end boundary dates.
					((DENSE_RANK() OVER
					(
						PARTITION BY
							Interval.partitionId
						ORDER BY
							Interval.boundaryValue,
							Interval.negativeBoundaryType
					) - 1) % 2) + 1
				) AS groupingId
			FROM
				(
					SELECT
						IntervalBoundary.partitionId,
						IntervalBoundary.endDateReasonId,
						IntervalBoundary.dateReasonPrecedenceOrder,
						IntervalBoundary.boundaryValue,
						IntervalBoundary.boundaryValueOffset,
						IntervalBoundary.negativeBoundaryType,
						SUM(IntervalBoundary.boundaryType) OVER
						(
							PARTITION BY
								IntervalBoundary.partitionId
							ORDER BY
								IntervalBoundary.boundaryValue,
								IntervalBoundary.negativeBoundaryType,
								IntervalBoundary.boundaryType DESC,
								IntervalBoundary.dateReasonPrecedenceOrder
							ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
						) - IntervalBoundary.offset AS overlapCount,
						SUM(IntervalBoundary.negativeBoundaryType) OVER
						(
							PARTITION BY
								IntervalBoundary.partitionId
							ORDER BY
								IntervalBoundary.boundaryValue,
								IntervalBoundary.negativeBoundaryType,
								IntervalBoundary.boundaryType DESC,
								IntervalBoundary.dateReasonPrecedenceOrder
							ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
						) - IntervalBoundary.negativeOffset AS negativeOverlapCount
					FROM
						(
							SELECT
								DatePeriod.partitionId,
								DatePeriod.dateReasonId AS endDateReasonId,
								IntervalBoundary.dateReasonPrecedenceOrder,
								IntervalBoundary.boundaryType,
								IntervalBoundary.offset,
								IntervalBoundary.negativeBoundaryType,
								IntervalBoundary.negativeOffset,
								IntervalBoundary.boundaryValue,
								IntervalBoundary.boundaryValueOffset
							FROM
								@DatePeriod AS DatePeriod
								INNER JOIN dbo.DateReason
									ON DatePeriod.dateReasonId = DateReason.dateReasonId
								OUTER APPLY
								(VALUES
									-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
									-- For positive start dates, apply an offset of 1 so that a start date doesn't count against itself in the running aggregate check.
									(+1, 1, 0, 0, 1, DATEADD(DAY, -1, DatePeriod.startDate), 0),
									(-1, 0, 0, 0, 0, DatePeriod.endDate, DateReason.precedenceOrder)
								) AS IntervalBoundary
									(boundaryType, offset, negativeBoundaryType, negativeOffset, boundaryValueOffset, boundaryValue, dateReasonPrecedenceOrder)
                            

							UNION ALL

							SELECT
								DatePeriod.partitionId,
								DatePeriod.dateReasonId AS endDateReasonId,
								IntervalBoundary.dateReasonPrecedenceOrder,
								IntervalBoundary.boundaryType,
								IntervalBoundary.offset,
								IntervalBoundary.negativeBoundaryType,
								IntervalBoundary.negativeOffset,
								IntervalBoundary.boundaryValue,
								IntervalBoundary.boundaryValueOffset
							FROM
								@ExcludedDatePeriod AS DatePeriod
								INNER JOIN dbo.DateReason
									ON DatePeriod.dateReasonId = DateReason.dateReasonId
								OUTER APPLY
								(VALUES
									-- For excluded intervals, leave the start date as-is to avoid conflicts with inclusion end dates.
									-- Instead, shift the end date forward a day to detect adjacent intervals.
									-- In the final output, the start date will be adjusted to an end date.
									(+2, +2, +1, 1, -1, DatePeriod.startDate, DateReason.precedenceOrder),
									(-2,  0, -1, 0,  0, DATEADD(DAY, IIF(DATEFROMPARTS(9999, 12, 31) = DatePeriod.endDate, 0, 1), DatePeriod.endDate), 0)
								) AS IntervalBoundary
									(boundaryType, offset, negativeBoundaryType, negativeOffset, boundaryValueOffset, boundaryValue, dateReasonPrecedenceOrder)
						) AS IntervalBoundary
				) AS Interval
			WHERE
				(
					-- Any positive value that has no overlap with another interval is a true boundary value.
					ABS(Interval.negativeBoundaryType) = 0
					AND Interval.overlapCount = 0
					AND Interval.negativeOverlapCount = 0
				)
				OR
				(
					-- Any negative value that has no overlap with another negative interval, but does overlap with a positive interval, is a true boundary value.
					ABS(Interval.negativeBoundaryType) = 1
					AND Interval.overlapCount > 0
					AND Interval.negativeOverlapCount = 0
				)
		) AS IntervalGroup
	WHERE
		IntervalGroup.groupingId = 2 /* ends a grouping pair */
		-- safety filter
		AND IntervalGroup.startDate <= IntervalGroup.endDate
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

INSERT INTO dbo.DatePeriod (customerId, startDate, endDate, endDateReasonId)
VALUES
	(1, '2020-01-01', '2020-03-31', 4),
	(1, '2020-04-01', '2020-05-31', 4),
	(1, '2021-06-01', '2023-12-31', 3),
	(1, '2024-07-01', '2025-07-30', 4),
	(1, '2027-01-01', '2027-12-31', 1),
	(2, '2020-01-01', '2020-01-01', 1);

DECLARE @DatePeriod dbo.tvp_DatePeriodWithDateReason;
INSERT INTO @DatePeriod (partitionId, startDate, endDate, dateReasonId)
SELECT
	customerId,
	startDate,
	endDate,
    endDateReasonId
FROM dbo.DatePeriod;

INSERT INTO dbo.ExcludedDatePeriod (customerId, startDate, endDate, exclusionReasonId)
VALUES
	(1, '2019-01-01', '2019-12-31', 10),
	(1, '2020-02-01', '2020-03-31', 10),
	(1, '2020-06-01', '2020-08-31', 10),
	(1, '2024-01-01', '2024-12-31', 10),
	(1, '2025-01-01', '2025-12-31', 10),
	(1, '2026-01-01', '2026-12-31', 11),
	(1, '2028-01-01', '2030-12-31', 10),
	(2, '2019-01-01', '2019-12-31', 11);

DECLARE @ExcludedDatePeriod dbo.tvp_DatePeriodWithDateReason;
INSERT INTO @ExcludedDatePeriod (partitionId, startDate, endDate, dateReasonId)
SELECT
	customerId,
	startDate,
	endDate,
    exclusionReasonId
FROM dbo.ExcludedDatePeriod;

SET STATISTICS IO,TIME ON;

SELECT
	DatePeriod.customerId,
	DatePeriod.startDate,
	DatePeriod.endDate,
    DatePeriod.endDateReasonId,
    DateReason.dateReasonName,
    DateReason.precedenceOrder
FROM
	dbo.V_DifferenceDatePeriod_WithDateReason AS DatePeriod
	LEFT OUTER JOIN dbo.DateReason
		ON DatePeriod.endDateReasonId = DateReason.dateReasonId
ORDER BY
	DatePeriod.customerId,
	DatePeriod.startDate;

SELECT
	DatePeriod.partitionId AS customerId,
	DatePeriod.startDate,
	DatePeriod.endDate,
    DatePeriod.endDateReasonId,
    DateReason.dateReasonName,
    DateReason.precedenceOrder
FROM
	dbo.udf_DifferenceDatePeriod_WithDateReason (@DatePeriod, @ExcludedDatePeriod) AS DatePeriod
	LEFT OUTER JOIN dbo.DateReason
		ON DatePeriod.endDateReasonId = DateReason.dateReasonId
ORDER BY
	DatePeriod.partitionId,
	DatePeriod.startDate;

SET STATISTICS IO,TIME OFF;

PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
--PRINT 'COMMIT'; COMMIT WORK;
/*

*/
