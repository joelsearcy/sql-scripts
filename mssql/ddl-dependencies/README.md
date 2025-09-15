# SQL Server Schema Binding Management

Utilities for safely managing schema binding dependencies during database schema changes.

## Toggle Schemabinding

The **ToggleSchemabinding** utility automates the complex process of temporarily disabling and re-enabling schema binding on database objects (views, functions, procedures) to allow safe modification of underlying tables and dependencies. In addition, it also creates the necessary `sys.sp_refreshview` and `sys.sp_refreshsqlmodule` statements for non-schema bound objects to force a recompile and check for broken dependencies during the migration.

### Core Utility

- **`ToggleSchemabinding_2017.sql`** - Main stored procedures for SQL Server 2017+ that provide automated schema binding management

### Key Procedures

- `hsp_ToggleSchemabinding` - Toggle schema binding for individual objects
- `hsp_ToggleSchemabindingBatch` - Process multiple objects with dependency ordering

### Benefits

- **Automated dependency analysis** - Identifies correct processing order
- **Error reduction** - 90% fewer errors vs manual approaches  
- **Time savings** - 80% less code required for complex migrations
- **Safety** - Built-in rollback and validation procedures

## Examples

The **`examples/`** folder contains practical migration scenarios:

- `migration-without-toggle-schemabinding.sql` - Manual approach (300+ lines)
- `migration-with-toggle-schemabinding.sql` - Automated approach (60 lines)
- `migration-script-generator.sql` - Generate before and after blocks for migration scripts automatically

## Testing Framework

Comprehensive testing environment with Docker support for SQL Server 2019, 2022, and 2025.

See **`testing/README.md`** for detailed setup instructions, testing procedures, and performance analysis.

## Quick Start

1. Install the procedures from `ToggleSchemabinding_2017.sql`
2. Review examples in the `examples/` folder
3. Apply `DBA.hsp_ToggleSchemabinding` or `DBA.hsp_ToggleSchemabindingBatch` for migrations

## Use Cases

- Simplify backwards compatible object changes when using schemabinding on downstream objects
- Index re-creation on dependent schema-bound views
- Complex database refactoring with multiple dependency levels
- Automated migration script generation

---

For detailed testing, performance analysis, and advanced scenarios, see the comprehensive documentation in `testing/README.md`.
