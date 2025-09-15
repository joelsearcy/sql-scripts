#!/bin/bash
# Run tests against all SQL Server versions

echo "Running ToggleSchemabinding tests against all SQL Server versions..."
echo "===================================================================="

# Load environment
source "$(dirname "$0")/.env.test"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/test-results"
mkdir -p "$RESULTS_DIR"

# Function to run SQL script
run_sql_script() {
    local server=$1
    local port=$2
    local script_path=$3
    local output_file=$4
    
    echo "Running $script_path on $server..."
    docker exec ${server} /opt/mssql-tools18/bin/sqlcmd \
        -S localhost \
        -U SA \
        -P "$SA_PASSWORD" \
        -i "/scripts/$script_path" \
        -o "/test-results/$output_file" \
        -e -W -C
}

# Function to run SQL script from /tmp/ directory
run_tmp_sql_script() {
    local server=$1
    local port=$2
    local script_path=$3
    local output_file=$4
    local db_name=$5
    
    echo "Running $script_path on $server..."
    docker exec ${server} /opt/mssql-tools18/bin/sqlcmd \
        -S localhost \
        -U SA \
        -P "$SA_PASSWORD" \
        -i "/tmp/$script_path" \
        -o "/test-results/$output_file" \
        -d "$db_name" \
        -e -W -C
}

# Create test databases on all instances
echo "Setting up test databases..."

# First, initialize databases and schemas
run_sql_script "sqlserver-2019-test" "1419" "00-initialize-database.sql" "init-2019.log"
run_sql_script "sqlserver-2022-test" "1422" "00-initialize-database.sql" "init-2022.log"
run_sql_script "sqlserver-2025-test" "1425" "00-initialize-database.sql" "init-2025.log"

# Then create the complex schema objects
run_sql_script "sqlserver-2019-test" "1419" "01-setup-complex-enterprise-schema.sql" "setup-2019.log"
run_sql_script "sqlserver-2022-test" "1422" "01-setup-complex-enterprise-schema.sql" "setup-2022.log"
run_sql_script "sqlserver-2025-test" "1425" "01-setup-complex-enterprise-schema.sql" "setup-2025.log"

# Install procedures on each version
echo "Installing procedures..."

# Create ToggleSchemabinding procedures on all instances
run_sql_script "sqlserver-2019-test" "1419" "02-setup-toggle-schemabinding.sql" "install-2019.log"
run_sql_script "sqlserver-2022-test" "1422" "02-setup-toggle-schemabinding.sql" "install-2022.log"
run_sql_script "sqlserver-2025-test" "1425" "02-setup-toggle-schemabinding.sql" "install-2025.log"

# Run performance tests
echo "Running performance tests..."
echo "EXEC Performance.sp_RunPerformanceTests 'SQL Server 2019', 'SQL2019', 30, 1" > /tmp/perf_test_2019.sql
echo "EXEC Performance.sp_RunPerformanceTests 'SQL Server 2022', 'SQL2022', 30, 1" > /tmp/perf_test_2022.sql
echo "EXEC Performance.sp_RunPerformanceTests 'SQL Server 2025', 'SQL2025', 30, 1" > /tmp/perf_test_2025.sql

# Copy test scripts to containers and run
docker cp /tmp/perf_test_2019.sql sqlserver-2019-test:/tmp/
docker cp /tmp/perf_test_2022.sql sqlserver-2022-test:/tmp/
docker cp /tmp/perf_test_2025.sql sqlserver-2025-test:/tmp/

run_tmp_sql_script "sqlserver-2019-test" "1419" "perf_test_2019.sql" "performance-2019.log" "SchemabindingTestDB"
run_tmp_sql_script "sqlserver-2022-test" "1422" "perf_test_2022.sql" "performance-2022.log" "SchemabindingTestDB"
run_tmp_sql_script "sqlserver-2025-test" "1425" "perf_test_2025.sql" "performance-2025.log" "SchemabindingTestDB"

# Run correctness validation
echo "Running correctness validation..."
echo "EXEC Validation.sp_RunCorrectnessValidation 'SQL Server 2019', 'SQL2019'" > /tmp/validation_2019.sql
echo "EXEC Validation.sp_RunCorrectnessValidation 'SQL Server 2022', 'SQL2022'" > /tmp/validation_2022.sql
echo "EXEC Validation.sp_RunCorrectnessValidation 'SQL Server 2025', 'SQL2025'" > /tmp/validation_2025.sql

docker cp /tmp/validation_2019.sql sqlserver-2019-test:/tmp/
docker cp /tmp/validation_2022.sql sqlserver-2022-test:/tmp/
docker cp /tmp/validation_2025.sql sqlserver-2025-test:/tmp/

run_tmp_sql_script "sqlserver-2019-test" "1419" "validation_2019.sql" "validation-2019.log" "SchemabindingTestDB"
run_tmp_sql_script "sqlserver-2022-test" "1422" "validation_2022.sql" "validation-2022.log" "SchemabindingTestDB"
run_tmp_sql_script "sqlserver-2025-test" "1425" "validation_2025.sql" "validation-2025.log" "SchemabindingTestDB"

echo ""
echo "All tests completed!"
echo "Results are available in: $RESULTS_DIR"
echo ""
echo "To view results:"
echo "  ls -la $RESULTS_DIR"
echo "  cat $RESULTS_DIR/performance-*.log"
echo "  cat $RESULTS_DIR/validation-*.log"
