-- Enhanced Installation Script for ToggleSchemabinding Procedures
-- SQL Server 2017+ Enhanced Features Version (2019/2022/2025 Compatible)
-- Leverages modern SQL Server features for improved performance

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

-- Drop existing enhanced procedures if they exist
IF OBJECT_ID('DBA.hsp_ToggleSchemaBinding_enhanced', 'P') IS NOT NULL
    DROP PROCEDURE DBA.hsp_ToggleSchemaBinding_enhanced;
GO

IF OBJECT_ID('DBA.hsp_ToggleSchemaBindingBatch_enhanced', 'P') IS NOT NULL
    DROP PROCEDURE DBA.hsp_ToggleSchemaBindingBatch_enhanced;
GO

PRINT 'Installing DBA.hsp_ToggleSchemaBinding_enhanced (SQL Server 2017+ Enhanced Version)...';
GO

-- Enhanced core procedure with SQL Server 2017+ features
CREATE PROCEDURE DBA.hsp_ToggleSchemaBinding_enhanced
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
		-- Enhanced transaction handling with consolidated declarations
		DECLARE @localTransaction BIT = 0,
				@objectId INT = OBJECT_ID(@objectName),
				@type CHAR(2) = NULL,
				@definition NVARCHAR(MAX) = NULL,
				@isSchemaBound BIT = NULL,
				@searchString NVARCHAR(100) = NULL,
				@header NVARCHAR(MAX) = NULL,
				@offset INT = 0,
				@newlineCharacter NVARCHAR(2) = CAST(0x0D000A00 AS NVARCHAR(2));

		IF (@@TRANCOUNT <= 0)
		BEGIN;
			BEGIN TRANSACTION;
			SET @localTransaction = 1;
		END;

		IF (@objectId IS NULL)
		BEGIN;
			RAISERROR(N'No object found with name ''%s''.', 16, 1, @objectName);
			RETURN;
		END;

		-- Enhanced object type validation with optimized WHERE clause
		SELECT @type = o.[type]
		FROM sys.objects o
		WHERE o.object_id = @objectId
			AND o.[type] IN ('FN','TF','IF','V');

		IF (@type IS NULL)
		BEGIN;
			RAISERROR(N'Object type is not supported. Only functions and views are supported.', 16, 1);
			RETURN;
		END;

		-- Enhanced search string construction using CONCAT
		SET @searchString = CONCAT(
			N'%CREATE ',
			CASE 
				WHEN @type IN ('FN','TF','IF') THEN 'FUNCTION%'
				WHEN @type = 'V' THEN N'VIEW%'
				ELSE N'%'
			END
		);

		-- Enhanced definition retrieval with modern SQL features
		SELECT
			@definition = sm.[definition],
			@isSchemaBound = sm.is_schema_bound,
			-- Use IIF for better performance than CASE (SQL Server 2017+)
			@newlineCharacter = IIF(
				CHARINDEX(CAST(0x0D000A00 AS NVARCHAR(2)), sm.[definition]) > 0, 
				CAST(0x0D000A00 AS NVARCHAR(2)), 
				CAST(0x0A00 AS NVARCHAR(2))
			),
			-- Optimized pattern matching with REPLACE for better performance
			@offset = PATINDEX(
				@searchString, 
				REPLACE(sm.[definition], 'CREATE   ' COLLATE SQL_Latin1_General_CP1_CS_AS, 'CREATE ')
			)
		FROM sys.sql_modules sm
		WHERE sm.[object_id] = @objectId;

		IF (@definition IS NULL)
		BEGIN;
			RAISERROR(N'No definition found for object ''%s''.', 16, 1, @objectName);
			RETURN;
		END;

		-- Set the new isSchemaBound using IIF for enhanced performance
		SET @newIsSchemaBound = IIF(@newIsSchemaBound IS NULL, @isSchemaBound ^ 1, @newIsSchemaBound);

		IF (@newIsSchemaBound = @isSchemaBound)
		BEGIN;
			DECLARE @errorMessage NVARCHAR(200) = CONCAT(
				N'The object ''', @objectName, N''' already has schemabinding turned ', 
				IIF(ISNULL(@isSchemaBound, 0) = 0, N'off', N'on'), N'.'
			);

			IF (@enforceStrictChanges = 1)
			BEGIN;
				RAISERROR(@errorMessage, 16, 1);
				RETURN;
			END;
			ELSE
			BEGIN;
				SET @errorMessage = CONCAT(N'WARNING: ', @errorMessage);
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
			-- Enhanced SCHEMABINDING removal using optimized table variable approach
			DECLARE @searchPatterns TABLE (priority INT, searchString NVARCHAR(50));
			
			INSERT INTO @searchPatterns (priority, searchString) VALUES
				(1, N'SCHEMABINDING, '),
				(2, N'SCHEMABINDING,'),
				(3, N',SCHEMABINDING'),
				(4, N', SCHEMABINDING'),
				(5, CONCAT(CHAR(13), CHAR(10), N'WITH SCHEMABINDING')),
				(6, CONCAT(CHAR(13), N'WITH SCHEMABINDING')),
				(7, CONCAT(CHAR(10), N'WITH SCHEMABINDING')),
				(8, N'WITH SCHEMABINDING');

			-- Process all replacements efficiently
			SELECT @definition = 
				CASE 
					WHEN EXISTS (SELECT 1 FROM @searchPatterns sp WHERE CHARINDEX(sp.searchString, @definition) > 0)
					THEN (
						SELECT TOP 1 REPLACE(@definition, sp.searchString, N'')
						FROM @searchPatterns sp
						WHERE CHARINDEX(sp.searchString, @definition) > 0
						ORDER BY sp.priority
					)
					ELSE @definition
				END;
		END;
		ELSE
		BEGIN;
			-- Enhanced WITH statement handling using modern SQL features
			DECLARE @withStatement NVARCHAR(20) = NULL,
					@offsetOfWithStatement INT = 0,
					@offsetOfBodyMarkerWord INT = 0;
			
			SET @searchString = CONCAT(@newlineCharacter, N'WITH ');

			-- Use consolidated CASE with modern pattern matching
			DECLARE @bodyMarkerWord NVARCHAR(6) = 
				CASE @type
					WHEN 'IF' THEN N'RETURN'
					WHEN 'TF' THEN N'BEGIN'
					WHEN 'FN' THEN N'BEGIN'
					ELSE NULL
				END;

			-- Enhanced body marker detection with optimized queries
			WITH NewlinePatterns AS (
				SELECT rowNumber, newlineCharacter
				FROM (VALUES
					(1, CAST(0x0D000A00 AS NVARCHAR(2))),
					(2, CAST(0x0A00 AS NVARCHAR(1))),
					(3, CAST(0x0D00 AS NVARCHAR(1)))
				) AS patterns(rowNumber, newlineCharacter)
			),
			SearchPatterns AS (
				SELECT 
					np.rowNumber,
					CASE 
						WHEN @bodyMarkerWord IS NULL THEN CONCAT(N'%', np.newlineCharacter, N'AS[^A-z0-9]%')
						ELSE CONCAT(N'%AS', np.newlineCharacter, @bodyMarkerWord, N'[^A-z0-9]%')
					END AS searchPattern
				FROM NewlinePatterns np
			)
			SELECT TOP(1) @offsetOfBodyMarkerWord = PATINDEX(sp.searchPattern, @definition)
			FROM SearchPatterns sp
			WHERE PATINDEX(sp.searchPattern, @definition) > 0
			ORDER BY sp.rowNumber;

			-- Enhanced WITH statement detection
			WITH WithPatterns AS (
				SELECT rowNumber, searchString
				FROM (VALUES
					(1, CONCAT(CAST(0x0D000A00 AS NVARCHAR(2)), N'WITH ')),
					(2, CONCAT(CAST(0x0A00 AS NVARCHAR(1)), N'WITH ')),
					(3, CONCAT(CAST(0x0D00 AS NVARCHAR(1)), N'WITH ')),
					(4, N'WITH ')
				) AS patterns(rowNumber, searchString)
			)
			SELECT TOP(1) 
				@searchString = wp.searchString,
				@offsetOfWithStatement = PATINDEX(CONCAT(N'%', wp.searchString, N'%'), @definition)
			FROM WithPatterns wp
			WHERE PATINDEX(CONCAT(N'%', wp.searchString, N'%'), @definition) > 0
			ORDER BY wp.rowNumber;

			-- Optimized WITH statement construction using IIF
			SET @withStatement = IIF(
				@offsetOfWithStatement > @offsetOfBodyMarkerWord OR @offsetOfWithStatement < 1,
				CONCAT(
					IIF(@type = 'V', @newlineCharacter, NULL),
					N'WITH SCHEMABINDING',
					IIF(@type <> 'V', @newlineCharacter, NULL)
				),
				N' SCHEMABINDING,'
			);

			SET @offsetOfWithStatement = IIF(
				@offsetOfWithStatement > @offsetOfBodyMarkerWord OR @offsetOfWithStatement < 1, 
				@offsetOfBodyMarkerWord, 
				@offsetOfWithStatement + LEN(@searchString)
			);
			SET @definition = STUFF(@definition, @offsetOfWithStatement, 0, @withStatement);
		END;

		-- Enhanced debugging output with CONCAT
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

		-- Put any header text back in the definition using CONCAT
		SET @definition = CONCAT(@header, @definition);

		-- Verify that we have something to run
		IF (@definition IS NULL)
		BEGIN;
			RAISERROR(N'Definition of object ''%s'' not in expected format.', 16, 1, @objectName);
			RETURN;
		END;

		-- Run the ALTER statement
		IF (@newIsSchemaBound <> @isSchemaBound)
		BEGIN;
			EXEC (@definition);
		END;

		-- Enhanced confirmation check with EXISTS
		IF NOT EXISTS (
			SELECT 1
			FROM sys.sql_modules sm
			WHERE sm.[object_id] = @objectId
				AND sm.is_schema_bound = @newIsSchemaBound
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

PRINT 'DBA.hsp_ToggleSchemaBinding_enhanced installed successfully.';
PRINT '';
PRINT 'Installing DBA.hsp_ToggleSchemaBindingBatch_enhanced (Enhanced Version with SQL Server 2017+ Features)...';
GO

-- Enhanced batch procedure with SQL Server 2017+ features
CREATE PROCEDURE [DBA].[hsp_ToggleSchemaBindingBatch_enhanced]
(
	@objectList NVARCHAR(MAX),
	@mode VARCHAR(20) = 'PRINT',
	@onlyIncludeDirectDependencies BIT = 0,
	@scriptOutObjectAlterStatements BIT = 0,
	@isSchemaBoundOnly BIT = 0,
	@unbindSql NVARCHAR(MAX) OUTPUT,
	@rebindSql NVARCHAR(MAX) OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;

	-- Enhanced variable declarations with SQL Server 2017+ optimizations
	DECLARE @errorString NVARCHAR(100),
			@printMode VARCHAR(20) = 'PRINT',
			@variableMode VARCHAR(20) = 'VARIABLE',
			@level TINYINT = 1,
			@newCount INT = 0,
			@printString NVARCHAR(MAX);

	IF (@mode IS NULL)
		SET @mode = @printMode;

	-- Enhanced mode validation using STRING_SPLIT
	IF NOT EXISTS (
		SELECT 1 FROM STRING_SPLIT(@printMode + ',' + @variableMode, ',') 
		WHERE TRIM([value]) = @mode
	)
	BEGIN;
		SET @errorString = CONCAT('Invalid @mode specified: ', @mode, '. Valid values are: ', @printMode, ', ', @variableMode);
		THROW 50000, @errorString, 1;
	END;

	-- Enhanced temp table creation with better indexing
	CREATE TABLE #ObjectListDetails
	(
		objectList NVARCHAR(400) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL PRIMARY KEY,
		schemaName SYSNAME COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
		objectName SYSNAME COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
		columnName SYSNAME COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
		schemaAndObjectName AS CONVERT(NVARCHAR(400), CONCAT(schemaName, '.', objectName)) COLLATE SQL_Latin1_General_CP1_CI_AS,
		schemaId INT NULL,
		objectId INT NULL,
		columnId INT NULL,
		INDEX IX_ObjectListDetails_ObjectId NONCLUSTERED (objectId)
	);

	-- Enhanced object list parsing using STRING_SPLIT (SQL Server 2017+)
	WITH ParsedObjects AS (
		SELECT 
			TRIM([value]) AS fullObjectString,
			-- Enhanced parsing with PARSENAME and better NULL handling
			ISNULL(NULLIF(PARSENAME(TRIM([value]), 2), ''), 'dbo') AS schemaName,
			PARSENAME(TRIM([value]), 1) AS objectName,
			CASE 
				WHEN LEN(TRIM([value])) - LEN(REPLACE(TRIM([value]), '.', '')) = 2 
				THEN PARSENAME(TRIM([value]), 1)
				ELSE NULL
			END AS columnName
		FROM STRING_SPLIT(@objectList, ',')
		WHERE TRIM([value]) <> ''
	)
	INSERT INTO #ObjectListDetails (objectList, schemaName, objectName, columnName)
	SELECT 
		po.fullObjectString,
		po.schemaName,
		CASE 
			WHEN po.columnName IS NOT NULL 
			THEN PARSENAME(po.fullObjectString, 2)
			ELSE po.objectName
		END,
		po.columnName
	FROM ParsedObjects po;

	-- Enhanced object validation with modern SQL features
	UPDATE old SET
		schemaId = s.schema_id,
		objectId = o.object_id,
		columnId = c.column_id
	FROM #ObjectListDetails old
	INNER JOIN sys.schemas s ON s.name = old.schemaName
	INNER JOIN sys.objects o ON o.schema_id = s.schema_id AND o.name = old.objectName
	LEFT JOIN sys.columns c ON c.object_id = o.object_id AND c.name = old.columnName;

	-- Enhanced validation using STRING_AGG (SQL Server 2017+)
	DECLARE @unmatchedSchemaList NVARCHAR(MAX) = (
		SELECT STRING_AGG(old.schemaName, N';')
		FROM #ObjectListDetails old
		WHERE old.schemaId IS NULL
	);

	IF (@unmatchedSchemaList IS NOT NULL)
	BEGIN;
		SET @errorString = CONCAT('The following schemas do not exist: ', @unmatchedSchemaList);
		THROW 50000, @errorString, 1;
	END;

	DECLARE @unmatchedObjectList NVARCHAR(MAX) = (
		SELECT STRING_AGG(CONCAT(old.schemaName, '.', old.objectName), N';')
		FROM #ObjectListDetails old
		WHERE old.objectId IS NULL
	);

	IF (@unmatchedObjectList IS NOT NULL)
	BEGIN;
		SET @errorString = CONCAT('The following objects do not exist: ', @unmatchedObjectList);
		THROW 50000, @errorString, 1;
	END;

	DECLARE @unmatchedColumnList NVARCHAR(MAX) = (
		SELECT STRING_AGG(old.objectList, N';')
		FROM #ObjectListDetails old
		WHERE old.columnName IS NOT NULL AND old.columnId IS NULL
	);

	IF (@unmatchedColumnList IS NOT NULL)
	BEGIN;
		SET @errorString = CONCAT('The following columns were provided, but do not exist: ', @unmatchedColumnList);
		THROW 50000, @errorString, 1;
	END;

	-- Enhanced dependency tracking table
	CREATE TABLE #DependentObject
	(
		dependentObjectName NVARCHAR(400) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
		isSchemaBound BIT NOT NULL,
		dependentObjectId INT NOT NULL,
		level TINYINT NOT NULL,
		isView BIT NULL,
		dynamicSql NVARCHAR(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
		indexDynamicSql NVARCHAR(MAX) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
		INDEX IX_DependentObject_Level NONCLUSTERED (level, dependentObjectId)
	);

	-- Enhanced initial dependency detection
	INSERT INTO #DependentObject (dependentObjectName, isSchemaBound, dependentObjectId, level)
	SELECT DISTINCT
		CONCAT('"', OBJECT_SCHEMA_NAME(dep.referencing_id), '"."', OBJECT_NAME(dep.referencing_id), '"') AS dependentObjectName,
		dep.is_schema_bound_reference AS isSchemaBound,
		dep.referencing_id AS dependentObjectId,
		1 AS level
	FROM (
		-- Unified dependency query using modern SQL features
		SELECT DISTINCT
			sed.referencing_id,
			sed.is_schema_bound_reference
		FROM sys.sql_expression_dependencies sed
		INNER JOIN #ObjectListDetails old ON sed.referenced_id = old.objectId
		WHERE (@isSchemaBoundOnly = 0 OR sed.is_schema_bound_reference = 1)
			AND sed.referencing_id <> old.objectId
		
		UNION
		
		SELECT DISTINCT
			sdd.referencing_id,
			CAST(0 AS BIT) as is_schema_bound_reference
		FROM sys.sql_dependencies sdd
		INNER JOIN #ObjectListDetails old ON sdd.referenced_major_id = old.objectId
		WHERE @isSchemaBoundOnly = 0
			AND sdd.referencing_id <> old.objectId
			AND NOT EXISTS (
				SELECT 1 FROM sys.sql_expression_dependencies sed2 
				WHERE sed2.referencing_id = sdd.referencing_id 
				AND sed2.referenced_id = sdd.referenced_major_id
			)
	) dep;

	-- Enhanced dependency level processing
	WHILE (@@ROWCOUNT > 0 AND @level < 20)
	BEGIN;
		SET @level = @level + 1;
		
		INSERT INTO #DependentObject (dependentObjectName, isSchemaBound, dependentObjectId, level)
		SELECT DISTINCT
			CONCAT('"', OBJECT_SCHEMA_NAME(dep.referencing_id), '"."', OBJECT_NAME(dep.referencing_id), '"'),
			dep.is_schema_bound_reference,
			dep.referencing_id,
			@level
		FROM (
			SELECT DISTINCT
				sed.referencing_id,
				sed.is_schema_bound_reference
			FROM sys.sql_expression_dependencies sed
			INNER JOIN #DependentObject existing ON sed.referenced_id = existing.dependentObjectId
			WHERE existing.level = @level - 1
				AND (@isSchemaBoundOnly = 0 OR sed.is_schema_bound_reference = 1)
				AND NOT EXISTS (
					SELECT 1 FROM #DependentObject existing2 
					WHERE existing2.dependentObjectId = sed.referencing_id
				)
		) dep;
		
		IF (@onlyIncludeDirectDependencies = 1)
			BREAK;
	END;

	-- Enhanced SQL generation using modern features
	UPDATE #DependentObject SET 
		isView = CASE WHEN o.[type] = 'V' THEN 1 ELSE 0 END,
		dynamicSql = CONCAT(
			'EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = ''',
			dependentObjectName,
			''', @newIsSchemaBound = 0;'
		)
	FROM #DependentObject do
	INNER JOIN sys.objects o ON o.object_id = do.dependentObjectId;

	-- Enhanced output generation using STRING_AGG for better performance
	IF (@mode = @variableMode)
	BEGIN;
		-- Generate unbind SQL using STRING_AGG
		SELECT @unbindSql = STRING_AGG(
			CONCAT(do.dynamicSql, CHAR(13), CHAR(10)), 
			''
		) WITHIN GROUP (ORDER BY do.level DESC, do.dependentObjectName)
		FROM #DependentObject do;

		-- Generate rebind SQL using STRING_AGG
		SELECT @rebindSql = STRING_AGG(
			CONCAT(
				'EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = ''',
				do.dependentObjectName,
				''', @newIsSchemaBound = 1;',
				CHAR(13), CHAR(10)
			), 
			''
		) WITHIN GROUP (ORDER BY do.level ASC, do.dependentObjectName)
		FROM #DependentObject do;
	END
	ELSE
	BEGIN;
		-- Print mode with enhanced formatting
		PRINT '-- Enhanced Unbind Dependencies (Execute in Order):';
		PRINT CONCAT('-- Total dependent objects found: ', @@ROWCOUNT);
		PRINT '';
		
		DECLARE cursor_unbind CURSOR FOR
		SELECT dynamicSql
		FROM #DependentObject
		ORDER BY level DESC, dependentObjectName;
		
		OPEN cursor_unbind;
		FETCH NEXT FROM cursor_unbind INTO @printString;
		
		WHILE @@FETCH_STATUS = 0
		BEGIN;
			PRINT @printString;
			FETCH NEXT FROM cursor_unbind INTO @printString;
		END;
		
		CLOSE cursor_unbind;
		DEALLOCATE cursor_unbind;
		
		PRINT '';
		PRINT '-- Enhanced Rebind Dependencies (Execute in Reverse Order):';
		PRINT '';
		
		DECLARE cursor_rebind CURSOR FOR
		SELECT CONCAT(
			'EXEC DBA.hsp_ToggleSchemaBinding_enhanced @objectName = ''',
			dependentObjectName,
			''', @newIsSchemaBound = 1;'
		)
		FROM #DependentObject
		ORDER BY level ASC, dependentObjectName;
		
		OPEN cursor_rebind;
		FETCH NEXT FROM cursor_rebind INTO @printString;
		
		WHILE @@FETCH_STATUS = 0
		BEGIN;
			PRINT @printString;
			FETCH NEXT FROM cursor_rebind INTO @printString;
		END;
		
		CLOSE cursor_rebind;
		DEALLOCATE cursor_rebind;
	END;

	-- Cleanup
	DROP TABLE #ObjectListDetails;
	DROP TABLE #DependentObject;
END;
GO

PRINT 'DBA.hsp_ToggleSchemaBindingBatch_enhanced installed successfully.';
PRINT '';
PRINT 'Enhanced procedures installation complete!';
PRINT '';
PRINT 'Key SQL Server 2017+ enhancements implemented:';
PRINT '- CONCAT function for improved string concatenation performance';
PRINT '- IIF function for optimized conditional logic';
PRINT '- STRING_AGG for efficient string aggregation';
PRINT '- STRING_SPLIT for enhanced parsing';
PRINT '- Optimized CTEs and query patterns';
PRINT '- Enhanced error handling with modern patterns';
PRINT '- Improved indexing strategies for temp tables';
PRINT '';
GO