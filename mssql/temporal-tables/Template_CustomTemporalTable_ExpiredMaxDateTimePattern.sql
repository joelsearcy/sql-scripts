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

CREATE TABLE dbo.CustomTemporalTable
(
	customTemporalTableId INT IDENTITY(1,1) NOT NULL
		CONSTRAINT PK_CustomTemporalTable_customTemporalTableId PRIMARY KEY,
	surrogateKey INT NOT NULL,
	attributeA DATE NOT NULL,
	attributeB VARCHAR(100) COLLATE Latin1_General_100_CI_AS NOT NULL,
	rowCreatedAtTimeUtc DATETIME2(2) NOT NULL
		CONSTRAINT DF_CustomTemporalTable_rowCreatedAtTimeUtc DEFAULT (SYSUTCDATETIME()),
	rowExpiredAtTimeUtc DATETIME2(2) NOT NULL
		CONSTRAINT DF_CustomTemporalTable_rowExpiredAtTimeUtc DEFAULT (DATETIME2FROMPARTS(9999, 12, 31, 23, 59, 59, 99, 2)),
		CONSTRAINT CK_CustomTemporalTable_VL_rowCreatedAtTimeUtc_rowExpiredAtTimeUtc__ExpiredAfterCreated
			CHECK (rowExpiredAtTimeUtc >= rowCreatedAtTimeUtc),
	INDEX NCIX_CustomTemporalTable_rowExpiredAtTimeUtc_rowCreatedAtTimeUtc (rowExpiredAtTimeUtc, rowCreatedAtTimeUtc)
);

CREATE UNIQUE NONCLUSTERED INDEX FUC_CustomTemporalTable_surrogateKey__ActiveOnly
ON dbo.CustomTemporalTable
(
	surrogateKey
)
WHERE (rowExpiredAtTimeUtc = CAST('9999-12-31 23:59:59.99' AS DATETIME2(2)));

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
-- Description:	Enforces temporal immutability.
-- ===========================================================================
CREATE TRIGGER dbo.TR_CustomTemporalTable_UD_TemporalImmutability
ON dbo.CustomTemporalTable
AFTER UPDATE, DELETE
AS
BEGIN;
	SET NOCOUNT ON;

	/* Check for deletes */
	IF
	(
		NOT EXISTS (SELECT NULL FROM inserted)
		AND EXISTS (SELECT NULL FROM deleted)
	)
	BEGIN;
		THROW 50000, N'Deleting temporal history is not allowed.', 1;
	END;

	/* Verify that the only rowExpiredAtTimeUtc is being updated. */
	IF
	(
		/* Check every column on the table, other than rowExpiredAtTimeUtc. */
		UPDATE(customTemporalTableId)
		OR UPDATE(surrogateKey)
		OR UPDATE(attributeA)
		OR UPDATE(attributeB)
		OR UPDATE(rowCreatedAtTimeUtc)
	)
	BEGIN;
		THROW 50000, N'Updating temporal history is not allowed.', 1;
	END;

	/* Verify that rowExpiredAtTimeUtc is only going from NULL to non-NULL. */
	IF EXISTS
	(
		SELECT NULL
		FROM deleted
		WHERE
			deleted.rowExpiredAtTimeUtc <> DATETIME2FROMPARTS(9999, 12, 31, 23, 59, 59, 99, 2)

		UNION ALL

		SELECT NULL
		FROM inserted
		WHERE
			inserted.rowExpiredAtTimeUtc = DATETIME2FROMPARTS(9999, 12, 31, 23, 59, 59, 99, 2)
	)
	BEGIN;
		THROW 50000, N'Updating temporal history is not allowed.', 1;
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
--============================================================================
-- Author:		Author
-- Creation on:	YYYY-MM-DD
-- Work Items:	TW-TBD
-- Description:	Temporally current data.
-- ===========================================================================
CREATE VIEW dbo.V_ActiveCustomTemporalTable
WITH SCHEMABINDING
AS
(
	SELECT
		CustomTemporalTable.customTemporalTableId,
		CustomTemporalTable.surrogateKey,
		CustomTemporalTable.attributeA,
		CustomTemporalTable.attributeB
	FROM dbo.CustomTemporalTable
	WHERE
		CustomTemporalTable.rowExpiredAtTimeUtc = DATETIME2FROMPARTS(9999, 12, 31, 23, 59, 59, 99, 2)
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

--============================================================================
-- Author:		Author
-- Creation on:	YYYY-MM-DD
-- Work Items:	TW-TBD
-- Description:	Handles temporal history tracking.
-- ===========================================================================
CREATE TRIGGER dbo.TR_V_ActiveCustomTemporalTable_IUD_TemporalHistoryTracking
ON dbo.V_ActiveCustomTemporalTable
INSTEAD OF INSERT, UPDATE, DELETE
AS
BEGIN;
	SET NOCOUNT ON;
	
	DECLARE @nowUtc DATETIME2(2) = SYSUTCDATETIME();

	UPDATE dbo.CustomTemporalTable
	SET
		rowExpiredAtTimeUtc = @nowUtc
	FROM
		dbo.CustomTemporalTable
		INNER JOIN deleted
			ON CustomTemporalTable.customTemporalTableId = deleted.customTemporalTableId
	WHERE
		CustomTemporalTable.rowExpiredAtTimeUtc = DATETIME2FROMPARTS(9999, 12, 31, 23, 59, 59, 99, 2);

	INSERT INTO dbo.CustomTemporalTable
	(
		surrogateKey,
		attributeA,
		attributeB,
		rowCreatedAtTimeUtc
	)
	SELECT
		inserted.surrogateKey,
		inserted.attributeA,
		inserted.attributeB,
		@nowUtc
	FROM inserted;
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

INSERT INTO dbo.V_ActiveCustomTemporalTable
(
	surrogateKey,
	attributeA,
	attributeB
)
VALUES
	(1, '2019-06-20', 'Example A'),
	(2, '2019-06-20', 'Example b');

WAITFOR DELAY '00:00:00.01';

UPDATE dbo.V_ActiveCustomTemporalTable
SET
	attributeA = DATEADD(DAY, -1, V_ActiveCustomTemporalTable.attributeA);

DECLARE @systemTimeUtc DATETIME2(2) = SYSUTCDATETIME();

UPDATE dbo.V_ActiveCustomTemporalTable
SET
	attributeB = 'Example B'
WHERE
	V_ActiveCustomTemporalTable.surrogateKey = 2;

WAITFOR DELAY '00:00:00.01';

DELETE FROM dbo.V_ActiveCustomTemporalTable;

WAITFOR DELAY '00:00:00.01';

INSERT INTO dbo.V_ActiveCustomTemporalTable
(
	surrogateKey,
	attributeA,
	attributeB
)
VALUES
	(1, '2019-06-21', 'Example A'),
	(2, '2019-06-21', 'Example B');


SELECT * FROM dbo.V_ActiveCustomTemporalTable;

SELECT * FROM dbo.CustomTemporalTable;

SELECT *
FROM dbo.CustomTemporalTable
WHERE
	CustomTemporalTable.rowCreatedAtTimeUtc <= @systemTimeUtc
	AND CustomTemporalTable.rowExpiredAtTimeUtc > @systemTimeUtc;

PRINT 'ROLLBACK'; ROLLBACK TRANSACTION;
--PRINT 'COMMIT'; COMMIT WORK;
/*

*/