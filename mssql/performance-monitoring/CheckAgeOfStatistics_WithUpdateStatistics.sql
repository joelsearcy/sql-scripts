SELECT
	CONCAT('UPDATE STATISTICS ', QUOTENAME(OBJECT_SCHEMA_NAME(stats.object_id)), '.', QUOTENAME(objects.name), ';') AS schema_name,
	--objects.name AS object_name,
	--stats.name AS stats_name,
	MIN(STATS_DATE(stats.object_id, stats.stats_id)) AS statistics_update_date
FROM
	sys.stats
	INNER JOIN sys.objects
		ON stats.object_id = objects.object_id
WHERE
	STATS_DATE(stats.object_id, stats.stats_id) < '2017-01-01'
	AND objects.type NOT IN ('S', 'IT')
	--AND objects.schema_id NOT IN
	--(
	--	SCHEMA_ID('')
	--)
GROUP BY
	OBJECT_SCHEMA_NAME(stats.object_id),
	objects.name
ORDER BY
	statistics_update_date DESC