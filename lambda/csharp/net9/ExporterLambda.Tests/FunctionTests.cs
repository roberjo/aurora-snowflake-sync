using Amazon.Lambda.Core;
using Amazon.Lambda.TestUtilities;
using ExporterLambda;
using FluentAssertions;
using Xunit;

namespace ExporterLambda.Tests;

/// <summary>
/// Unit tests for the ExporterLambda Function class.
/// These tests validate the configuration models and basic functionality.
/// Note: Integration tests with actual database connections are handled separately.
/// </summary>
public class FunctionTests
{
    /// <summary>
    /// Test that TableConfig can be instantiated with default values.
    /// </summary>
    [Fact]
    public void TableConfig_ShouldInitializeWithDefaults()
    {
        // Arrange & Act
        var config = new Function.TableConfig();

        // Assert
        config.TableName.Should().BeEmpty();
        config.WatermarkCol.Should().BeEmpty();
    }

    /// <summary>
    /// Test that TableConfig properties can be set correctly.
    /// </summary>
    [Fact]
    public void TableConfig_ShouldSetPropertiesCorrectly()
    {
        // Arrange & Act
        var config = new Function.TableConfig
        {
            TableName = "orders",
            WatermarkCol = "updated_at"
        };

        // Assert
        config.TableName.Should().Be("orders");
        config.WatermarkCol.Should().Be("updated_at");
    }

    /// <summary>
    /// Test that SyncConfig can be instantiated with default values.
    /// </summary>
    [Fact]
    public void SyncConfig_ShouldInitializeWithEmptyList()
    {
        // Arrange & Act
        var config = new Function.SyncConfig();

        // Assert
        config.Tables.Should().NotBeNull();
        config.Tables.Should().BeEmpty();
    }

    /// <summary>
    /// Test that SyncConfig can hold multiple TableConfig objects.
    /// </summary>
    [Fact]
    public void SyncConfig_ShouldHoldMultipleTables()
    {
        // Arrange & Act
        var config = new Function.SyncConfig
        {
            Tables = new List<Function.TableConfig>
            {
                new Function.TableConfig { TableName = "orders", WatermarkCol = "updated_at" },
                new Function.TableConfig { TableName = "customers", WatermarkCol = "created_at" }
            }
        };

        // Assert
        config.Tables.Should().HaveCount(2);
        config.Tables[0].TableName.Should().Be("orders");
        config.Tables[1].TableName.Should().Be("customers");
    }

    /// <summary>
    /// Test that the Lambda context logger is used correctly.
    /// </summary>
    [Fact]
    public void TestLambdaContext_ShouldProvideLogger()
    {
        // Arrange
        var context = new TestLambdaContext();

        // Act & Assert
        context.Logger.Should().NotBeNull();
        
        // Verify we can log without errors
        Action act = () => context.Logger.LogInformation("Test message");
        act.Should().NotThrow();
    }

    /// <summary>
    /// Test that multiple TableConfig objects can be created with different configurations.
    /// </summary>
    [Theory]
    [InlineData("orders", "updated_at")]
    [InlineData("customers", "created_at")]
    [InlineData("products", "modified_date")]
    public void TableConfig_ShouldSupportVariousTableNames(string tableName, string watermarkCol)
    {
        // Arrange & Act
        var config = new Function.TableConfig
        {
            TableName = tableName,
            WatermarkCol = watermarkCol
        };

        // Assert
        config.TableName.Should().Be(tableName);
        config.WatermarkCol.Should().Be(watermarkCol);
    }

    /// <summary>
    /// Test that TableConfig can be added to a list.
    /// </summary>
    [Fact]
    public void TableConfig_ShouldBeAddableToList()
    {
        // Arrange
        var tableConfigs = new List<Function.TableConfig>();

        // Act
        tableConfigs.Add(new Function.TableConfig { TableName = "table1", WatermarkCol = "col1" });
        tableConfigs.Add(new Function.TableConfig { TableName = "table2", WatermarkCol = "col2" });

        // Assert
        tableConfigs.Should().HaveCount(2);
        tableConfigs[0].TableName.Should().Be("table1");
        tableConfigs[1].TableName.Should().Be("table2");
    }

    /// <summary>
    /// Test that SyncConfig Tables property is mutable.
    /// </summary>
    [Fact]
    public void SyncConfig_TablesShouldBeMutable()
    {
        // Arrange
        var config = new Function.SyncConfig();

        // Act
        config.Tables.Add(new Function.TableConfig { TableName = "test", WatermarkCol = "test_col" });

        // Assert
        config.Tables.Should().HaveCount(1);
        config.Tables[0].TableName.Should().Be("test");
    }

    /// <summary>
    /// Test that TestLambdaContext provides required properties.
    /// </summary>
    [Fact]
    public void TestLambdaContext_ShouldProvideRequiredProperties()
    {
        // Arrange & Act
        var context = new TestLambdaContext
        {
            FunctionName = "TestFunction",
            FunctionVersion = "1.0",
            MemoryLimitInMB = 512
        };

        // Assert
        context.FunctionName.Should().Be("TestFunction");
        context.FunctionVersion.Should().Be("1.0");
        context.MemoryLimitInMB.Should().Be(512);
    }
}
