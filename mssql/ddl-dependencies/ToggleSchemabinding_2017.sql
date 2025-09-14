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
CREATE SCHEMA DBA AUTHORIZATION dbo;
GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO
/*
Original creation date:
	2009-05-28
Original authors:
	Joel Searcy
	Kevin M. Owen
Additional contributors:
	Todd Hudson
	Thomas Fowles
	Brian Gilbert
	Brian Belnap
*/
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
		IF (@@TRANCOUNT <= 0)
		BEGIN;
			RAISERROR('DBA.hsp_ToggleSchemaBinding must be called within the context of a transaction.', 16, 0) WITH LOG;
		END;

		BEGIN TRANSACTION;

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
			RAISERROR(N'No object found with name ''%s''.', 16, 1, @objectName) WITH LOG;
		END;

		/* Get the object's type. */
		SELECT
			@type = objects.[type]
		FROM sys.objects
		WHERE
			objects.object_id = @objectId;

		IF (@type NOT IN ('FN','TF','IF','V'))
		BEGIN;
			RAISERROR(N'Object type ''%s'' is not supported (''FN'',''TF'',''IF'',''V'').)', 16, 1, @type) WITH LOG;
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
			RAISERROR(N'No definition found for object ''%s''.', 16, 1, @objectName) WITH LOG;
		END;

		/* Set the new isSchemaBound to the inverse of the current state, if no desired state was set. */
		SET @newIsSchemaBound = IIF(@newIsSchemaBound IS NULL, @isSchemabound ^ 1, @newIsSchemaBound);

		IF (@newIsSchemaBound = @isSchemaBound)
		BEGIN;
			DECLARE @errorMessage NVARCHAR(200) = CONCAT(N'The object ''', @objectName, N''' already has schemabinding turned ', IIF(ISNULL(@isSchemaBound, 0) = 0, N'off', N'on'), N'.');

			IF (@enforceStrictChanges = 1)
			BEGIN;
				RAISERROR(@errorMessage, 16, 1) WITH LOG;
			END;
			ELSE
			BEGIN;
				SET @errorMessage = N'WARNING: ' + @errorMessage;
				RAISERROR(@errorMessage, 10, 1) WITH LOG;
			END;
		END;

		IF (@offset IS NULL OR @offset = 0)
		BEGIN;
			RAISERROR(N'Could not find CREATE statement in object definition.', 16, 1) WITH LOG;
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
			RAISERROR(N'Definition of object ''%s'' not in expected format.', 16, 1, @objectName) WITH LOG;
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
			RAISERROR (N'Alter failed to change the schemabinding for object ''%s''.', 16, 1, @objectName) WITH LOG;
		END;

		COMMIT WORK;
	END TRY
	BEGIN CATCH;
		THROW;
	END CATCH;
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
CREATE PROCEDURE [DBA].[hsp_ToggleSchemaBindingBatch]
(
	@objectList NVARCHAR(MAX),
	@mode VARCHAR(20),
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

	--Ignore schemas
	CREATE TABLE #SchemaIgnoreList
	(
		schemaName SYSNAME  COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL PRIMARY KEY
	);

	--INSERT INTO #SchemaIgnoreList (schemaName)
	--VALUES
	--	('');

	--Ignore objects
	CREATE TABLE #ObjectIgnoreList
	(
		objectId BIGINT NOT NULL PRIMARY KEY
	);
	--INSERT INTO #ObjectIgnoreList (objectId)
	--SELECT
	--	objects.object_id
	--FROM sys.objects
	--WHERE
	--	-- add here if needed;

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


	-- Generate dynamicSql
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
					CONCAT
					(
						'DBA.hsp_ToggleSchemaBindingBatch',
						IIF(Computed.isIndexedView = 1, ' /*Indexed Vew - WARNING: All indexes on this view will be dropped!*/', ''),
						' @objectName = '
					)
				),
				' N''', ISNULL(DependentObject.dependentObjectName, 'ERROR'), '''',
				IIF
				(
					DependentObject.isSchemaBound = 1,
					', @newIsSchemaBound = ::toggle::',
					''
				),
				';'
			),
		indexDynamicSql = REPLACE(Indexes.value,'&#x0D;' /*Weird XML newline character.*/, '')
	FROM
		#DependentObject AS DependentObject
		INNER JOIN sys.objects AS ref_object
			ON DependentObject.dependentObjectId = ref_object.object_id
		CROSS APPLY
		(
			SELECT
				CAST(IIF(ref_object.type = 'V' /*View*/, 1, 0) AS BIT) AS isView,
				CAST(IIF
				(
					ref_object.type = 'V' /*View*/
					AND EXISTS
					(
						SELECT NULL
						FROM sys.indexes
						WHERE
							indexes.object_id = ref_object.object_id
					),
					1,
					0
				) AS BIT) AS isIndexedView
		) AS Computed
		OUTER APPLY
		(
			SELECT
				CONCAT
				(
					'CREATE ',
					IIF(indexes.is_unique = 1, 'UNIQUE ', ''),
					(
						CASE indexes.type
							WHEN 1 THEN 'CLUSTERED'
							WHEN 2 THEN 'NONCLUSTERED'
							WHEN 3 THEN 'XML'
							ELSE '<ERROR>'
						END
					),
					' INDEX ',
					Computed.indexName, @newLine, 'ON ',
					Computed.objectName, @newLine, Computed.indexedColumns,
					ISNULL(@newLine + 'INCLUDE' + @newLine + Computed.includedColumns, ''),
					ISNULL(@newLine + 'WHERE ' + Computed.filterDefinition, ''),
					@newLine, 'WITH ', indexProperties, ';', @newLine, @newLine
				)
			FROM 
				sys.indexes
				INNER JOIN sys.objects
					ON indexes.object_id = objects.object_id
				CROSS APPLY
				(
					SELECT 
						CONCAT(QUOTENAME(SCHEMA_NAME(objects.schema_id), '['), '.', QUOTENAME(objects.name, '[')) AS objectName,
						QUOTENAME(indexes.name, '[') AS indexName,
						indexes.filter_definition AS filterDefinition,
						REPLACE(CONCAT('(', STUFF(KeyColumn.value, 1, 1, '') + @newLine, ')'), '^', @newLine + '	')  AS indexedColumns,
						KeyColumn.value AS keyColumnsRaw,
						IIF(IncludedColumn.value IS NOT NULL, REPLACE(CONCAT('(', STUFF(IncludedColumn.value, 1, 1, ''), @newLine, ')'), '^', @newLine + '	'), NULL) AS includedColumns,
						IncludedColumn.value AS includedColumnsRaw,
						IIF(IndexProperties.value IS NOT NULL, CONCAT('(', STUFF(IndexProperties.value, 1, 2, ''), ')'), NULL) AS indexProperties
					FROM
						(
							SELECT
								CONCAT(',^', QUOTENAME(columns.name, '['), IIF(index_columns.is_descending_key = 1, ' DESC', ''))
							FROM 
								sys.columns 
								INNER JOIN sys.index_columns
									ON columns.column_id = index_columns.column_id
										AND columns.object_id = index_columns.object_id
							WHERE 
								index_columns.object_id = indexes.object_id
								AND index_columns.index_id = indexes.index_id
								AND index_columns.is_included_column = 0
							ORDER BY 
								index_columns.key_ordinal
							FOR XML PATH ('')
						) AS KeyColumn (value)
						OUTER APPLY
						(
							SELECT
								CONCAT(',^', QUOTENAME(columns.name, '['))
							FROM
								sys.columns 
								INNER JOIN sys.index_columns
									ON columns.column_id = index_columns.column_id
										AND columns.object_id = index_columns.object_id
							WHERE
								index_columns.object_id = indexes.object_id
								AND index_columns.index_id = indexes.index_id
								AND index_columns.is_included_column = 1	
							ORDER BY
								columns.name
							FOR XML PATH ('')
						) AS IncludedColumn (value)
						OUTER APPLY
						(
							SELECT 
								CONCAT
								(
									', ', IndexProperties.propertyName, ' = ',
									IIF
									(
										IndexProperties.propertyValue IS NULL,
										IIF
										(
											IndexProperties.isYesNo IS NOT NULL,
											IIF(INDEXPROPERTY(indexes.object_id, indexes.name, IndexProperties.propertyLookup) = IndexProperties.isYesNo, 'ON', 'OFF'),
											CAST(NULLIF(INDEXPROPERTY(indexes.object_id, indexes.name, IndexProperties.propertyLookup), 0) AS NVARCHAR(20))
										),
										IIF
										(
											IndexProperties.isYesNo IS NOT NULL,
											IIF(IndexProperties.propertyValue = 1, 'ON', 'OFF'),
											CAST(NULLIF(IndexProperties.propertyValue, 0) AS NVARCHAR(20))
										)
									)
								)
							FROM
								(VALUES
									(1, 'PAD_INDEX','IsPadIndex', indexes.is_padded, CAST(1 AS BIT)),
									(2, 'STATISTICS_NORECOMPUTE','IsStatistics', NULL, CAST(1 AS BIT)),
									--(3, 'SORT_IN_TEMPDB', '', NULL, CAST(1 AS BIT)), -- Only affects the current index (re)build
									(4, 'IGNORE_DUP_KEY', NULL, indexes.ignore_dup_key, CAST(1 AS BIT)),
									--(5, 'DROP_EXISTING', '', NULL, CAST(1 AS BIT)), -- Doesn't matter in the intended context. Only affects the current create index statement
									--(6, 'ONLINE', '', NULL, CAST(1 AS BIT)), -- Only affects the current index (re)build (not allowed on some indexes)
									(7, 'ALLOW_ROW_LOCKS','IsRowLockDisallowed', indexes.allow_row_locks, CAST(0 AS BIT)),
									(8, 'ALLOW_PAGE_LOCKS','IsPageLockDisallowed', indexes.allow_page_locks, CAST(0 AS BIT)),
									(9, 'FILLFACTOR','IndexFillFactor', indexes.fill_factor, CAST(NULL AS BIT))
								) AS IndexProperties (displayOrder, propertyName, propertyLookup, propertyValue, isYesNo)
							WHERE
								IndexProperties.propertyName <> 'FILLFACTOR'
								OR
								(
									IndexProperties.propertyName = 'FILLFACTOR'
									AND ISNULL(INDEXPROPERTY(indexes.object_id, indexes.name, IndexProperties.propertyLookup), 0) <> 0
								)
							ORDER BY
								IndexProperties.displayOrder
							FOR XML PATH ('')
						) AS IndexProperties (value)
				) AS Computed
			WHERE
				indexes.is_unique_constraint = 0
				AND indexes.is_primary_key = 0
				AND indexes.type IN
				(
					--0 /*HEAP*/,
					1 /*CLUSTERED*/,
					2 /*NONCLUSTERED*/
					--4 /*SPATIAL*/
				)
				AND indexes.object_id = ref_object.object_id
				AND objects.type = 'V' /*View*/
			ORDER BY
				indexes.object_id,	
				indexes.index_id
			FOR XML PATH ('')
		) AS Indexes (value)
	WHERE
		ref_object.type_desc NOT LIKE '%CONSTRAINT';

	-- Conditionally create indexes for base level indexed view(s), but only if the view is not already a dependency.
	INSERT INTO #DependentObject
	(
		dependentObjectName,	
		isSchemaBound,
		dependentObjectId,
		level,
		isView,
		dynamicSql,
		indexDynamicSql
	)
	SELECT
		CONCAT(N'"', OBJECT_SCHEMA_NAME(ref_object.object_id), N'"."', OBJECT_NAME(ref_object.object_id), N'"') AS referencingObjectName,
		1 AS isSchemaBound,
		ref_object.object_id AS dependentObjectId,
		0 AS level,
		Computed.isView,	
		'' AS dynamicSql,
		indexDynamicSql = REPLACE(Indexes.value,'&#x0D;' /*Weird XML newline character.*/, '')
	FROM	
		#ObjectListDetails
		INNER JOIN sys.objects AS ref_object	
			ON [#ObjectListDetails].objectId = ref_object.object_id
		CROSS APPLY
		(
			SELECT
				CAST(IIF(ref_object.type = 'V' /*View*/, 1, 0) AS BIT) AS isView,
				CAST(IIF	
				(
					ref_object.type = 'V' /*View*/
					AND EXISTS
					(
						SELECT NULL
						FROM sys.indexes	
						WHERE
							indexes.object_id = ref_object.object_id	
					),
					1,
					0
				) AS BIT) AS isIndexedView
		) AS Computed
		OUTER APPLY
		(
			SELECT
				CONCAT
				(
					'IF NOT EXISTS ( SELECT NULL FROM sys.indexes WHERE indexes.name = ''',
					Computed.indexName, ''' )', @newLine,
					'BEGIN', @newLine,
					'CREATE ',
					IIF(indexes.is_unique = 1, 'UNIQUE ', ''),
					(
						CASE indexes.type
							WHEN 1 THEN 'CLUSTERED'
							WHEN 2 THEN 'NONCLUSTERED'
							WHEN 3 THEN 'XML'
							ELSE '<ERROR>'
						END
					),
					' INDEX ',
					QUOTENAME(Computed.indexName, '['), @newLine, 'ON ',	
					Computed.objectName, @newLine, Computed.indexedColumns,
					ISNULL(@newLine + 'INCLUDE' + @newLine + Computed.includedColumns, ''),
					ISNULL(@newLine + 'WHERE ' + Computed.filterDefinition, ''),	
					@newLine, 'WITH ', indexProperties, ';', @newLine,
					'END', @newLine, @newLine
				)
			FROM
				sys.indexes
				INNER JOIN sys.objects
					ON indexes.object_id = objects.object_id	
				CROSS APPLY
				(
					SELECT
						CONCAT(QUOTENAME(SCHEMA_NAME(objects.schema_id), '['), '.', QUOTENAME(objects.name, '[')) AS objectName,	
						indexes.name AS indexName,
						indexes.filter_definition AS filterDefinition,
						REPLACE(CONCAT('(', STUFF(KeyColumn.value, 1, 1, '') + @newLine, ')'), '^', @newLine + '	')  AS indexedColumns,
						KeyColumn.value AS keyColumnsRaw,
						IIF(IncludedColumn.value IS NOT NULL, REPLACE(CONCAT('(', STUFF(IncludedColumn.value, 1, 1, ''), @newLine, ')'), '^', @newLine + '	'), NULL) AS includedColumns,
						IncludedColumn.value AS includedColumnsRaw,
						IIF(IndexProperties.value IS NOT NULL, CONCAT('(', STUFF(IndexProperties.value, 1, 2, ''), ')'), NULL) AS indexProperties
					FROM	
						(
							SELECT
								CONCAT(',^', QUOTENAME(columns.name, '['), IIF(index_columns.is_descending_key = 1, ' DESC', ''))
							FROM
								sys.columns 
								INNER JOIN sys.index_columns	
									ON columns.column_id = index_columns.column_id
										AND columns.object_id = index_columns.object_id
							WHERE
								index_columns.object_id = indexes.object_id
								AND index_columns.index_id = indexes.index_id
								AND index_columns.is_included_column = 0	
							ORDER BY
								index_columns.key_ordinal
							FOR XML PATH ('')
						) AS KeyColumn (value)
						OUTER APPLY
						(
							SELECT
								CONCAT(',^', QUOTENAME(columns.name, '['))
							FROM	
								sys.columns 	
								INNER JOIN sys.index_columns	
									ON columns.column_id = index_columns.column_id
										AND columns.object_id = index_columns.object_id
							WHERE
								index_columns.object_id = indexes.object_id
								AND index_columns.index_id = indexes.index_id
								AND index_columns.is_included_column = 1	
							ORDER BY	
								columns.name	
							FOR XML PATH ('')
						) AS IncludedColumn (value)
						OUTER APPLY
						(
							SELECT
								CONCAT
								(
									', ', IndexProperties.propertyName, ' = ',
									IIF
									(
										IndexProperties.propertyValue IS NULL,
										IIF
										(
											IndexProperties.isYesNo IS NOT NULL,	
											IIF(INDEXPROPERTY(indexes.object_id, indexes.name, IndexProperties.propertyLookup) = IndexProperties.isYesNo, 'ON', 'OFF'),
											CAST(NULLIF(INDEXPROPERTY(indexes.object_id, indexes.name, IndexProperties.propertyLookup), 0) AS NVARCHAR(20))
										),
										IIF
										(
											IndexProperties.isYesNo IS NOT NULL,	
											IIF(IndexProperties.propertyValue = 1, 'ON', 'OFF'),	
											CAST(NULLIF(IndexProperties.propertyValue, 0) AS NVARCHAR(20))
										)
									)
								)
							FROM	
								(VALUES
									(1, 'PAD_INDEX','IsPadIndex', indexes.is_padded, CAST(1 AS BIT)),
									(2, 'STATISTICS_NORECOMPUTE','IsStatistics', NULL, CAST(1 AS BIT)),
									--(3, 'SORT_IN_TEMPDB', '', NULL, CAST(1 AS BIT)), -- Only affects the current index (re)build	
									(4, 'IGNORE_DUP_KEY', NULL, indexes.ignore_dup_key, CAST(1 AS BIT)),	
									--(5, 'DROP_EXISTING', '', NULL, CAST(1 AS BIT)), -- Doesn't matter in the intended context. Only affects the current create index statement	
									--(6, 'ONLINE', '', NULL, CAST(1 AS BIT)), -- Only affects the current index (re)build (not allowed on some indexes)	
									(7, 'ALLOW_ROW_LOCKS','IsRowLockDisallowed', indexes.allow_row_locks, CAST(0 AS BIT)),
									(8, 'ALLOW_PAGE_LOCKS','IsPageLockDisallowed', indexes.allow_page_locks, CAST(0 AS BIT)),
									(9, 'FILLFACTOR','IndexFillFactor', indexes.fill_factor, CAST(NULL AS BIT))
								) AS IndexProperties (displayOrder, propertyName, propertyLookup, propertyValue, isYesNo)
							WHERE
								IndexProperties.propertyName <> 'FILLFACTOR'	
								OR
								(
									IndexProperties.propertyName = 'FILLFACTOR'
									AND ISNULL(INDEXPROPERTY(indexes.object_id, indexes.name, IndexProperties.propertyLookup), 0) <> 0
								)
							ORDER BY	
								IndexProperties.displayOrder	
							FOR XML PATH ('')
						) AS IndexProperties (value)	
				) AS Computed
			WHERE
				indexes.is_unique_constraint = 0	
				AND indexes.is_primary_key = 0
				AND indexes.type IN
				(
					--0 /*HEAP*/,
					1 /*CLUSTERED*/,	
					2 /*NONCLUSTERED*/
					--4 /*SPATIAL*/
				)
				AND indexes.object_id = ref_object.object_id	
				AND objects.type = 'V' /*View*/
			ORDER BY	
				indexes.object_id,
				indexes.index_id	
			FOR XML PATH ('')
		) AS Indexes (value)	
	WHERE
		Computed.isView = 1
		AND Computed.isIndexedView = 1
		AND NOT EXISTS
		(	-- Don't script index creation here if the view is a dependency at a higher level (it will be scripted later)
			SELECT NULL
			FROM #DependentObject
			WHERE [#DependentObject].dependentObjectId = ref_object.object_id
		);

	-- Remove non-compilable objects from refresh list
	DECLARE @dependentObjectId INT;
	DECLARE NonCompilationCursor CURSOR FAST_FORWARD READ_ONLY
	FOR
		SELECT
			[#DependentObject].dependentObjectId
		FROM #DependentObject
		WHERE
			[#DependentObject].isSchemaBound = 0
		ORDER BY
			[#DependentObject].level DESC;

	OPEN NonCompilationCursor;
	FETCH NEXT FROM NonCompilationCursor
		INTO @dependentObjectId;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SELECT
			CAST(NULL AS BIT) AS temp
			INTO #Temp
		FROM
			sys.all_objects
			CROSS APPLY sys.dm_sql_referenced_entities
				(
				CONCAT
				(
					QUOTENAME(SCHEMA_NAME(all_objects.schema_id), '['),
					'.',
					QUOTENAME(all_objects.name, '[')
				),
				N'OBJECT'
				) AS Referenced
		WHERE
			all_objects.object_id = @dependentObjectId;

		IF (@@ERROR <> 0)
		BEGIN
			DELETE FROM #DependentObject
			WHERE
				[#DependentObject].dependentObjectId = @dependentObjectId;
		END;

		DROP TABLE #Temp;
		SET @dependentObjectId = NULL;
		
		FETCH NEXT FROM NonCompilationCursor
		INTO @dependentObjectId;
	END;

	CLOSE NonCompilationCursor;
	DEALLOCATE NonCompilationCursor;

	-- Generate Unbind & Rebind queries
	SELECT
		@unbindSql = '	/*Toggle Schemabinding Off*/' + REPLACE(REPLACE(UnbindToggleList.value, '&#x0D;', ''), '::toggle::', '0'),
		@rebindSql = '	/*Toggle Schemabinding On and Refresh Non-Schemabound Views*/' + REPLACE(REPLACE(RebindToggleList.value, '&#x0D;', ''), '::toggle::', '1')
	FROM
		(
			-- Get Unbind list
			SELECT
				@newLine + '	' + NULLIF([#DependentObject].dynamicSql, '')
			FROM #DependentObject
			WHERE
				[#DependentObject].dynamicSql IS NOT NULL
				AND [#DependentObject].isSchemaBound = 1
			ORDER BY 
				[#DependentObject].level DESC
			FOR XML PATH ('')
		) AS UnbindToggleList (value)
		CROSS JOIN
		(
			-- Get Rebind/Refresh list
			SELECT
				CONCAT
				(
					@newLine + '	' + NULLIF([#DependentObject].dynamicSql, ''),
					@newLine + [#DependentObject].indexDynamicSql
				)
			FROM #DependentObject
			WHERE 
				[#DependentObject].dynamicSql IS NOT NULL
			ORDER BY
				IIF([#DependentObject].isView = 1 AND [#DependentObject].isSchemaBound = 0, 1, 0), 
				[#DependentObject].level
			FOR XML PATH ('')
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
				@ddlGoBlock, @newLine
			);
		IF (@scriptOutObjectAlterStatements = 0)
		BEGIN
			SET @printString = CONCAT(@printString, @beginTryBlock, @newLine, @rebindSql, @newLine, @endTryBlock, @newLine, @ddlGoBlock);
		END
		ELSE BEGIN
			DECLARE @rebindIndexes NVARCHAR(MAX) = NULL;
			DECLARE @rebindAlterDefinition NVARCHAR(MAX) = NULL;

			DECLARE ObjectDefinition_Cursor CURSOR LOCAL READ_ONLY FAST_FORWARD FOR
			(
				SELECT
					STUFF
					(
						OBJECT_DEFINITION([#DependentObject].dependentObjectId),
						ISNULL(NULLIF(Search.offset, 0), Search.alternateOffset),
						8,
						CONCAT
						(
							IIF(ISNULL(NULLIF(Search.offset, 0), Search.alternateOffset) > 1, CAST(0x0A AS CHAR(1)), ''),
							'ALTER '
						)
					) AS definition,
					REPLACE([#DependentObject].indexDynamicSql, CAST(0x0A AS CHAR(1)), @newLine) AS indexDynamicSql
				FROM
					#DependentObject
					CROSS APPLY
					(
						SELECT
							PATINDEX(CONCAT('%', CAST(0x0A AS CHAR(1)), 'CREATE %'), OBJECT_DEFINITION([#DependentObject].dependentObjectId)) AS offset,
							PATINDEX(CONCAT('%', 'CREATE %'), OBJECT_DEFINITION([#DependentObject].dependentObjectId)) AS alternateOffset
					) AS Search
				WHERE
					[#DependentObject].dynamicSql IS NOT NULL
			)
			ORDER BY
				IIF([#DependentObject].isView = 1 AND [#DependentObject].isSchemaBound = 0, 1, 0),
				[#DependentObject].level;

			OPEN ObjectDefinition_Cursor;

			FETCH NEXT FROM ObjectDefinition_Cursor
				INTO @rebindAlterDefinition,
					@rebindIndexes;

			WHILE (@@FETCH_STATUS = 0)
			BEGIN
				SET @printString = CONCAT(@printString, @rebindAlterDefinition, @newLine, @ddlGoBlock, @newLine);

				IF (@rebindIndexes IS NOT NULL)
				BEGIN
					SET @printString = CONCAT(@printString, @rebindIndexes, @newLine, @ddlGoBlock, @newLine);
				END;

				SET @rebindAlterDefinition = NULL;
				SET @rebindIndexes = NULL;

				FETCH NEXT FROM ObjectDefinition_Cursor
					INTO @rebindAlterDefinition,
						@rebindIndexes;
			END;

			CLOSE ObjectDefinition_Cursor;
			DEALLOCATE ObjectDefinition_Cursor;
		END;

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

/*
build toggle statements:
EXEC DBA.hsp_ToggleSchemaBindingBatchBatch
	@objectList = 'Foo.Bar',
	@mode = NULL,
	@onlyIncludeDirectDependencies = 0,
	@scriptOutObjectAlterStatements = 0,
	@isSchemaBoundOnly = 0,
	@unbindSql = NULL,
	@rebindSql = NULL;
*/


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