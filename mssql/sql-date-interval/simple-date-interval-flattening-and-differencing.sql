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

CREATE TABLE dbo.ExcludedDatePeriod
(
    datePeriodId INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_ExcludedDatePeriod_datePeriodId PRIMARY KEY,
    customerId INT NOT NULL,
        -- CONSTRAINT FK_ExcludedDatePeriod_Customer_customerId
        --     FOREIGN KEY REFERENCES dbo.Customer(customerId),
    startDate DATE NOT NULL,
    endDate DATE NOT NULL,
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
 *========================================================*/
CREATE VIEW dbo.V_DifferenceDatePeriod
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
					IntervalBoundary.boundaryValue,
					IntervalBoundary.boundaryValueOffset,
					IntervalBoundary.negativeBoundaryType,
					SUM(IntervalBoundary.boundaryType) OVER
                    (
                        PARTITION BY
                            IntervalBoundary.customerId
                        ORDER BY
                            IntervalBoundary.boundaryValue,
                            IntervalBoundary.negativeBoundaryType DESC,
                            IntervalBoundary.boundaryType DESC
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                    ) - IntervalBoundary.offset AS overlapCount,
					SUM(IntervalBoundary.negativeBoundaryType) OVER
					(
						PARTITION BY
							IntervalBoundary.customerId
						ORDER BY
							IntervalBoundary.boundaryValue,
							IntervalBoundary.negativeBoundaryType DESC,
							IntervalBoundary.boundaryType DESC
						ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
					) - IntervalBoundary.negativeOffset AS negativeOverlapCount
				FROM
					(
						SELECT
							InclusionPeriod.customerId,
							IntervalBoundary.boundaryType,
							IntervalBoundary.offset,
							IntervalBoundary.negativeBoundaryType,
							IntervalBoundary.negativeOffset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							dbo.DatePeriod AS InclusionPeriod
							OUTER APPLY
							(VALUES
								-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
								-- For positive start dates, apply an offset of 1 so that a start date doesn't count against itself in the running aggregate check.
								(+1, 1, 0, 0, 1, DATEADD(DAY, -1, InclusionPeriod.startDate)),
								(-1, 0, 0, 0, 0, InclusionPeriod.endDate)
							) AS IntervalBoundary
								(boundaryType, offset, negativeBoundaryType, negativeOffset, boundaryValueOffset, boundaryValue)

						UNION ALL

						SELECT
							ExcludedDatePeriod.customerId,
							IntervalBoundary.boundaryType,
							IntervalBoundary.offset,
							IntervalBoundary.negativeBoundaryType,
							IntervalBoundary.negativeOffset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							dbo.ExcludedDatePeriod
							OUTER APPLY
							(VALUES
								-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
								-- For negative start dates, do not apply an offset.
								(+2, +2, +1, 1, 0, DATEADD(DAY, -1, ExcludedDatePeriod.startDate)),
								(-2,  0, -1, 0, 1, ExcludedDatePeriod.endDate)
							) AS IntervalBoundary
								(boundaryType, offset, negativeBoundaryType, negativeOffset, boundaryValueOffset, boundaryValue)
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
 * Description: Flattens (or merges) overlapping and adjacent date periods,
 *              differencing out excluded date periods.
 *========================================================*/
CREATE FUNCTION dbo.udf_DifferenceDatePeriod
(
	@DatePeriod dbo.tvp_DatePeriod READONLY,
    @ExcludedDatePeriod dbo.tvp_DatePeriod READONLY
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
					IntervalBoundary.boundaryValue,
					IntervalBoundary.boundaryValueOffset,
					IntervalBoundary.negativeBoundaryType,
					SUM(IntervalBoundary.boundaryType) OVER
					(
						PARTITION BY
							IntervalBoundary.partitionId
						ORDER BY
							IntervalBoundary.boundaryValue,
							IntervalBoundary.negativeBoundaryType DESC,
							IntervalBoundary.boundaryType DESC
						ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
					) - IntervalBoundary.offset AS overlapCount,
					SUM(IntervalBoundary.negativeBoundaryType) OVER
					(
						PARTITION BY
							IntervalBoundary.partitionId
						ORDER BY
							IntervalBoundary.boundaryValue,
							IntervalBoundary.negativeBoundaryType DESC,
							IntervalBoundary.boundaryType DESC
						ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
					) - IntervalBoundary.negativeOffset AS negativeOverlapCount
				FROM
					(
						SELECT
							InclusionPeriod.partitionId,
							IntervalBoundary.boundaryType,
							IntervalBoundary.offset,
							IntervalBoundary.negativeBoundaryType,
							IntervalBoundary.negativeOffset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							@DatePeriod AS InclusionPeriod
							OUTER APPLY
							(VALUES
								-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
								-- For positive start dates, apply an offset of 1 so that a start date doesn't count against itself in the running aggregate check.
								(+1, 1, 0, 0, 1, DATEADD(DAY, -1, InclusionPeriod.startDate)),
								(-1, 0, 0, 0, 0, InclusionPeriod.endDate)
							) AS IntervalBoundary
								(boundaryType, offset, negativeBoundaryType, negativeOffset, boundaryValueOffset, boundaryValue)

						UNION ALL

						SELECT
							ExclusionPeriod.partitionId,
							IntervalBoundary.boundaryType,
							IntervalBoundary.offset,
							IntervalBoundary.negativeBoundaryType,
							IntervalBoundary.negativeOffset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							@ExcludedDatePeriod AS ExclusionPeriod
							OUTER APPLY
							(VALUES
								-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
								-- For negative start dates, do not apply an offset.
								(+2, +2, +1, 1, 0, DATEADD(DAY, -1, ExclusionPeriod.startDate)),
								(-2,  0, -1, 0, 1, ExclusionPeriod.endDate)
							) AS IntervalBoundary
								(boundaryType, offset, negativeBoundaryType, negativeOffset, boundaryValueOffset, boundaryValue)
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
	(1, '2025-01-01', '2025-12-31');

DECLARE @DatePeriod dbo.tvp_DatePeriod;
INSERT INTO @DatePeriod (partitionId, startDate, endDate)
SELECT
	customerId,
	startDate,
	endDate
FROM dbo.DatePeriod;

INSERT INTO dbo.ExcludedDatePeriod (customerId, startDate, endDate)
VALUES
	(1, '2019-01-01', '2019-12-30'),
	(1, '2020-01-01', '2020-01-01'),
	(1, '2021-01-01', '2021-03-31'),
	(1, '2023-01-01', '2023-12-31'),
	(1, '2027-01-01', '2027-12-31'),
	(1, '2022-01-01', '2022-01-31');

DECLARE @ExcludedDatePeriod dbo.tvp_DatePeriod;
INSERT INTO @ExcludedDatePeriod (partitionId, startDate, endDate)
SELECT
	customerId,
	startDate,
	endDate
FROM dbo.ExcludedDatePeriod;

SET STATISTICS IO,TIME ON;

SELECT
	customerId,
	startDate,
	endDate
FROM dbo.V_DifferenceDatePeriod
ORDER BY
	customerId, startDate;

SELECT
	partitionId AS customerId,
	startDate,
	endDate
FROM dbo.udf_DifferenceDatePeriod (@DatePeriod, @ExcludedDatePeriod)
ORDER BY
	partitionId, startDate;

SET STATISTICS IO,TIME OFF;

PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
--PRINT 'COMMIT'; COMMIT WORK;
/*

*/