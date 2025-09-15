/*USE SchemaBindingTestDB;*/

EXEC [DBA].[hsp_ToggleSchemaBindingBatch]
	@objectList = N'Core.Customers';
    
/* Generated Output:
BEGIN TRY
	/*Toggle Schemabinding Off*/
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Strategy"."vw_InvestmentOpportunities"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Research"."fn_GetMarketSegments"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Research"."vw_MarketAnalysis"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Executive"."vw_ExecutiveDashboard"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Executive"."vw_TopCompanyAnalysis"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Analytics"."fn_GetTopPerformingCompanies"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Analytics"."vw_BusinessIntelligence"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Sales"."vw_CustomerProfitability"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Sales"."fn_GetCustomerAnalytics"', @newIsSchemaBound = 0;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Core"."vw_OrderSummary"', @newIsSchemaBound = 0;
END TRY
BEGIN CATCH
	IF (@@TRANCOUNT > 0)
	BEGIN
		ROLLBACK TRANSACTION;
	END;

	THROW;
	RETURN;
END CATCH;
GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO

/**** Your Changes to Core.Customers go here ****/

GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO
BEGIN TRY
	/*Toggle Schemabinding On and Refresh Non-Schemabound Views*/
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Core"."vw_OrderSummary"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Sales"."fn_GetCustomerAnalytics"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Sales"."vw_CustomerProfitability"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Analytics"."vw_BusinessIntelligence"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Analytics"."fn_GetTopPerformingCompanies"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Executive"."vw_TopCompanyAnalysis"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Executive"."vw_ExecutiveDashboard"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Research"."vw_MarketAnalysis"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Research"."fn_GetMarketSegments"', @newIsSchemaBound = 1;
	EXEC DBA.hsp_ToggleSchemaBinding @objectName =  N'"Strategy"."vw_InvestmentOpportunities"', @newIsSchemaBound = 1;
	EXEC sys.sp_refreshsqlmodule /*WARNING: Any associated signatures will be dropped!*/ N'"Strategy"."fn_GetInvestmentPortfolio"';
	EXEC sys.sp_refreshsqlmodule /*WARNING: Any associated signatures will be dropped!*/ N'"Governance"."fn_GetComplianceMetrics"';
	EXEC sys.sp_refreshview N'"Risk"."vw_PortfolioRiskAssessment"';
	EXEC sys.sp_refreshview N'"Governance"."vw_ExecutiveComplianceDashboard"';
END TRY
BEGIN CATCH
	IF (@@TRANCOUNT > 0)
	BEGIN
		ROLLBACK TRANSACTION;
	END;

	THROW;
	RETURN;
END CATCH;
GO
IF (@@ERROR <> 0 OR @@TRANCOUNT <= 0)
BEGIN
	RAISERROR('SCHEMA CHANGE FAILED!', 18, 0);
	IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
	SET NOEXEC ON;
	RETURN;
END;
GO
 

Completion time: 2025-09-15T09:46:27.7405418-06:00

*/