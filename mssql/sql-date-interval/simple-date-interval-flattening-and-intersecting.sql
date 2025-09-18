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

CREATE TABLE dbo.OtherDatePeriod
(
    datePeriodId INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_OtherDatePeriod_datePeriodId PRIMARY KEY,
    customerId INT NOT NULL,
        -- CONSTRAINT FK_OtherDatePeriod_Customer_customerId
        --     FOREIGN KEY REFERENCES dbo.Customer(customerId),
    startDate DATE NOT NULL,
    endDate DATE NOT NULL,
    rowCreatedAtTimeUtc DATETIME2(3) GENERATED ALWAYS AS ROW START NOT NULL,
    rowUpdatedAtTimeUtc DATETIME2(3) GENERATED ALWAYS AS ROW END NOT NULL,
    PERIOD FOR SYSTEM_TIME (rowCreatedAtTimeUtc, rowUpdatedAtTimeUtc),
    CONSTRAINT CK_VL_OtherDatePeriod_ValidRange CHECK (endDate >= startDate)
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
 * Description: Finds the intersecting date periods for 2 sets of date periods,
 *              flattening/merging any overlapping or adjacent periods within each set.
 *========================================================*/
CREATE VIEW dbo.V_IntersectDatePeriod
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
						Interval.boundaryValue,
						Interval.boundaryType DESC
				) - 1) / 2) + 1
			) AS groupingId
		FROM
			(
				SELECT
					IntervalBoundary.customerId,
					IntervalBoundary.boundaryValue,
					IntervalBoundary.boundaryValueOffset,
					IntervalBoundary.boundaryType,
					IntervalBoundary.isLeft,
					SUM(IIF(IntervalBoundary.isLeft = 1, IntervalBoundary.boundaryType, 0)) OVER
                    (
                        PARTITION BY
                            IntervalBoundary.customerId
                        ORDER BY
                            IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryType DESC,
                            IntervalBoundary.isLeft
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
					) + IIF(IntervalBoundary.isLeft = 1, IntervalBoundary.offset, 0) AS leftOverlapCount,
					SUM(IIF(IntervalBoundary.isLeft = 0, IntervalBoundary.boundaryType, 0)) OVER
					(
						PARTITION BY
							IntervalBoundary.customerId
						ORDER BY
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryType DESC,
                            IntervalBoundary.isLeft
						ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
					) + IIF(IntervalBoundary.isLeft = 0, IntervalBoundary.offset, 0) AS rightOverlapCount
				FROM
					(
						SELECT
							DatePeriod.customerId,
							IntervalBoundary.boundaryType,
							IntervalBoundary.isLeft,
							IntervalBoundary.offset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							dbo.DatePeriod AS DatePeriod
							OUTER APPLY
							(VALUES
								-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
								-- For end dates, apply an offset of 1 so that an end date doesn't count against itself in the running aggregate check.
								(1, +1,  0, 1, DATEADD(DAY, -1, DatePeriod.startDate)),
								(1, -1,  1, 0, DatePeriod.endDate)
							) AS IntervalBoundary
								(isLeft, boundaryType, offset, boundaryValueOffset, boundaryValue)

						UNION ALL

						SELECT
							DatePeriod.customerId,
							IntervalBoundary.boundaryType,
							IntervalBoundary.isLeft,
							IntervalBoundary.offset,
							IntervalBoundary.boundaryValue,
							IntervalBoundary.boundaryValueOffset
						FROM
							dbo.OtherDatePeriod AS DatePeriod
							OUTER APPLY
							(VALUES
								-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
								-- For end dates, apply an offset of 1 so that an end date doesn't count against itself in the running aggregate check.
								(0, +1, 0, 1, DATEADD(DAY, -1, DatePeriod.startDate)),
								(0, -1, 1, 0, DatePeriod.endDate)
							) AS IntervalBoundary
								(isLeft, boundaryType, offset, boundaryValueOffset, boundaryValue)
					) AS IntervalBoundary
			) AS Interval
		WHERE
			(
				Interval.isLeft = 1
				AND Interval.leftOverlapCount = 1
				AND Interval.rightOverlapCount >= 1
			)
			OR
			(
				Interval.isLeft = 0
				AND Interval.leftOverlapCount >= 1
				AND Interval.rightOverlapCount = 1
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
 * Description: Finds the intersecting date periods for 2 sets of date periods,
 *              flattening/merging any overlapping or adjacent periods within each set.
 *========================================================*/
CREATE FUNCTION dbo.udf_IntersectDatePeriod
(
	@LeftDatePeriodSet dbo.tvp_DatePeriod READONLY,
    @RightDatePeriodSet dbo.tvp_DatePeriod READONLY
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
							Interval.boundaryValue,
							Interval.boundaryType DESC
					) - 1) / 2) + 1
				) AS groupingId
			FROM
				(
					SELECT
						IntervalBoundary.partitionId,
						IntervalBoundary.boundaryValue,
						IntervalBoundary.boundaryValueOffset,
						IntervalBoundary.boundaryType,
						IntervalBoundary.isLeft,
						SUM(IIF(IntervalBoundary.isLeft = 1, IntervalBoundary.boundaryType, 0)) OVER
						(
							PARTITION BY
								IntervalBoundary.partitionId
							ORDER BY
								IntervalBoundary.boundaryValue,
								IntervalBoundary.boundaryType DESC,
								IntervalBoundary.isLeft
							ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
						) + IIF(IntervalBoundary.isLeft = 1, IntervalBoundary.offset, 0) AS leftOverlapCount,
						SUM(IIF(IntervalBoundary.isLeft = 0, IntervalBoundary.boundaryType, 0)) OVER
						(
							PARTITION BY
								IntervalBoundary.partitionId
							ORDER BY
								IntervalBoundary.boundaryValue,
								IntervalBoundary.boundaryType DESC,
								IntervalBoundary.isLeft
							ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
						) + IIF(IntervalBoundary.isLeft = 0, IntervalBoundary.offset, 0) AS rightOverlapCount
					FROM
						(
							SELECT
								DatePeriod.partitionId,
								IntervalBoundary.boundaryType,
								IntervalBoundary.isLeft,
								IntervalBoundary.offset,
								IntervalBoundary.boundaryValue,
								IntervalBoundary.boundaryValueOffset
							FROM
								@LeftDatePeriodSet AS DatePeriod
								OUTER APPLY
								(VALUES
									-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
									-- For end dates, apply an offset of 1 so that an end date doesn't count against itself in the running aggregate check.
									(1, +1,  0, 1, DATEADD(DAY, -1, DatePeriod.startDate)),
									(1, -1,  1, 0, DatePeriod.endDate)
								) AS IntervalBoundary
									(isLeft, boundaryType, offset, boundaryValueOffset, boundaryValue)

							UNION ALL

							SELECT
								DatePeriod.partitionId,
								IntervalBoundary.boundaryType,
								IntervalBoundary.isLeft,
								IntervalBoundary.offset,
								IntervalBoundary.boundaryValue,
								IntervalBoundary.boundaryValueOffset
							FROM
								@RightDatePeriodSet AS DatePeriod
								OUTER APPLY
								(VALUES
									-- Shift start dates back a day in order to detect adjacent intervals, and to treat all dates the same.
									-- For end dates, apply an offset of 1 so that an end date doesn't count against itself in the running aggregate check.
									(0, +1, 0, 1, DATEADD(DAY, -1, DatePeriod.startDate)),
									(0, -1, 1, 0, DatePeriod.endDate)
								) AS IntervalBoundary
									(isLeft, boundaryType, offset, boundaryValueOffset, boundaryValue)
						) AS IntervalBoundary
				) AS Interval
			WHERE
				(
					Interval.isLeft = 1
					AND Interval.leftOverlapCount = 1
					AND Interval.rightOverlapCount >= 1
				)
				OR
				(
					Interval.isLeft = 0
					AND Interval.leftOverlapCount >= 1
					AND Interval.rightOverlapCount = 1
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
	(1, '2020-01-01', '2025-12-31'),
	(1, '2020-01-01', '2025-12-31');

DECLARE @DatePeriod dbo.tvp_DatePeriod;
INSERT INTO @DatePeriod (partitionId, startDate, endDate)
SELECT
	customerId,
	startDate,
	endDate
FROM dbo.DatePeriod;

INSERT INTO dbo.OtherDatePeriod (customerId, startDate, endDate)
VALUES
	(1, '2019-01-01', '2023-12-31'),
	(1, '2025-01-01', '2026-12-31'),
	(1, '2019-01-01', '2022-12-31'),
	(1, '2025-01-01', '2026-12-31');


DECLARE @OtherDatePeriod dbo.tvp_DatePeriod;
INSERT INTO @OtherDatePeriod (partitionId, startDate, endDate)
SELECT
	customerId,
	startDate,
	endDate
FROM dbo.OtherDatePeriod;

SET STATISTICS IO,TIME ON;

SELECT
	customerId,
	startDate,
	endDate
FROM dbo.V_IntersectDatePeriod
ORDER BY
	customerId, startDate;

SELECT
	partitionId AS customerId,
	startDate,
	endDate
FROM dbo.udf_IntersectDatePeriod (@DatePeriod, @OtherDatePeriod)
ORDER BY
	partitionId, startDate;

SET STATISTICS IO,TIME OFF;

PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
--PRINT 'COMMIT'; COMMIT WORK;
/*

*/