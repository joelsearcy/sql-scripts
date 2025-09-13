SET NOEXEC OFF;
SET ANSI_NULL_DFLT_ON ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @objectName SYSNAME = N'Foo.Bar';
DECLARE @columnName SYSNAME = NULL;
DECLARE @maxNestingLevel INT = 3;
DECLARE @objectId INT = OBJECT_ID(@objectName);
DECLARE @columnId INT =
(
	SELECT columns.column_id
	FROM sys.columns
	WHERE
		columns.object_id = @objectId
		AND columns.name = @columnName
);

WITH Dependency AS
(
	SELECT DISTINCT
		1 AS nestingLevel,
		CAST(FORMAT(DENSE_RANK() OVER (ORDER BY OBJECT_SCHEMA_NAME(sql_expression_dependencies.referencing_id), sql_expression_dependencies.referencing_id), '00') AS NVARCHAR(MAX)) AS path,
		sql_expression_dependencies.referencing_id,
		sql_expression_dependencies.referencing_minor_id,
		sql_expression_dependencies.referencing_class,
		sql_expression_dependencies.referencing_class_desc
	FROM
		sys.sql_expression_dependencies
		LEFT OUTER JOIN sys.objects
			ON sql_expression_dependencies.referencing_id = objects.object_id
		LEFT OUTER JOIN sys.schemas
			ON objects.schema_id = schemas.schema_id
	WHERE
		sql_expression_dependencies.referenced_id = @objectId
		AND sql_expression_dependencies.referencing_class_desc NOT IN ('INDEX')
		AND
		(
			@columnName IS NULL
			OR sql_expression_dependencies.referenced_minor_id IS NULL
			OR sql_expression_dependencies.referenced_minor_id = @columnId
		)
		AND
		(
			objects.object_id IS NULL
			OR objects.type NOT IN ('C','PK','D','F','UQ')
		)
		AND
		(
			schemas.schema_id IS NULL
			OR schemas.name NOT LIKE 'Tests%'
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

	UNION ALL

	SELECT
		Dependency.nestingLevel + 1,
		CAST(CONCAT(Dependency.path, '.', FORMAT(DENSE_RANK() OVER (ORDER BY OBJECT_SCHEMA_NAME(sql_expression_dependencies.referencing_id), sql_expression_dependencies.referencing_id), '00')) AS NVARCHAR(MAX)) AS path,
		sql_expression_dependencies.referencing_id,
		sql_expression_dependencies.referencing_minor_id,
		sql_expression_dependencies.referencing_class,
		sql_expression_dependencies.referencing_class_desc
	FROM
		Dependency
		INNER JOIN sys.sql_expression_dependencies
			ON Dependency.referencing_id = sql_expression_dependencies.referenced_id
	WHERE
		Dependency.nestingLevel < @maxNestingLevel
		AND sql_expression_dependencies.referencing_class_desc NOT IN ('INDEX')
		AND
		(
			OBJECT_SCHEMA_NAME(sql_expression_dependencies.referencing_id) IS NULL
			OR OBJECT_SCHEMA_NAME(sql_expression_dependencies.referencing_id) NOT LIKE 'Tests%'
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
		
)
SELECT DISTINCT
	Dependency.path,
	Dependency.nestingLevel,
	CONCAT('|', REPLICATE('---|', Dependency.nestingLevel)) AS graph,
	ReferenceObject.reference_object,
	ReferenceObject.reference_object_column
FROM
	Dependency
	OUTER APPLY
	(
		SELECT
			CONCAT(OBJECT_SCHEMA_NAME(Dependency.referencing_id), '.', OBJECT_NAME(Dependency.referencing_id)) AS reference_object,
			COL_NAME(Dependency.referencing_id, Dependency.referencing_minor_id) AS reference_object_column
		WHERE
			Dependency.referencing_class = 1 /*OBJECT_OR_COLUMN*/

		UNION ALL

		SELECT
			'Reference class not supported',
			Dependency.referencing_class_desc
		WHERE
			Dependency.referencing_class NOT IN (1 /*OBJECT_OR_COLUMN*/)
	) AS ReferenceObject
ORDER BY
	Dependency.path
OPTION (MAXRECURSION 10000);