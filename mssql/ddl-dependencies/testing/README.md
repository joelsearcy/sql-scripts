# ToggleSchemabinding Docker Testing Environment

## Overview

This Docker-based testing infrastructure validates the ToggleSchemabinding procedures across multiple SQL Server versions (2019, 2022, 2025) in isolated containers. The environment provides automated setup, execution, and comparison of performance and correctness tests.

## Quick Start

### Prerequisites

- **Docker & Docker Compose** installed
- **8GB+ RAM** available (recommended)
- **10GB+ disk space**
- **Linux/macOS/WSL2** environment

### Setup & Run Tests

```bash
# Navigate to testing directory
cd mssql/ddl-dependencies/testing

# Run setup to start docker containers and created additional scripts
./setup-docker-test-environment.sh

# Run complete test suite across all versions
./run-all-tests.sh
```

This will:
1. `setup-docker-test-environment.sh`
   1. Create Docker Compose configuration
   2. Start 3 SQL Server containers (2019, 2022, 2025)
2. `run-all-tests.sh`
   1. Set up test databases and schemas
   2. Install ToggleSchemabinding procedures
   3. Run performance and validation tests
   4. Generate test results

## Environment Components

### Docker Containers

| Container | SQL Server Version | Port |
|-----------|-------------------|------|
| `sqlserver-2019-test` | 2019-latest | 1419 |
| `sqlserver-2022-test` | 2022-latest | 1422 |
| `sqlserver-2025-test` | 2025-latest | 1425 |

### Key Files

#### Setup Scripts
- **`setup-docker-test-environment.sh`** - Main setup script
- **`test-connections.sh`** - Verifies container connectivity
- **`run-all-tests.sh`** - Executes full test suite
- **`stop-test-environment.sh`** - Stops all containers
- **`cleanup-test-environment.sh`** - Complete cleanup

#### SQL Scripts  
- **`00-initialize-database.sql`** - Creates database and schemas
- **`01-setup-complex-enterprise-schema.sql`** - Creates test objects with dependencies
- **`02-setup-toggle-schemabinding.sql`** - Installs ToggleSchemabinding procedures

#### Configuration Files
- **`docker-compose.test.yml`** - Container configuration (generated)
- **`.env.test`** - Environment variables (generated)

## Test Schema Architecture

The test environment creates a complex enterprise schema with:

### Core Schemas
- **Core** - Base tables (Companies, Employees, Customers, Orders)
- **Financial** - Financial data and calculations  
- **Audit** - Audit trails and logging
- **Analytics** - Business intelligence views
- **Sales** - Sales reporting and analysis

### Advanced Schemas  
- **Executive** - Executive dashboards
- **Research** - Market research and analysis
- **Strategy** - Strategic planning views
- **Risk** - Risk management functions
- **Governance** - Governance and compliance

### Testing Infrastructure
- **Performance** - Performance test tables and procedures
- **Validation** - Correctness validation framework
- **DBA** - Database administration utilities

### Dependency Chain Design

The schema creates a deliberate dependency hierarchy:

```
Level 0: Base functions (no dependencies)
├── Core.fn_GetEmployeeFullName
├── Financial.fn_GetAccountBalance
└── Sales.fn_GetCustomerAnalytics

Level 1: Functions depending on Level 0
├── Core.fn_GetCompanyEmployees  
├── Financial.fn_GetAccountSummary
└── Analytics.fn_GetCompanyMetrics

Level 2: Views depending on Level 1
├── Core.vw_EmployeeDetails
├── Financial.vw_AccountHierarchy  
└── Analytics.vw_CompanyPerformance

Level 3+: Complex multi-dependency objects
├── Executive.vw_ExecutiveDashboard
├── Research.vw_MarketAnalysis
└── Strategy.vw_InvestmentOpportunities
```

## Usage Examples

### Manual Container Management

```bash
# Start environment
./setup-docker-test-environment.sh

# Test connectivity
./test-connections.sh

# Stop environment  
./stop-test-environment.sh

# Complete cleanup (removes all data)
./cleanup-test-environment.sh
```

### Direct SQL Server Access

```bash
# Connect to SQL Server 2019
docker exec -it sqlserver-2019-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C

# Connect to SQL Server 2022  
docker exec -it sqlserver-2022-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C

# Connect to SQL Server 2025
docker exec -it sqlserver-2025-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C
```

### Host Machine Connections

```bash
# Using sqlcmd from host (if installed)
sqlcmd -S localhost,1419 -U SA -P "$SA_PASSWORD" --env-file .env.test -C -Q "SELECT @@VERSION"
sqlcmd -S localhost,1422 -U SA -P "$SA_PASSWORD" --env-file .env.test -C -Q "SELECT @@VERSION"  
sqlcmd -S localhost,1425 -U SA -P "$SA_PASSWORD" --env-file .env.test -C -Q "SELECT @@VERSION"
```

## Test Execution

### Automated Test Suite

```bash
# Run complete test suite across all versions
./run-all-tests.sh
```

This executes:
1. **Database Initialization** (`00-initialize-database.sql`)
2. **Schema Creation** (`01-setup-complex-enterprise-schema.sql`)  
3. **Procedure Installation** (`02-setup-toggle-schemabinding.sql`)
4. **Performance Tests** (30 objects across dependency levels)
5. **Validation Tests** (Schema binding consistency checks)

### Manual Test Execution

```bash
# Performance test on SQL Server 2022
docker exec sqlserver-2022-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C \
    -Q "USE SchemaBindingTestDB; EXEC Performance.sp_RunPerformanceTests 'SQL Server 2022', 'SQL2022', 30, 1"

# Validation test on SQL Server 2025
docker exec sqlserver-2025-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C \
    -Q "USE SchemaBindingTestDB; EXEC Validation.sp_RunCorrectnessValidation 'SQL Server 2025', 'SQL2025'"
```

## Test Results Analysis

### Result Files Location

Test results are generated in the `test-results/` directory:

```
test-results/
├── initialization-2019.log        # Database setup results
├── initialization-2022.log
├── initialization-2025.log
├── schema-setup-2019.log          # Schema creation results
├── schema-setup-2022.log
├── schema-setup-2025.log
├── procedure-install-2019.log     # Procedure installation results
├── procedure-install-2022.log
├── procedure-install-2025.log
├── performance-2019.log           # Performance test results
├── performance-2022.log
├── performance-2025.log
├── validation-2019.log            # Validation test results
├── validation-2022.log
└── validation-2025.log
```

### Performance Test Results

Each performance test processes 30 objects in dependency order and reports:

```
Starting Performance Test: SQL Server 2022 (Test ID: 1)
  ✓ Tested: [Core].[fn_GetEmployeeFullName] (8ms)
  ✓ Tested: [Financial].[fn_GetAccountBalance] (9ms)
  ✗ Failed: [Research].[vw_MarketAnalysis] - Cannot schema bind...
  ...
Performance Test Summary:
- Total Objects: 30
- Successful: 23 (77%)  
- Failed: 7 (23%)
- Total Duration: 748ms
- Test Status: FAILED (expected due to dependency chain breaks)
```

### Validation Test Results

Validation tests check schema binding consistency:

```
Starting Validation Test: SQL Server 2022
✓ Schema Binding Consistency: 32 objects validated successfully
✓ Dependency Chain Ordering: All chains have reasonable depth (1-15 levels)
✗ Required Procedures: DBA.sp_AnalyzeDependencies not found

Validation Summary:
- Total Validations: 3
- Passed: 2 (67%)
- Failed: 1 (33%)
- Overall Status: WARNING
```

### Cross-Version Comparison

Expected results show version-specific performance characteristics:

| Metric | SQL Server 2019 | SQL Server 2022 | SQL Server 2025 |
|--------|-----------------|-----------------|-----------------|
| **Total Duration** | ~670ms | ~748ms | ~750ms |
| **Success Rate** | 23/30 (77%) | 23/30 (77%) | 23/30 (77%) |
| **Consistency** | ✓ Identical | ✓ Identical | ✓ Identical |
| **Performance** | Fastest | 12% slower | Similar to 2022 |

## Troubleshooting

### Container Issues

```bash
# Check container status
docker ps -a

# View container logs
docker logs sqlserver-2019-test
docker logs sqlserver-2022-test  
docker logs sqlserver-2025-test

# Check Docker Compose status
docker-compose -f docker-compose.test.yml --env-file .env.test ps
```

### Connection Issues

```bash
# Test container health
docker exec sqlserver-2019-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C -Q "SELECT 1"

# Check port availability
netstat -an | grep 1419
netstat -an | grep 1422
netstat -an | grep 1425
```

### Permission Issues

```bash
# Fix data directory permissions
sudo chmod -R 777 data/ logs/ test-results/

# Remove containers and rebuild
./cleanup-test-environment.sh
./setup-docker-test-environment.sh
```

### Performance Issues

```bash
# Check available memory
free -h

# Check Docker resource usage
docker stats

# Reduce containers if needed
docker-compose -f docker-compose.test.yml --env-file .env.test \
    stop sqlserver-2025-test
```

## Customization

### Environment Variables

Edit `.env.test` to customize:

```bash
SA_PASSWORD=StrongPassword123!
SQL_2019_PORT=1419
SQL_2022_PORT=1422  
SQL_2025_PORT=1425
SCRIPTS_PATH=/path/to/your/scripts
```

### Adding Test Objects

Modify `01-setup-complex-enterprise-schema.sql` to add:

```sql
-- New test function
CREATE FUNCTION YourSchema.fn_YourTestFunction(@param INT)
RETURNS INT
WITH SCHEMABINDING  -- or without to test toggle functionality
AS
BEGIN
    RETURN @param * 2
END
GO
```

### Custom Test Parameters

Modify test calls in `run-all-tests.sh`:

```bash
# Change number of objects tested (default: 30)
EXEC Performance.sp_RunPerformanceTests 'SQL Server 2022', 'SQL2022', 50, 1

# Add custom test identifier
EXEC Validation.sp_RunCorrectnessValidation 'SQL Server 2022', 'CustomTest_2022'
```

## Cleanup

### Temporary Cleanup
```bash
# Stop containers but keep data
./stop-test-environment.sh
```

### Complete Cleanup
```bash
# Remove everything including data
./cleanup-test-environment.sh
```

### Manual Cleanup
```bash
# Remove containers
docker-compose -f docker-compose.test.yml --env-file .env.test down -v

# Remove data directories
rm -rf data/ logs/ test-results/

# Remove configuration files
rm -f docker-compose.test.yml .env.test sqlcmd.conf
```

## Advanced Usage

### Running Specific Tests

```bash
# Only performance tests
docker exec sqlserver-2022-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C \
    -i "/scripts/performance-test-2022.sql"

# Only validation tests  
docker exec sqlserver-2025-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C \
    -i "/scripts/validation-test-2025.sql"
```

### Debugging Failed Tests

```bash
# Check specific object schema binding status
docker exec sqlserver-2019-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C \
    -Q "USE SchemaBindingTestDB; 
        SELECT name, is_schema_bound 
        FROM sys.sql_modules m 
        JOIN sys.objects o ON m.object_id = o.object_id 
        WHERE o.name = 'YourObjectName'"
```

### Performance Monitoring

```bash
# Monitor resource usage during tests
watch docker stats

# Check SQL Server performance counters
docker exec sqlserver-2022-test /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U SA -P "$SA_PASSWORD" --env-file .env.test -C \
    -Q "SELECT * FROM sys.dm_os_performance_counters 
        WHERE counter_name LIKE '%Batch Requests%'"
```

This Docker testing environment provides a comprehensive, automated way to validate ToggleSchemabinding functionality across multiple SQL Server versions with consistent, reproducible results.