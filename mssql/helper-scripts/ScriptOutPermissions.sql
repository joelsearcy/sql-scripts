SELECT
	database_principals.name,
	PermissionStatement.permissionStatement,
	database_principals.type_desc AS principal_type_desc
FROM
	sys.database_principals
	CROSS APPLY
	(
		SELECT
			database_permissions.major_id,
			database_permissions.class,
			database_permissions.state_desc,
			database_permissions.permission_name,
			MIN(database_permissions.minor_id) AS minor_id
		FROM sys.database_permissions
		WHERE
			database_principals.principal_id = database_permissions.grantee_principal_id
			--AND database_permissions.minor_id <> 0
			AND database_permissions.class IN (0 /*Database*/, 1 /*Object/Column*/, 3 /*Schema*/, 6 /*Type*/, 10 /*XML Schema Collection*/)
		GROUP BY
			database_permissions.major_id,
			database_permissions.class,
			database_permissions.state_desc,
			database_permissions.permission_name
	) AS DatabasePermission
	OUTER APPLY
	(
		SELECT
			RIGHT(XmlResult.listString, LEN(XmlResult.listString) - 2) AS columnList
		FROM
			(
				SELECT
					', ' + columns.name
				FROM 
					sys.database_permissions AS ColumnPermission
					INNER JOIN sys.columns
						ON ColumnPermission.major_id = columns.object_id
							AND ColumnPermission.minor_id = columns.column_id
				WHERE
					ColumnPermission.grantee_principal_id = database_principals.principal_id
					AND ColumnPermission.major_id = DatabasePermission.major_id
					AND ColumnPermission.state_desc = DatabasePermission.state_desc
					AND DatabasePermission.minor_id <> 0
				ORDER BY
					columns.column_id
				FOR XML PATH('')
			) AS XmlResult (listString)
	) AS ColumnList
	OUTER APPLY
	(
		SELECT
			CONCAT('SCHEMA::', QUOTENAME(schemas.name, '[')) AS entityName
		FROM sys.schemas
		WHERE
			schemas.schema_id = DatabasePermission.major_id
			AND DatabasePermission.class = 3 /*Schema*/

		UNION ALL

		SELECT
			CONCAT(Entity.typeName, QUOTENAME(schemas.name, '['), '.', QUOTENAME(Entity.name, '[')) AS entityName
		FROM
			(
				SELECT
					'TYPE::' AS typeName,
					types.name,
					types.schema_id
				FROM sys.types
				WHERE
					types.user_type_id = DatabasePermission.major_id
					AND DatabasePermission.class = 6 /*Type*/

				UNION ALL

				SELECT
					'XML SCHEMA COLLECTION::' AS typeName,
					xml_schema_collections.name,
					xml_schema_collections.schema_id
				FROM sys.xml_schema_collections
				WHERE
					xml_schema_collections.xml_collection_id = DatabasePermission.major_id
					AND DatabasePermission.class = 10 /*XML Schema Collection*/
				
				UNION ALL

				SELECT
					'' AS typeName,
					objects.name,
					objects.schema_id
				FROM sys.objects
				WHERE 
					objects .object_id = DatabasePermission.major_id
					AND DatabasePermission.class = 1 /*OBJECT_OR_COLUMN*/
			) AS Entity
			INNER JOIN sys.schemas
				ON Entity.schema_id = schemas.schema_id

		UNION ALL

		SELECT
			'UNKOWN' AS entityName
		WHERE
			DatabasePermission.class NOT IN (0 /*Database*/, 1 /*Object/Column*/, 3 /*Schema*/, 6 /*Type*/, 10 /*XML Schema Collection*/)
	) AS DatabaseObject
	CROSS APPLY
	(
		SELECT
			CONCAT
			(
				DatabasePermission.state_desc, ' ',
				DatabasePermission.permission_name,
				(' (' + ColumnList.columnList + ')'),
				(' ON ' + DatabaseObject.entityName),
				' TO ', QUOTENAME(database_principals.name, '['), ';'
					COLLATE Latin1_General_CI_AS_KS_WS
			)  AS permissionStatement
	) AS PermissionStatement
WHERE
	DatabasePermission.major_id >= 0 /*Exclude system objects*/
	--AND database_principals.name = 'login';
	AND DatabasePermission.major_id = OBJECT_ID('name');