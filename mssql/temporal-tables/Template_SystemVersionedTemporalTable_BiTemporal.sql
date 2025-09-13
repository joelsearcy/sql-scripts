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

/*
https://docs.microsoft.com/en-us/sql/relational-databases/tables/creating-a-system-versioned-temporal-table?view=sql-server-2017#creating-a-temporal-table-with-a-user-defined-history-table
*/

--ALTER TABLE dbo.SystemVersionedTemporalTable SET (SYSTEM_VERSIONING = OFF);
--DROP TABLE IF EXISTS dbo.SystemVersionedTemporalTable;
--DROP TABLE IF EXISTS dbo.SystemVersionedTemporalTableHistory;

CREATE TABLE dbo.SystemVersionedTemporalTable
(
	surrogateKey INT NOT NULL,
	startDate DATE NOT NULL,
	endDate DATE NOT NULL,
	attributeA DATE NOT NULL,
	attributeB VARCHAR(100) COLLATE Latin1_General_100_CI_AS NOT NULL,
	rowCreatedAtTimeUtc DATETIME2(2) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
	rowExpiredAtTimeUtc DATETIME2(2) GENERATED ALWAYS AS ROW END HIDDEN NOT NULL,
	PERIOD FOR SYSTEM_TIME (rowCreatedAtTimeUtc, rowExpiredAtTimeUtc),
	CONSTRAINT CK_SystemVersionedTemporalTable_VLrowExpiredAtTimeUtc__MaxDateTime
		CHECK (rowExpiredAtTimeUtc = DATETIME2FROMPARTS(9999, 12, 31, 23, 59, 59, 99, 2)),
	CONSTRAINT CK_SystemVersionedTemporalTable_VL_startDate_endDate__EndAfterStart
		CHECK (endDate >= startDate),
	CONSTRAINT CK_SystemVersionedTemporalTable_VL_rowCreatedAtTimeUtc_rowExpiredAtTimeUtc__ExpiredAfterCreated
		CHECK (rowExpiredAtTimeUtc >= rowCreatedAtTimeUtc),
	INDEX NCIX_SystemVersionedTemporalTable_rowExpiredAtTimeUtc_rowCreatedAtTimeUtc (rowExpiredAtTimeUtc, rowCreatedAtTimeUtc),
	CONSTRAINT PK_SystemVersionedTemporalTable_surrogateKey_startDate
		PRIMARY KEY (surrogateKey, startDate),
	INDEX NCIX_SystemVersionedTemporalTable_endDate_startDate_surrogateKey (endDate, startDate, surrogateKey),
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.SystemVersionedTemporalTableHistory));

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO
--============================================================================
-- Author:		Author
-- Creation on:	YYYY-MM-DD
-- Work Items:	TW-TBD
-- Description:	Enforces bi-temporal contiguousness.
-- ===========================================================================
CREATE TRIGGER dbo.TR_SystemVersionedTemporalTable_IUD_BiTemporalContiguousness
ON dbo.SystemVersionedTemporalTable
AFTER UPDATE, DELETE
AS
BEGIN;
	SET NOCOUNT ON;

	IF EXISTS
	(
		SELECT NULL
		FROM
			(
				SELECT
					SystemVersionedTemporalTable.surrogateKey,
					SystemVersionedTemporalTable.startDate,
					SystemVersionedTemporalTable.endDate,
					LEAD(SystemVersionedTemporalTable.startDate) OVER
					(
						PARTITION BY
							SystemVersionedTemporalTable.surrogateKey
						ORDER BY
							SystemVersionedTemporalTable.startDate
					) AS nextStartDate
				FROM dbo.SystemVersionedTemporalTable
			) AS ContiguousnessCheck
		WHERE
			ContiguousnessCheck.endDate <> DATEADD(DAY, -1, ContiguousnessCheck.nextStartDate)
	)
	BEGIN;
		THROW 50000, N'No overlap or gap periods are allow.', 1;
	END;
END;
GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

INSERT INTO dbo.SystemVersionedTemporalTable
(
	surrogateKey,
	startDate,
	endDate,
	attributeA,
	attributeB
)
VALUES
	(1, '2019-01-01', '2020-12-31', '2019-06-20', 'Example A'),
	(1, '2021-01-01', '9999-12-31', '2019-06-20', 'Example A.a'),
	(2, '2019-01-01', '9999-12-31', '2019-06-20', 'Example b');

WAITFOR DELAY '00:00:00.01';

UPDATE dbo.SystemVersionedTemporalTable
SET
	attributeA = DATEADD(DAY, -1, SystemVersionedTemporalTable.attributeA);

DECLARE @systemTimeUtc DATETIME2(2) = SYSUTCDATETIME();

UPDATE dbo.SystemVersionedTemporalTable
SET
	attributeB = 'Example B'
WHERE
	SystemVersionedTemporalTable.surrogateKey = 2;

WAITFOR DELAY '00:00:00.01';

DELETE FROM dbo.SystemVersionedTemporalTable;

WAITFOR DELAY '00:00:00.01';

INSERT INTO dbo.SystemVersionedTemporalTable
(
	surrogateKey,
	startDate,
	endDate,
	attributeA,
	attributeB
)
VALUES
	(1, '2019-01-01', '2020-12-31', '2019-06-20', 'Example A'),
	(1, '2020-01-01', '9999-12-31', '2019-06-20', 'Example A.a'),
	(2, '2019-01-01', '9999-12-31', '2019-06-20', 'Example B');


SELECT * FROM dbo.SystemVersionedTemporalTableHistory;

SELECT * FROM dbo.SystemVersionedTemporalTable;
SELECT *, rowCreatedAtTimeUtc, rowCreatedAtTimeUtc FROM dbo.SystemVersionedTemporalTable;


SELECT *, rowCreatedAtTimeUtc, rowCreatedAtTimeUtc
FROM dbo.SystemVersionedTemporalTable FOR SYSTEM_TIME ALL;

SELECT *, rowCreatedAtTimeUtc, rowCreatedAtTimeUtc
FROM dbo.SystemVersionedTemporalTable FOR SYSTEM_TIME AS OF @systemTimeUtc;

PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
--PRINT 'COMMIT'; COMMIT WORK;
/*

*/