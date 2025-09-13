SET NOEXEC OFF;
SET ANSI_NULL_DFLT_ON ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;


SELECT
	indexes.fill_factor,
	Computed.adjustedFillFactor,
	CONCAT('ALTER INDEX ', QUOTENAME(indexes.name), ' ON ', QUOTENAME(OBJECT_SCHEMA_NAME(objects.object_id)), '.', QUOTENAME(objects.name), ' REBUILD WITH (MAXDOP = 16, ONLINE = ON, SORT_IN_TEMPDB = ON);'),
	CONCAT('ALTER INDEX ', QUOTENAME(indexes.name), ' ON ', QUOTENAME(OBJECT_SCHEMA_NAME(objects.object_id)), '.', QUOTENAME(objects.name), ' REBUILD WITH (FILLFACTOR = ', Computed.adjustedFillFactor, ', MAXDOP = 16, ONLINE = ON, SORT_IN_TEMPDB = ON);'),
	page_count,
	avg_fragmentation_in_percent,
	*
FROM
	sys.objects
	INNER JOIN
	(
		--SELECT
		--	CONCAT(OBJECT_SCHEMA_NAME(key_constraints.object_id), '.', OBJECT_NAME(key_constraints.object_id)) AS objectName,
		--	key_constraints.name,
		--	key_constraints.object_id,
		--	key_constraints.unique_index_id AS index_id,
		--	--CAST(0 AS INT) AS index_id,
		--	CAST(0 AS BIT) AS has_filter,
		--	CAST(NULL AS TINYINT) AS fill_factor,
		--	CAST(0 AS BIT) AS is_padded
		--FROM sys.key_constraints

		--UNION ALL

		SELECT
			CONCAT(OBJECT_SCHEMA_NAME(indexes.object_id), '.', OBJECT_NAME(indexes.object_id)) AS objectName,
			indexes.name,
			indexes.object_id,
			indexes.index_id,
			indexes.has_filter,
			indexes.fill_factor,
			indexes.is_padded
		FROM sys.indexes
	) AS indexes
		ON objects.object_id = indexes.object_id
	CROSS APPLY sys.dm_db_index_physical_stats (DB_ID(), indexes.object_id, indexes.index_id, NULL, NULL)
	--CROSS APPLY sys.dm_db_index_physical_stats (DB_ID(), indexes.object_id, -1, NULL, NULL)
	CROSS APPLY
	(
		SELECT
			IIF
			(
				indexes.fill_factor = 0,
				CASE
					WHEN dm_db_index_physical_stats.avg_fragmentation_in_percent <= 10 THEN 90
					WHEN dm_db_index_physical_stats.avg_fragmentation_in_percent > 10 AND dm_db_index_physical_stats.avg_fragmentation_in_percent <= 25 THEN 85
					WHEN dm_db_index_physical_stats.avg_fragmentation_in_percent > 25 AND dm_db_index_physical_stats.avg_fragmentation_in_percent <= 50 THEN 80
					ELSE 75
				END,
				CAST(indexes.fill_factor * 0.85 AS INT)
			) AS adjustedFillFactor
		WHERE
			page_count >= 1000

		UNION ALL
		
		SELECT
			IIF
			(
				indexes.fill_factor = 0,
				CASE
					WHEN dm_db_index_physical_stats.avg_fragmentation_in_percent <= 60 THEN 95
					WHEN dm_db_index_physical_stats.avg_fragmentation_in_percent > 60 AND dm_db_index_physical_stats.avg_fragmentation_in_percent <= 75 THEN 90
					WHEN dm_db_index_physical_stats.avg_fragmentation_in_percent > 75 AND dm_db_index_physical_stats.avg_fragmentation_in_percent <= 90 THEN 85
					ELSE 80
				END,
				CAST(indexes.fill_factor * 0.95 AS INT)
			) AS adjustedFillFactor
		WHERE
			page_count < 1000
	) AS Computed
WHERE
	objects.schema_id NOT IN
	(
		ISNULL(SCHEMA_ID(''), 0)
	)

--	indexes.index_id <> 0
--	AND indexes.is_disabled = 0

	--AND avg_fragmentation_in_percent > 15
	--AND page_count >= 1000

	--AND avg_fragmentation_in_percent > 40
	--AND page_count > 500
	--AND page_count < 1000

	--AND
	--(
	--	indexes.fill_factor = 0
	--	OR indexes.fill_factor > 90
	--)
ORDER BY
	OBJECT_SCHEMA_NAME(objects.object_id),
	objects.name,
	indexes.name