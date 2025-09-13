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
https://docs.microsoft.com/en-us/sql/relational-databases/tables/creating-a-system-versioned-temporal-table?view=sql-server-2017#alter-non-temporal-table-to-be-system-versioned-temporal-table
*/

CREATE TABLE dbo.SystemVersionedTemporalTable
(
	surrogateKey INT NOT NULL
		CONSTRAINT PK_SystemVersionedTemporalTable_surrogateKey PRIMARY KEY,
	attributeA DATE NOT NULL,
	attributeB VARCHAR(100) COLLATE Latin1_General_100_CI_AS NOT NULL
);

INSERT INTO dbo.SystemVersionedTemporalTable
(
	surrogateKey,
	attributeA,
	attributeB
)
VALUES
	(1, '2019-06-20', 'Example A'),
	(2, '2019-06-20', 'Example b');

ALTER TABLE dbo.SystemVersionedTemporalTable
	ADD rowCreatedAtTimeUtc DATETIME2(2) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL
			CONSTRAINT DF_SystemVersionedTemporalTable_rowCreatedAtTimeUtc DEFAULT (SYSUTCDATETIME()),
		rowExpiredAtTimeUtc DATETIME2(2) GENERATED ALWAYS AS ROW END HIDDEN NOT NULL
			CONSTRAINT DF_SystemVersionedTemporalTable_rowExpiredAtTimeUtc DEFAULT (DATETIME2FROMPARTS(9999, 12, 31, 23, 59, 59, 99, 2)),
		PERIOD FOR SYSTEM_TIME (rowCreatedAtTimeUtc, rowExpiredAtTimeUtc),
		CONSTRAINT CK_SystemVersionedTemporalTable_VL_rowExpiredAtTimeUtc__MaxDateTime
			CHECK (rowExpiredAtTimeUtc = DATETIME2FROMPARTS(9999, 12, 31, 23, 59, 59, 99, 2)),
		CONSTRAINT CK_SystemVersionedTemporalTable_VL_rowCreatedAtTimeUtc_rowExpiredAtTimeUtc__ExpiredAfterCreated
			CHECK (rowExpiredAtTimeUtc >= rowCreatedAtTimeUtc);

ALTER TABLE dbo.SystemVersionedTemporalTable
	SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.SystemVersionedTemporalTableHistory));

CREATE NONCLUSTERED INDEX NCIX_SystemVersionedTemporalTable_rowExpiredAtTimeUtc_rowCreatedAtTimeUtc
ON dbo.SystemVersionedTemporalTable
(
	rowExpiredAtTimeUtc,
	rowCreatedAtTimeUtc
);


--PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
PRINT 'COMMIT'; COMMIT WORK;


BEGIN TRANSACTION;

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
	attributeA,
	attributeB
)
VALUES
	(1, '2019-06-21', 'Example A'),
	(2, '2019-06-21', 'Example B');


SELECT * FROM dbo.SystemVersionedTemporalTableHistory;

SELECT * FROM dbo.SystemVersionedTemporalTable;
SELECT *, rowCreatedAtTimeUtc, rowCreatedAtTimeUtc FROM dbo.SystemVersionedTemporalTable;

SELECT *
FROM dbo.SystemVersionedTemporalTable FOR SYSTEM_TIME AS OF @systemTimeUtc;



ALTER TABLE dbo.SystemVersionedTemporalTable SET (SYSTEM_VERSIONING = OFF);
DROP TABLE IF EXISTS dbo.SystemVersionedTemporalTable;
DROP TABLE IF EXISTS dbo.SystemVersionedTemporalTableHistory;

--PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
PRINT 'COMMIT'; COMMIT WORK;
/*

*/