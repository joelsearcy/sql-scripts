#!/bin/bash
# Test connections to all SQL Server instances

echo "Testing SQL Server connections..."
echo "================================="

# Load environment
source "$(dirname "$0")/.env.test"

echo "SQL Server 2019 (localhost:1419):"
docker exec sqlserver-2019-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT 'SQL Server 2019: ' + @@VERSION"
echo ""

echo "SQL Server 2022 (localhost:1422):"
docker exec sqlserver-2022-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT 'SQL Server 2022: ' + @@VERSION"
echo ""

echo "SQL Server 2025 (localhost:1425):"
docker exec sqlserver-2025-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT 'SQL Server 2025: ' + @@VERSION"
echo ""
