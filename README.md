# SQL Scripts Repository

A collection of SQL Server scripts, tools, and utilities for database administration, performance monitoring, and development automation.

## Getting Started

### Prerequisites

- **SQL Server 2017+** (most scripts compatible)
- **SQL Server Management Studio** or other SQL IDE
- **Docker** (for testing framework)
- **sqlcmd** utility (for automation scripts)

## Documentation

### Database Schema Migrations

- **[Toggle Schemabinding Procedures](mssql/ddl-dependencies/)** - How to reduce the scope of database change scripts while getting the benefits of enabling SCHEMABINDING by using `DBA.hsp_ToggleSchemabinding`
- **[Toggle Schemabinding Testing](mssql/ddl-dependencies/testing/)** - Comprehensive Docker testing framework for `DBA.hsp_ToggleSchemabinding`
- **[Development Helper Scripts](mssql/helper-scripts/)** - misc. template scripts and queries to script out objects from the database

### Design Patterns and Advanced T-SQL Examples

- **[Date Intervals](mssql/sql-date-interval/)** - Flattening/Merging, Differencing, and Intersecting of date intervals
- **[Calendar Scheduling](mssql/sql-calendar/)** - Advanced date scheduling utility functions
- **[Temporal Tables](mssql/temporal-tables/)** - temporal table examples, both custom and system-versioned

### Performance Monitoring

- **[Performance Monitoring Scritps](mssql/performance-monitoring/)** - queries for a variaty of performance related scenarios

## Resource Recommendations

- **Backups, Maintenance, Integrity Checks**
  - Simple. Use Ola Hallengren's [SQL Server Maintenance Solution](https://ola.hallengren.com/). It's a life changer if you are currently using the built-in Database Maintenance Plans.
- **Industry experts**
  - [Adam Machanic](http://dataeducation.com)
  - [Bob Ward](https://www.microsoft.com/en-us/sql-server/blog/author/bob-ward/)
  - [Brent Ozar](https://www.brentozar.com/)
  - [Erik Darling](https://erikdarling.com/)
  - [Erland Sommarskog](https://www.sommarskog.se)
  - [Grant Fritchey](https://www.scarydba.com/)
  - [Itzik Ben-Gan](https://itziktsql.com/)
  - [Kendra Little](https://kendralittle.com)
  - [Kimberly Tripp](https://www.sqlskills.com/blogs/kimberly/)
  - [Ola Hallengren](https://ola.hallengren.com/)
  - [Paul White](sql.kiwi)
  - Pedro Lopes
  - [Phil Factor](https://thphilfactor.com)

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

---

**Repository maintained by:** Joel Searcy  
**Focus:** SQL Database Administration, Performance Optimization, and Development Automation  
**Latest Update:** September 2025