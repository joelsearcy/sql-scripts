# SQL Scripts Repository

A collection of SQL Server scripts, tools, and utilities for database administration, performance monitoring, and development automation.

## Repository Structure

### MSSQL Scripts (`mssql/`)

This repository contains SQL Server-specific scripts organized by functionality:

#### DDL Dependencies (`mssql/ddl-dependencies/`)

Advanced database dependency management tools with comprehensive testing infrastructure.

**Core Components:**
- **`DownstreamDependencies.sql`** - Analyzes object dependencies and downstream impacts
- **`ToggleSchemabinding_2017.sql`** - SQL Server 2017+ compatible schema binding toggle utility

**Testing Framework (`mssql/ddl-dependencies/testing/`)**
- **Docker-based multi-version testing** across SQL Server 2019, 2022, and 2025
- **Automated performance benchmarks** comparing schema binding operations
- **Comprehensive validation suite** ensuring cross-version compatibility
- **Enterprise-scale test schema** with 200+ objects and 15+ dependency levels

Key testing scripts:
- `setup-docker-test-environment.sh` - One-command environment setup
- `run-all-tests.sh` - Execute complete test suite
- `01-setup-complex-enterprise-schema.sql` - Creates realistic enterprise test data

#### Helper Scripts (`mssql/helper-scripts/`)

Common database administration utilities:

- **`AnsiHeaders.sql`** - Standardized script headers with ANSI settings
- **`DDLGO_statement.sql`** - DDL batch separator utility
- **`NewScriptTemplate.sql`** - Template for new SQL script creation
- **`ScriptOutDropAndCreateForeignKeysForMultipleObjects.sql`** - Foreign key management automation
- **`ScriptOutIndexes.sql`** - Index definition extraction utility
- **`ScriptOutPermissions.sql`** - Database permission documentation tool

#### Performance Monitoring (`mssql/performance-monitoring/`)

Database performance analysis and optimization tools:

- **`ActiveQueries.sql`** - Real-time query monitoring and analysis
- **`AvailabilityGroup_HADR_SYNC_COMMIT_delay.sql`** - Always On availability group latency monitoring
- **`CheckAgeOfStatistics_WithUpdateStatistics.sql`** - Statistics maintenance automation
- **`IdentifyMissingIndexesWithHighAverageImpact.sql`** - Missing index impact analysis
- **`IndexFillFactorAdjustmentAnalysis.sql`** - Index optimization recommendations

#### SQL Calendar (`mssql/sql-calendar/`)

Advanced date and calendar functionality for SQL Server:

**Core Features:**
- **`calendar.sql`** - Comprehensive calendar table with business logic
- Pre-calculated date dimensions, holidays, and business day calculations
- Optimized for high-performance date-based queries

**Benchmarks (`mssql/sql-calendar/benches/`)**
- **`calendar_datetrunc_benchmark.sql`** - Date truncation performance comparison
- **`day_of_week_metadata_benchmark.sql`** - Day-of-week calculation optimization

**Examples (`mssql/sql-calendar/examples/`)**
- **`generate_schedule_examples.sql`** - Recurring schedule generation patterns
- **`is_scheduled_date_examples.sql`** - Business rule date validation examples

#### Temporal Tables (`mssql/temporal-tables/`)

SQL Server temporal table templates and patterns:

- **`Template_CustomTemporalTable_CurrentPattern.sql`** - Custom temporal implementation (current-state pattern)
- **`Template_CustomTemporalTable_ExpiredMaxDateTimePattern.sql`** - Custom temporal with expiration handling
- **`Template_SystemVersionedTemporalTable_Basic.sql`** - Basic system-versioned temporal table
- **`Template_SystemVersionedTemporalTable_BiTemporal.sql`** - Bi-temporal data management pattern
- **`Template_SystemVersionedTemporalTable_TableConversion.sql`** - Convert existing tables to temporal

## Getting Started

### Prerequisites

- **SQL Server 2017+** (most scripts compatible)
- **SQL Server Management Studio** or other SQL IDE
- **Docker** (for testing framework)
- **sqlcmd** utility (for automation scripts)

## Documentation

- **[`calendar` Documentation](mssql/sql-calendar/README.md)** - Advanced date handling utilities
- **[Toggle Schemabinding Guide](mssql/ddl-dependencies/README.md)** - Database performance analysis tools
- **[Toggle Schemabinding Testing Guide](mssql/ddl-dependencies/testing/README.md)** - Comprehensive Docker testing framework
- **[Temporal Tables](mssql/temporal-tables/)** - Historical (temporal) data management patterns

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

---

**Repository maintained by:** Joel Searcy  
**Focus:** SQL Database Administration, Performance Optimization, and Development Automation  
**Latest Update:** September 2025