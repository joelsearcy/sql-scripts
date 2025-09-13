
SELECT
	CONCAT('ALTER TABLE ', Computed.objectName, ' DROP CONSTRAINT ', Computed.foreignKeyName, ';') AS dropConstraint,
	CONCAT('ALTER TABLE ', Computed.objectName, '
	ADD CONSTRAINT ', Computed.foreignKeyName, '
			FOREIGN KEY (', ReferencingColums.referencingColumnNames, ')
				REFERENCES ', Computed.referencedObjectName, ' (', ReferencedColums.referencedColumnNames, ');') AS addConstraint,
	
	CONCAT('ALTER TABLE ', Computed.objectName, ' NOCHECK CONSTRAINT ', Computed.foreignKeyName, ';') AS disableConstraint,
	CONCAT('ALTER TABLE ', Computed.objectName, ' WITH CHECK CHECK CONSTRAINT ', Computed.foreignKeyName, ';') AS enableConstraint,
	-- TOOD: Add alternates with aggregated sets to be run as a single statement.
	CONCAT(Computed.foreignKeyName, ','),
	*
FROM
	sys.foreign_keys
	CROSS APPLY
	(
		SELECT
			CONCAT
			(
				QUOTENAME(OBJECT_SCHEMA_NAME(foreign_keys.parent_object_id)), '.',
				QUOTENAME(OBJECT_NAME(foreign_keys.parent_object_id))
			) AS objectName,
			QUOTENAME(foreign_keys.name) AS foreignKeyName,
			CONCAT
			(
				QUOTENAME(OBJECT_SCHEMA_NAME(foreign_keys.referenced_object_id)), '.',
				QUOTENAME(OBJECT_NAME(foreign_keys.referenced_object_id))
			) AS referencedObjectName
	) AS Computed
	CROSS APPLY
	(
		SELECT
			STUFF(ConcatWS.value, 1, 2, '') AS referencingColumnNames
		FROM
			(
				SELECT
					CONCAT(', ', columns.name)
				FROM
					sys.foreign_key_columns
					INNER JOIN sys.columns
						ON foreign_key_columns.parent_object_id = columns.object_id
							AND foreign_key_columns.parent_column_id = columns.column_id
				WHERE
					foreign_key_columns.constraint_object_id = foreign_keys.object_id
				ORDER BY
					foreign_key_columns.constraint_column_id
				FOR XML PATH ('')
			) AS ConcatWS (value)
	) AS ReferencingColums
	CROSS APPLY
	(
		SELECT
			STUFF(ConcatWS.value, 1, 2, '') AS referencedColumnNames
		FROM
			(
				SELECT
					CONCAT(', ', columns.name)
				FROM
					sys.foreign_key_columns
					INNER JOIN sys.columns
						ON foreign_key_columns.referenced_object_id = columns.object_id
							AND foreign_key_columns.referenced_column_id = columns.column_id
				WHERE
					foreign_key_columns.constraint_object_id = foreign_keys.object_id
				ORDER BY
					foreign_key_columns.constraint_column_id
				FOR XML PATH ('')
			) AS ConcatWS (value)
	) AS ReferencedColums
WHERE
	foreign_keys.referenced_object_id IN
	(
		SELECT
			OBJECT_ID(List.objectName)
		FROM
			(VALUES
				('')
			) AS List (objectName)
		WHERE
			OBJECT_ID(List.objectName) IS NOT NULL
	)