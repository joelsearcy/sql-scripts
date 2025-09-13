SET ANSI_NULL_DFLT_ON ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

PRINT SYSDATETIMEOFFSET();


DECLARE @objectId INT = OBJECT_ID('Foo.Bar');
DECLARE @dynamicSql NVARCHAR(MAX) = NULL;
DECLARE @newLineCharacter CHAR(2) = CAST(0x0D0A AS CHAR(2));

PRINT @objectId;

DECLARE Temp_CURSOR CURSOR FAST_FORWARD LOCAL FOR
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
		Computed.indexName, @newLineCharacter, 'ON ',
		Computed.objectName, @newLineCharacter, Computed.indexedColumns,
		ISNULL(@newLineCharacter + 'INCLUDE' + @newLineCharacter + Computed.includedColumns, ''),
		ISNULL(@newLineCharacter + 'WHERE ' + Computed.filterDefinition, ''),
		@newLineCharacter, 'WITH ', indexProperties, ';', @newLineCharacter, @newLineCharacter
	) AS dynamicSql
FROM
	sys.partitions
	INNER JOIN sys.indexes
		ON partitions.object_id = indexes.object_id
			AND partitions.index_id = indexes.index_id
	INNER JOIN sys.objects
		ON indexes.object_id = objects.object_id
	CROSS APPLY
	(
		SELECT 
			CONCAT(QUOTENAME(SCHEMA_NAME(objects.schema_id), '['), '.', QUOTENAME(objects.name, '[')) AS objectName,
			QUOTENAME(indexes.name, '[') AS indexName,
			indexes.filter_definition AS filterDefinition,
			REPLACE(CONCAT('(', STUFF(KeyColumn.value, 1, 1, '') + @newLineCharacter, ')'), '^', @newLineCharacter + '	')  AS indexedColumns,
			KeyColumn.value AS keyColumnsRaw,
			IIF(IncludedColumn.value IS NOT NULL, REPLACE(CONCAT('(', STUFF(IncludedColumn.value, 1, 1, ''), @newLineCharacter, ')'), '^', @newLineCharacter + '	'), NULL) AS includedColumns,
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
						(9, 'FILLFACTOR','IndexFillFactor', indexes.fill_factor, CAST(NULL AS BIT)),
						(10, 'DATA_COMPRESSION', NULL, NULLIF(partitions.data_compression_desc, 'NONE'), CAST(NULL AS BIT))
					) AS IndexProperties (displayOrder, propertyName, propertyLookup, propertyValue, isYesNo)
				WHERE
					IndexProperties.propertyName NOT IN ('FILLFACTOR', 'DATA_COMPRESSION')
					OR
					(
						IndexProperties.propertyName = 'FILLFACTOR'
						AND ISNULL(INDEXPROPERTY(indexes.object_id, indexes.name, IndexProperties.propertyLookup), 0) <> 0
					)
					OR
					(
						IndexProperties.propertyName = 'DATA_COMPRESSION'
						AND IndexProperties.propertyValue IS NOT NULL
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
	AND 
	(
		indexes.object_id = @objectId
		OR @objectId IS NULL
	)
ORDER BY
	indexes.object_id,
	indexes.index_id;

OPEN Temp_CURSOR;

FETCH NEXT FROM Temp_CURSOR
INTO @dynamicSql;

WHILE (@@FETCH_STATUS = 0)
BEGIN
	PRINT @dynamicSql;

	SET @dynamicSql = NULL;
	
	FETCH NEXT FROM Temp_CURSOR
	INTO @dynamicSql;
END;

CLOSE Temp_CURSOR;
DEALLOCATE Temp_CURSOR;



ROLLBACK TRANSACTION;
--COMMIT WORK;