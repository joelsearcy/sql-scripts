-- Installation Script for Original ToggleSchemabinding Procedures
-- SQL Server 2019/2022/2025 Compatible Version - Includes Both Procedures
-- Removes complex transaction handling that caused installation issues

USE SchemaBindingTestDB;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Create DBA schema if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'DBA')
BEGIN
    EXEC('CREATE SCHEMA DBA AUTHORIZATION dbo');
    PRINT 'DBA schema created successfully.';
END
ELSE
BEGIN
    PRINT 'DBA schema already exists.';
END
GO

-- Drop existing procedures if they exist
IF OBJECT_ID('DBA.hsp_ToggleSchemaBinding', 'P') IS NOT NULL
    DROP PROCEDURE DBA.hsp_ToggleSchemaBinding;
GO

IF OBJECT_ID('DBA.hsp_ToggleSchemaBindingBatch', 'P') IS NOT NULL
    DROP PROCEDURE DBA.hsp_ToggleSchemaBindingBatch;
GO

PRINT 'Installing DBA.hsp_ToggleSchemaBinding (Original Version)...';
GO

-- Original core procedure with simplified transaction handling
CREATE PROCEDURE DBA.hsp_ToggleSchemaBinding
(
	@objectName SYSNAME,
	@newIsSchemaBound BIT = NULL,
	@enforceStrictChanges BIT = 0,
	@ifDebug BIT = 0
)
AS
BEGIN
	SET NOCOUNT ON;

	BEGIN TRY;
		-- Simplified transaction check
		DECLARE @localTransaction BIT = 0;
		IF (@@TRANCOUNT <= 0)
		BEGIN;
			BEGIN TRANSACTION;
			SET @localTransaction = 1;
		END;

		DECLARE @objectId INT = OBJECT_ID(@objectName);
		DECLARE @type CHAR(2) = NULL;
		DECLARE @definition NVARCHAR(MAX) = NULL;
		DECLARE @isSchemaBound BIT = NULL;
		DECLARE @searchString NVARCHAR(100) = NULL;
		DECLARE @header NVARCHAR(MAX) = NULL;
		DECLARE @offset INT = 0;
		DECLARE @newlineCharacter NVARCHAR(2) = CAST(0x0D000A00 AS NVARCHAR(2)); -- CR:0D NL:0A

		IF (@objectId IS NULL)
		BEGIN;
			RAISERROR(N'No object found with name ''%s''.', 16, 1, @objectName);
			RETURN;
		END;

		/* Get the object's type. */
		SELECT
			@type = objects.[type]
		FROM sys.objects
		WHERE
			objects.object_id = @objectId;

		IF (@type NOT IN ('FN','TF','IF','V'))
		BEGIN;
			RAISERROR(N'Object type ''%s'' is not supported (''FN'',''TF'',''IF'',''V'').', 16, 1, @type);
			RETURN;
		END;

		SET @searchString =
			(
				N'%CREATE ' +
				(
					CASE
						WHEN @type IN ('FN','TF','IF')
							THEN 'FUNCTION%'
						WHEN @type = 'V'
							THEN N'VIEW%'
						ELSE N'%'
					END
				)
			);

		/* Attempt to retrieve definition and schema binding status. */
		SELECT
			@definition = sql_modules.[definition],
			@isSchemaBound = sql_modules.is_schema_bound,
			/* Detect whether the current line ending is either one character or two characters. */
			@newlineCharacter = IIF(CHARINDEX(CAST(0x0D000A00 AS NVARCHAR(2)), sql_modules.[definition]) > 0, CAST(0x0D000A00 AS NVARCHAR(2)), CAST(0x0A00 AS NVARCHAR(2))),
			/* Find the start of the create statement, so that it can be converted to an alter statement. */
			@offset = PATINDEX(@searchString, REPLACE(sql_modules.[definition], 'CREATE   ' COLLATE SQL_Latin1_General_CP1_CS_AS, 'CREATE '))
		FROM sys.sql_modules
		WHERE
			sql_modules.[object_id] = @objectId;

		IF (@definition IS NULL)
		BEGIN;
			RAISERROR(N'No definition found for object ''%s''.', 16, 1, @objectName);
			RETURN;
		END;

		/* Set the new isSchemaBound to the inverse of the current state, if no desired state was set. */
		SET @newIsSchemaBound = IIF(@newIsSchemaBound IS NULL, @isSchemaBound ^ 1, @newIsSchemaBound);

		IF (@newIsSchemaBound = @isSchemaBound)
		BEGIN;
			DECLARE @errorMessage NVARCHAR(200) = CONCAT(N'The object ''', @objectName, N''' already has schemabinding turned ', IIF(ISNULL(@isSchemaBound, 0) = 0, N'off', N'on'), N'.');

			IF (@enforceStrictChanges = 1)
			BEGIN;
				RAISERROR(@errorMessage, 16, 1);
				RETURN;
			END;
			ELSE
			BEGIN;
				SET @errorMessage = N'WARNING: ' + @errorMessage;
				RAISERROR(@errorMessage, 10, 1);
			END;
		END;

		IF (@offset IS NULL OR @offset = 0)
		BEGIN;
			RAISERROR(N'Could not find CREATE statement in object definition.', 16, 1);
			RETURN;
		END;

		SET @header = SUBSTRING(@definition, 1, @offset - 1);
		SET @definition = STUFF(SUBSTRING(@definition, @offset, LEN(@definition)), 1, 6, N'ALTER');

		IF (@isSchemaBound = 1)
		BEGIN;
			/* Remove SCHEMABINDING statement. */
			SELECT
				@definition = REPLACE(@definition, Search.searchString, N'')
			FROM
				(VALUES
					-- If there are multiple WITH options specified.
					(1, N'SCHEMABINDING, '),
					(2, N'SCHEMABINDING,'),
					(3, N',SCHEMABINDING'),
					(4, N', SCHEMABINDING'),
					-- If SCHEMABINDING is the only WITH option specified.
					(5, CAST(0x0D000A00 AS NVARCHAR(2)) + N'WITH SCHEMABINDING'),
					(6, CAST(0x0D00 AS NVARCHAR(1)) + N'WITH SCHEMABINDING'),
					(7, CAST(0x0A00 AS NVARCHAR(1)) + N'WITH SCHEMABINDING'),
					(8, N'WITH SCHEMABINDING')
				) AS Search (orderNumber, searchString)
			ORDER BY
				Search.orderNumber;
		END;
		ELSE
		BEGIN;
			/* Add SCHEMABINDING statement. */
			DECLARE @withStatement NVARCHAR(20) = NULL;
			DECLARE @offsetOfWithStatement INT = 0;
			DECLARE @offsetOfBodyMarkerWord INT = 0;
			SET @searchString = @newlineCharacter + N'WITH ';

			DECLARE @bodyMarkerWord NVARCHAR(6) =
				(
					CASE @type
						WHEN 'IF' THEN N'RETURN'
						WHEN 'TF' THEN N'BEGIN'
						WHEN 'FN' THEN N'BEGIN'
						ELSE NULL
					END
				);

			SET @offsetOfBodyMarkerWord =
				(
					SELECT TOP(1)
						Search.offset
					FROM
						(
							SELECT
								PATINDEX(Pattern.searchPattern, @definition) AS offset,
								Newline.rowNumber
							FROM
								(VALUES
									(1, CAST(0x0D000A00 AS NVARCHAR(2))),
									(2, CAST(0x0A00 AS NVARCHAR(1))),
									(3, CAST(0x0D00 AS NVARCHAR(1)))
								) AS Newline (rowNumber, newlineCharacter)
								CROSS APPLY
								(
									SELECT
										(N'%' + Newline.newlineCharacter + N'AS[^A-z0-9]%') AS searchPattern
									WHERE
										@bodyMarkerWord IS NULL

									UNION ALL

									SELECT
										(N'%AS' + Newline.newlineCharacter + @bodyMarkerWord + N'[^A-z0-9]%') AS searchPattern
									WHERE
										@bodyMarkerWord IS NOT NULL
								) AS Pattern
						) AS Search
					WHERE
						Search.offset > 0
					ORDER BY
						Search.rowNumber
				);

			SELECT TOP(1)
				@searchString = Search.searchString,
				@offsetOfWithStatement = Search.offset
			FROM
				(
					SELECT
						InnerSearch.searchString,
						PATINDEX(N'%' + InnerSearch.searchString + N'%', @definition) AS offset,
						InnerSearch.rowNumber
					FROM
						(
							VALUES
								(1, CAST(0x0D000A00 AS NVARCHAR(2)) + N'WITH '),
								(2, CAST(0x0A00 AS NVARCHAR(1)) + N'WITH '),
								(3, CAST(0x0D00 AS NVARCHAR(1)) + N'WITH '),
								(4, N'WITH ')
						) AS InnerSearch (rowNumber, searchString)
				) AS Search
			WHERE
				Search.offset > 0
			ORDER BY
				Search.rowNumber;

			SET @withStatement =
				IIF
				(
					@offsetOfWithStatement > @offsetOfBodyMarkerWord
					OR @offsetOfWithStatement < 1,
					CONCAT
					(
						IIF(@type = 'V', @newlineCharacter, NULL),
						N'WITH SCHEMABINDING',
						IIF(@type <> 'V', @newlineCharacter, NULL)
					),
					N' SCHEMABINDING,'
				);

			SET @offsetOfWithStatement = IIF(@offsetOfWithStatement > @offsetOfBodyMarkerWord OR @offsetOfWithStatement < 1, @offsetOfBodyMarkerWord, @offsetOfWithStatement + LEN(@searchString));
			SET @definition = STUFF(@definition, @offsetOfWithStatement, 0, @withStatement);
		END;

		/* debugging output */
		IF (@ifDebug = 1)
		BEGIN;
			PRINT REPLICATE(N'-', 20);
			PRINT CONCAT('@objectName = ', @objectName);
			PRINT CONCAT('@isSchemaBound = ', @isSchemaBound);
			PRINT CONCAT('@newIsSchemaBound = ', @newIsSchemaBound);
			PRINT CAST(@newLineCharacter AS VARBINARY(10));
			PRINT REPLICATE(N'-', 20);
			PRINT @definition;
			PRINT REPLICATE(N'-', 20);
		END;

		/* Put any header text back in the definition. */
		SET @definition = @header + @definition;

		/* Verify that we have something to run... */
		IF (@definition IS NULL)
		BEGIN;
			RAISERROR(N'Definition of object ''%s'' not in expected format.', 16, 1, @objectName);
			RETURN;
		END;

		/* Run the ALTER statement */
		IF (@newIsSchemaBound <> @isSchemaBound)
		BEGIN;
			EXEC (@definition);
		END;

		/* Confirm change. */
		IF NOT EXISTS
		(
			SELECT NULL
			FROM sys.sql_modules
			WHERE
				sql_modules.[object_id] = @objectId
				AND sql_modules.is_schema_bound = @newIsSchemaBound
		)
		BEGIN;
			RAISERROR (N'Alter failed to change the schemabinding for object ''%s''.', 16, 1, @objectName);
			RETURN;
		END;

		-- Commit if we started the transaction
		IF (@localTransaction = 1 AND @@TRANCOUNT > 0)
			COMMIT TRANSACTION;

	END TRY
	BEGIN CATCH;
		IF (@@TRANCOUNT > 0)
			ROLLBACK TRANSACTION;
		THROW;
	END CATCH;
END;
GO

PRINT 'DBA.hsp_ToggleSchemaBinding installed successfully.';
PRINT '';
PRINT 'Installing DBA.hsp_ToggleSchemaBindingBatch (Original Version with STRING_AGG)...';
GO

-- Original batch procedure with STRING_AGG and dependency analysis
CREATE PROCEDURE [DBA].[hsp_ToggleSchemaBindingBatch]
(
	@objectList NVARCHAR(MAX),
	@mode VARCHAR(20) = 'PRINT',
	@onlyIncludeDirectDependencies BIT = 0,
	@scriptOutObjectAlterStatements BIT = 0,
	@isSchemaBoundOnly BIT = 0,	-- only process dependencies that are schema-bound
	@unbindSql NVARCHAR(MAX) OUTPUT,
	@rebindSql NVARCHAR(MAX) OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @errorString NVARCHAR(100);
	DECLARE @printMode VARCHAR(20) = 'PRINT';			-- Prints the schemabinding toggle code to the output
	DECLARE @variableMode VARCHAR(20) = 'VARIABLE';		-- Returns schemabinding toggle code in output variables

	IF (@mode IS NULL)
	BEGIN
		SET @mode = @printMode;
	END;

	--Error Checking
	IF @mode NOT IN (@printMode, @variableMode)
	BEGIN
		SET @errorString = CONCAT('The @mode parameter accepts only the following values: ', @printMode, ', ', @variableMode);
		THROW 50000, @errorString, 1;
	END;

	--Declare variables
	DECLARE @newLine CHAR(2) = CHAR(13) + CHAR(10);
	DECLARE @beginTryBlock VARCHAR(MAX) = 'BEGIN TRY';
	DECLARE @endTryBlock VARCHAR(MAX) =
'END TRY
BEGIN CATCH
	IF (@@TRANCOUNT > 0)
	BEGIN
		ROLLBACK TRANSACTION;
	END;

	THROW;
	RETURN;
END CATCH;';
	DECLARE @ddlGoBlock VARCHAR(MAX) =
'GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR(''SCHEMA CHANGE FAILED!'', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO';
	DECLARE @level TINYINT = 1, @newCount INT = 0;
	DECLARE @printString NVARCHAR(MAX);

	-- Create temp tables for object processing
	CREATE TABLE #SchemaIgnoreList
	(
		schemaName SYSNAME  COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL PRIMARY KEY
	);

	CREATE TABLE #ObjectIgnoreList
	(
		objectId BIGINT NOT NULL PRIMARY KEY
	);

	CREATE TABLE #ObjectListDetails
	(
		objectList NVARCHAR(400)  COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL PRIMARY KEY,
		schemaName SYSNAME  COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
		objectName SYSNAME  COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
		columnName SYSNAME  COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
		schemaAndObjectName AS CONVERT(NVARCHAR(400), CONCAT(schemaName, '.', objectName)) COLLATE SQL_Latin1_General_CP1_CI_AS,
		schemaId INT NULL,
		objectId INT NULL,
		columnId INT NULL
	);

	-- Parse object list using STRING_SPLIT (SQL Server 2016+)
	WITH ListedObjects AS
	(
		SELECT DISTINCT TRIM(value) AS fullObjectString FROM STRING_SPLIT(@objectList, ',')
	), objectNames AS
	(
		SELECT
			ListedObjects.fullObjectString,
			CASE WHEN (LEN(ListedObjects.fullObjectString) - LEN(REPLACE(ListedObjects.fullObjectString, '.', ''))) = 2 THEN PARSENAME(ListedObjects.fullObjectString, 3) ELSE PARSENAME(ListedObjects.fullObjectString, 2) END AS schemaName,
			CASE WHEN (LEN(ListedObjects.fullObjectString) - LEN(REPLACE(ListedObjects.fullObjectString, '.', ''))) = 2 THEN PARSENAME(ListedObjects.fullObjectString, 2) ELSE PARSENAME(ListedObjects.fullObjectString, 1) END AS objectName,
			CASE WHEN (LEN(ListedObjects.fullObjectString) - LEN(REPLACE(ListedObjects.fullObjectString, '.', ''))) = 2 THEN PARSENAME(ListedObjects.fullObjectString, 1) ELSE NULL END AS columnName
		FROM
			ListedObjects
		WHERE
			ListedObjects.fullObjectString <> ''
	)
	INSERT INTO #ObjectListDetails
	(
		objectList,
		schemaName,
		objectName,
		columnName,
		schemaId,
		objectId,
		columnId
	)
		SELECT
			objectNames.fullObjectString AS objectList,
			objectNames.schemaName,
			objectNames.objectName,
			objectNames.columnName,
			schemas.schema_id,
			objects.object_id,
			columns.column_id
		FROM
			objectNames
			LEFT OUTER JOIN sys.schemas
				ON objectNames.schemaName = schemas.name
			LEFT OUTER JOIN sys.objects
				ON objects.schema_id = schemas.schema_id
					AND objects.name = objectNames.objectName
			LEFT OUTER JOIN sys.columns
				ON columns.object_id = objects.object_id
					AND columns.name = objectNames.columnName;

	-- Validation using STRING_AGG (SQL Server 2017+)
	DECLARE @unmatchedSchemaList NVARCHAR(MAX) =
		(
			SELECT
				STRING_AGG(#ObjectListDetails.schemaName, N';')
			FROM #ObjectListDetails
			WHERE
				#ObjectListDetails.schemaId IS NULL
		);

	IF (@unmatchedSchemaList IS NOT NULL)
	BEGIN;
		SET @errorString = CONCAT('The following schemas do not exist: ', @unmatchedSchemaList);
		THROW 50000, @errorString, 1;
	END;

	DECLARE @unmatchedObjectList NVARCHAR(MAX) =
		(
			SELECT
				STRING_AGG(CONCAT(#ObjectListDetails.schemaName, '.', #ObjectListDetails.objectName), N';')
			FROM #ObjectListDetails
			WHERE
				#ObjectListDetails.objectId IS NULL
		);

	IF (@unmatchedObjectList IS NOT NULL)
	BEGIN;
		SET @errorString = CONCAT('The following objects do not exist: ', @unmatchedObjectList);
		THROW 50000, @errorString, 1;
	END;

	DECLARE @unmatchedColumnList NVARCHAR(MAX) =
		(
			SELECT
				STRING_AGG(#ObjectListDetails.objectList, N';')
			FROM #ObjectListDetails
			WHERE
				#ObjectListDetails.columnName IS NOT NULL
				AND #ObjectListDetails.columnId IS NULL
		);

	IF (@unmatchedColumnList IS NOT NULL)
	BEGIN;
		SET @errorString = CONCAT('The following columns were provided, but do not exist: ', @unmatchedColumnList);
		THROW 50000, @errorString, 1;
	END;

	CREATE TABLE #DependentObject
	(
		dependentObjectName NVARCHAR(400) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
		isSchemaBound BIT NOT NULL,
		dependentObjectId INT NOT NULL,
		level TINYINT NOT NULL,
		isView BIT NULL,
		dynamicSql VARCHAR(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
		indexDynamicSql VARCHAR(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL
	);

	-- Get initial level of dependencies
	INSERT INTO #DependentObject
	(
		dependentObjectName,
		isSchemaBound,
		dependentObjectId,
		level
	)
	SELECT
		ISNULL(DependentExpression.referencingObjectName, DependentEntity.referencingObjectName) AS referencingObjectName,
		ISNULL(DependentExpression.is_schema_bound_reference, DependentEntity.is_schema_bound_reference) AS isSchemaBound,
		ISNULL(DependentExpression.referencing_id, DependentEntity.referencing_id) AS dependentObjectId,
		1 AS level
	FROM
		(
			SELECT DISTINCT
				CONCAT(N'"', OBJECT_SCHEMA_NAME(sql_expression_dependencies.referencing_id), N'"."', OBJECT_NAME(sql_expression_dependencies.referencing_id), N'"') AS referencingObjectName,
				sql_expression_dependencies.is_schema_bound_reference,
				sql_expression_dependencies.referencing_id
			FROM
				sys.sql_expression_dependencies
				INNER JOIN #ObjectListDetails AS ObjectListDetails
					ON
						sql_expression_dependencies.referenced_id = ObjectListDetails.objectId
						AND
						(
							ObjectListDetails.columnId IS NULL
							OR sql_expression_dependencies.referenced_minor_id = ObjectListDetails.columnId
						)
			WHERE
				sql_expression_dependencies.referencing_id <> ObjectListDetails.objectId
				AND
				(
					sql_expression_dependencies.is_schema_bound_reference = 1
					OR @isSchemaBoundOnly = 0
				)
				AND NOT EXISTS
				(
					SELECT
						sql_expression_dependencies.referencing_class,
						sql_expression_dependencies.referencing_id

					INTERSECT

					SELECT
						sql_expression_dependencies.referenced_class,
						sql_expression_dependencies.referenced_id
				)
			GROUP BY
				sql_expression_dependencies.referencing_id,
				sql_expression_dependencies.is_schema_bound_reference
		) AS DependentExpression
		FULL OUTER JOIN
		(
			SELECT DISTINCT
				CONCAT(N'"', OBJECT_SCHEMA_NAME(referencing.referencing_id), N'"."', OBJECT_NAME(referencing.referencing_id), N'"') AS referencingObjectName,
				CAST(0 AS BIT) AS is_schema_bound_reference,
				referencing.referencing_id
			FROM
				#ObjectListDetails objectListDetails
				CROSS APPLY sys.dm_sql_referencing_entities (objectListDetails.schemaAndObjectName, N'OBJECT') AS referencing
				OUTER APPLY sys.dm_sql_referenced_entities (CONCAT(referencing.referencing_schema_name, N'.', referencing.referencing_entity_name), N'OBJECT') AS referenced
			WHERE
				referenced.referenced_id = objectListDetails.objectId
				AND
				(
					objectListDetails.columnId IS NULL
					OR referenced.referenced_minor_id = objectListDetails.columnId
				)
				AND referencing.referencing_schema_name NOT IN
				(
					SELECT
						[#SchemaIgnoreList].schemaName
					FROM #SchemaIgnoreList
				)
				AND referencing.referencing_id <> objectListDetails.objectId
				AND referencing.referencing_Id NOT IN
				(
					SELECT
						[#ObjectIgnoreList].objectId
					FROM #ObjectIgnoreList
					WHERE
						[#ObjectIgnoreList].objectId IS NOT NULL
				)
				AND @isSchemaBoundOnly = 0
		) AS DependentEntity
			ON DependentExpression.referencing_id = DependentEntity.referencing_id;

	SET @newCount = @@ROWCOUNT;

	-- Get recursive level(s) of dependencies
	WHILE
	(
		@onlyIncludeDirectDependencies = 0
		AND
		(
			@newCount <> 0
			OR EXISTS
			(
				SELECT NULL
				FROM #DependentObject
				WHERE
					[#DependentObject].level >= @level
			)
		)
	)
	BEGIN
		-- Get new dependencies
		INSERT INTO #DependentObject
		(
			dependentObjectName,
			isSchemaBound,
			dependentObjectId,
			level
		)
		SELECT
			CONCAT(N'"', OBJECT_SCHEMA_NAME(sql_expression_dependencies.referencing_id), N'"."', OBJECT_NAME(sql_expression_dependencies.referencing_id), N'"') AS referencingObjectName,
			sql_expression_dependencies.is_schema_bound_reference,
			sql_expression_dependencies.referencing_id,
			MAX(DependentObject.level) + 1 AS level
		FROM
			sys.sql_expression_dependencies
			INNER JOIN #DependentObject AS DependentObject
				ON sql_expression_dependencies.referenced_id = DependentObject.dependentObjectId
		WHERE
			DependentObject.level = @level
			AND
			(
				sql_expression_dependencies.is_schema_bound_reference = 1
				OR @isSchemaBoundOnly = 0
			)
			AND NOT EXISTS
			(
				SELECT
					sql_expression_dependencies.referencing_class,
					sql_expression_dependencies.referencing_id

				INTERSECT

				SELECT
					sql_expression_dependencies.referenced_class,
					sql_expression_dependencies.referenced_id
			)
		GROUP BY
			sql_expression_dependencies.referencing_id,
			sql_expression_dependencies.is_schema_bound_reference;
	
		SET @newCount = @@ROWCOUNT;
		SET @level += 1;
	END;

	-- Remove duplicate objects that exist at a higher level
	DELETE
	FROM #DependentObject
	WHERE EXISTS
		(
			SELECT *
			FROM #DependentObject AS dups
			WHERE [#DependentObject].dependentObjectId = dups.dependentObjectId
				AND [#DependentObject].level < dups.level
		);

	-- Generate dynamic SQL statements for toggling
	UPDATE DependentObject SET
		isView = Computed.isView,
		dynamicSql =
			CONCAT
			(
				'EXEC ',
				IIF
				(
					DependentObject.isSchemaBound = 0,
					IIF
					(
						Computed.isView = 1,
						'sys.sp_refreshview',
						'sys.sp_refreshsqlmodule /*WARNING: Any associated signatures will be dropped!*/'
					),
					'DBA.hsp_ToggleSchemaBinding'
				),
				' @objectName = N''', ISNULL(DependentObject.dependentObjectName, 'ERROR'), '''',
				IIF
				(
					DependentObject.isSchemaBound = 1,
					', @newIsSchemaBound = ::toggle::',
					''
				),
				';'
			)
	FROM
		#DependentObject AS DependentObject
		INNER JOIN sys.objects AS ref_object
			ON DependentObject.dependentObjectId = ref_object.object_id
		CROSS APPLY
		(
			SELECT
				CAST(IIF(ref_object.type = 'V' /*View*/, 1, 0) AS BIT) AS isView
		) AS Computed
	WHERE
		ref_object.type_desc NOT LIKE '%CONSTRAINT';

	-- Generate Unbind & Rebind queries using STRING_AGG
	SELECT
		@unbindSql = '	/*Toggle Schemabinding Off*/' + REPLACE(REPLACE(UnbindToggleList.value, '&#x0D;', ''), '::toggle::', '0'),
		@rebindSql = '	/*Toggle Schemabinding On and Refresh Non-Schemabound Views*/' + REPLACE(REPLACE(RebindToggleList.value, '&#x0D;', ''), '::toggle::', '1')
	FROM
		(
			-- Get Unbind list using STRING_AGG
			SELECT
				STRING_AGG(@newLine + '	' + NULLIF([#DependentObject].dynamicSql, ''), '') WITHIN GROUP (ORDER BY [#DependentObject].level DESC)
			FROM #DependentObject
			WHERE
				[#DependentObject].dynamicSql IS NOT NULL
				AND [#DependentObject].isSchemaBound = 1
		) AS UnbindToggleList (value)
		CROSS JOIN
		(
			-- Get Rebind/Refresh list using STRING_AGG
			SELECT
				STRING_AGG(@newLine + '	' + NULLIF([#DependentObject].dynamicSql, ''), '') WITHIN GROUP (ORDER BY 
					IIF([#DependentObject].isView = 1 AND [#DependentObject].isSchemaBound = 0, 1, 0), 
					[#DependentObject].level)
			FROM #DependentObject
			WHERE 
				[#DependentObject].dynamicSql IS NOT NULL
		) AS RebindToggleList (value);

	IF @mode = @printMode
	BEGIN
		SET @printString =
			CONCAT(
				@beginTryBlock, @newLine,
				@unbindSql, @newLine,
				@endTryBlock, @newLine,
				@ddlGoBlock, @newLine, @newLine,
				'/**** Your Changes to ' + @objectList + ' go here ****/', @newLine, @newLine,
				@ddlGoBlock, @newLine,
				@beginTryBlock, @newLine, 
				@rebindSql, @newLine, 
				@endTryBlock, @newLine, 
				@ddlGoBlock
			);

		-- Print output in chunks to avoid truncation
		DECLARE @totalBatches INT;
		DECLARE @currentBatch INT = 0;
		DECLARE @substringStartPosition INT = 0;
		DECLARE @substringLength INT;

		-- Standardize all line endings to the same format
		SET @printString = REPLACE(@printString, CHAR(13)+CHAR(10), CHAR(10));
		SET @printString = REPLACE(@printString, CHAR(13), CHAR(10));

		SET @totalBatches = CEILING(LEN(@printString) / 4000.0);

		WHILE @currentBatch <= @totalBatches
		BEGIN
			SET @substringLength = 4000 - CHARINDEX(CHAR(10), REVERSE(SUBSTRING(@printString, @substringStartPosition, 4000)));
			PRINT SUBSTRING(@printString, @substringStartPosition, @substringLength);
			SET @currentBatch = @currentBatch + 1;
			SET @substringStartPosition = @substringStartPosition + @substringLength + 1;
		END;
	END;

	-- Clean up temp tables
	DROP TABLE #ObjectListDetails;
	DROP TABLE #DependentObject;
	DROP TABLE #SchemaIgnoreList;
	DROP TABLE #ObjectIgnoreList;
END;
GO

PRINT 'DBA.hsp_ToggleSchemaBindingBatch installed successfully.';
PRINT '';

PRINT 'Installation complete for SQL Server 2019/2022/2025.';
PRINT 'Both DBA.hsp_ToggleSchemaBinding and DBA.hsp_ToggleSchemaBindingBatch are ready for testing.';
PRINT 'Batch procedure includes SQL Server 2017+ features: STRING_SPLIT, STRING_AGG';

GO