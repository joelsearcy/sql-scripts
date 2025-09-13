SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
--SELECT *
--FROM
--	sys.dm_db_missing_index_group_stats
--	INNER JOIN sys.dm_db_missing_index_groups
--		ON dm_db_missing_index_group_stats.group_handle = dm_db_missing_index_groups.index_group_handle
--	INNER JOIN sys.dm_db_missing_index_details
--		ON dm_db_missing_index_groups.index_handle = dm_db_missing_index_details.index_handle
--WHERE
--	dm_db_missing_index_group_stats.avg_system_impact > 80
--	--AND last_user_seek > DATEADD(DAY, -1, SYSDATETIME())
	
SELECT *
FROM
	sys.dm_db_missing_index_group_stats
	INNER JOIN sys.dm_db_missing_index_groups
		ON dm_db_missing_index_group_stats.group_handle = dm_db_missing_index_groups.index_group_handle
	INNER JOIN sys.dm_db_missing_index_details
		ON dm_db_missing_index_groups.index_handle = dm_db_missing_index_details.index_handle
WHERE
	--dm_db_missing_index_group_stats.avg_user_impact > 80
	--AND avg_total_user_cost > 50
	--AND last_user_seek > DATEADD(DAY, -3, SYSDATETIME())

	dm_db_missing_index_details.object_id = OBJECT_ID('')
	


SELECT *
FROM
	sys.dm_db_missing_index_group_stats
	INNER JOIN sys.dm_db_missing_index_groups
		ON dm_db_missing_index_group_stats.group_handle = dm_db_missing_index_groups.index_group_handle
	INNER JOIN sys.dm_db_missing_index_details
		ON dm_db_missing_index_groups.index_handle = dm_db_missing_index_details.index_handle
	INNER JOIN sys.objects
		ON dm_db_missing_index_details.object_id = objects.object_id
WHERE
	--dm_db_missing_index_group_stats.avg_user_impact > 80
	--AND avg_total_user_cost > 50
	--AND last_user_seek > DATEADD(DAY, -3, SYSDATETIME())

	objects.schema_id = SCHEMA_ID('')