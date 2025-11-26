using Amazon.Lambda.Core;
using Npgsql;
using Snowflake.Data.Client;
using System.Data;
using VaultSharp;
using VaultSharp.V1.AuthMethods.Token;
using VaultSharp.V1.Commons;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace ExporterLambda;

public class Function
{
    public class TableConfig
    {
        public string TableName { get; set; } = string.Empty;
        public string WatermarkCol { get; set; } = string.Empty;
    }

    public class SyncConfig
    {
        public List<TableConfig> Tables { get; set; } = new();
    }

    public async Task<string> FunctionHandler(object input, ILambdaContext context)
    {
        context.Logger.LogInformation("Starting sync process...");

        var config = new SyncConfig
        {
            Tables = new List<TableConfig>
            {
                new TableConfig { TableName = "orders", WatermarkCol = "updated_at" },
                new TableConfig { TableName = "customers", WatermarkCol = "updated_at" }
            }
        };

        var s3Bucket = Environment.GetEnvironmentVariable("S3_BUCKET");
        if (string.IsNullOrEmpty(s3Bucket))
        {
             // Fallback or error? Python script crashes if key missing.
             throw new Exception("S3_BUCKET env var missing");
        }

        try
        {
            // 1. Get Secrets
            var secrets = await GetSecretsAsync();

            var auroraConnString = $"Host={secrets["aurora_host"]};Database={secrets["aurora_db"]};Username={secrets["aurora_user"]};Password={secrets["aurora_password"]}";
            var snowflakeConnString = $"account={secrets["snowflake_account"]};user={secrets["snowflake_user"]};password={secrets["snowflake_password"]};warehouse=COMPUTE_WH;db=SYNC_DB;schema=STAGING";

            // 2. Iterate and Sync
            foreach (var tableCfg in config.Tables)
            {
                var watermark = await GetSnowflakeWatermarkAsync(snowflakeConnString, tableCfg.TableName, tableCfg.WatermarkCol);
                await ExportFromAuroraAsync(auroraConnString, s3Bucket, tableCfg, watermark, context.Logger);
            }

            return "Sync completed successfully";
        }
        catch (Exception e)
        {
            context.Logger.LogError($"Error: {e.Message}");
            throw;
        }
    }

    private async Task<IDictionary<string, object>> GetSecretsAsync()
    {
        var vaultAddr = Environment.GetEnvironmentVariable("VAULT_ADDR");
        var vaultToken = Environment.GetEnvironmentVariable("VAULT_TOKEN");

        if (string.IsNullOrEmpty(vaultAddr) || string.IsNullOrEmpty(vaultToken))
        {
            throw new Exception("VAULT_ADDR or VAULT_TOKEN missing");
        }

        var authMethod = new TokenAuthMethodInfo(vaultToken);
        var vaultClientSettings = new VaultClientSettings(vaultAddr, authMethod);
        var vaultClient = new VaultClient(vaultClientSettings);

        var secret = await vaultClient.V1.Secrets.KeyValue.V2.ReadSecretAsync(path: "aurora-snowflake-sync");
        
        return secret.Data.Data;
    }

    private async Task<string> GetSnowflakeWatermarkAsync(string connString, string tableName, string watermarkCol)
    {
        using var conn = new SnowflakeDbConnection();
        conn.ConnectionString = connString;
        await conn.OpenAsync();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = $"SELECT MAX({watermarkCol}) FROM {tableName}";

        var result = await cmd.ExecuteScalarAsync();
        
        if (result == null || result == DBNull.Value)
        {
            return "1970-01-01 00:00:00";
        }

        if (result is DateTime dt)
        {
            return dt.ToString("yyyy-MM-dd HH:mm:ss");
        }

        return result.ToString()!;
    }

    private async Task ExportFromAuroraAsync(string connString, string s3Bucket, TableConfig tableConfig, string watermark, ILambdaLogger logger)
    {
        using var conn = new NpgsqlConnection(connString);
        await conn.OpenAsync();

        var table = tableConfig.TableName;
        var col = tableConfig.WatermarkCol;
        var date = DateTime.UtcNow;
        var s3Prefix = $"{table}/{date:yyyy/MM/dd/HH}";

        var query = $"SELECT * FROM {table} WHERE {col} > '{watermark}'";
        
        var exportSql = $@"
            SELECT * from aws_s3.query_export_to_s3(
                '{query}', 
                aws_commons.create_s3_uri('{s3Bucket}', '{s3Prefix}', 'us-east-1')
            );
        ";

        logger.LogInformation($"Executing export for {table} with watermark > {watermark}");
        
        using var cmd = new NpgsqlCommand(exportSql, conn);
        try 
        {
            await cmd.ExecuteNonQueryAsync();
            logger.LogInformation($"Export successful to s3://{s3Bucket}/{s3Prefix}");
        }
        catch (Exception ex)
        {
            logger.LogError($"Export failed: {ex.Message}");
            throw;
        }
    }
}
