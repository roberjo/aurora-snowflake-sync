const { Client } = require('pg');
const snowflake = require('snowflake-sdk');
const vault = require('node-vault');

/**
 * Exporter Lambda Function
 * ------------------------
 * Node.js version of the Aurora to Snowflake synchronization process.
 */

async function getSecrets() {
    const vaultAddr = process.env.VAULT_ADDR;
    const vaultToken = process.env.VAULT_TOKEN;

    const vaultClient = vault({
        apiVersion: 'v1',
        endpoint: vaultAddr,
        token: vaultToken
    });

    const secret = await vaultClient.read('aurora-snowflake-sync');
    return secret.data.data;
}

function getSnowflakeWatermark(connParams, tableName, watermarkCol) {
    return new Promise((resolve, reject) => {
        const connection = snowflake.createConnection({
            account: connParams.account,
            username: connParams.user,
            password: connParams.password,
            warehouse: connParams.warehouse,
            database: connParams.database,
            schema: connParams.schema
        });

        connection.connect((err, conn) => {
            if (err) {
                return reject(new Error('Unable to connect to Snowflake: ' + err.message));
            }

            const sqlText = `SELECT MAX(${watermarkCol}) FROM ${tableName}`;
            
            conn.execute({
                sqlText: sqlText,
                complete: (err, stmt, rows) => {
                    if (err) {
                        return reject(new Error('Failed to execute statement due to the following error: ' + err.message));
                    }
                    
                    const maxVal = (rows && rows.length > 0 && rows[0]['MAX(' + watermarkCol.toUpperCase() + ')']) 
                        ? rows[0]['MAX(' + watermarkCol.toUpperCase() + ')'] 
                        : '1970-01-01 00:00:00';
                        
                    // Note: Snowflake driver might return column names in uppercase by default.
                    // Accessing by index 0 if rows is array of arrays, or by column name if array of objects.
                    // snowflake-sdk returns array of objects by default.
                    // Let's try to be robust.
                    let result = '1970-01-01 00:00:00';
                    if (rows && rows.length > 0) {
                        // Get the first value of the first row
                        const firstRow = rows[0];
                        const values = Object.values(firstRow);
                        if (values.length > 0 && values[0]) {
                            result = values[0];
                        }
                    }
                    
                    // Format date if it's a Date object
                    if (result instanceof Date) {
                        result = result.toISOString().replace('T', ' ').replace('Z', '');
                    }

                    conn.destroy((err, conn) => {
                        if (err) {
                            console.error('Unable to disconnect: ' + err.message);
                        }
                        resolve(result);
                    });
                }
            });
        });
    });
}

async function exportFromAurora(dbParams, s3Bucket, tableConfig, watermark) {
    const client = new Client({
        host: dbParams.host,
        user: dbParams.user,
        password: dbParams.password,
        database: dbParams.database,
        ssl: { rejectUnauthorized: false } // Adjust based on actual SSL requirements
    });

    try {
        await client.connect();

        const table = tableConfig.table_name;
        const col = tableConfig.watermark_col;
        const date = new Date();
        const s3Prefix = `${table}/${date.getFullYear()}/${String(date.getMonth() + 1).padStart(2, '0')}/${String(date.getDate()).padStart(2, '0')}/${String(date.getHours()).padStart(2, '0')}`;

        const query = `SELECT * FROM ${table} WHERE ${col} > '${watermark}'`;
        
        // Escape single quotes in query if necessary, but simple concatenation here mirrors python script.
        // Be careful with SQL injection if inputs were untrusted.
        
        const exportSql = `
            SELECT * from aws_s3.query_export_to_s3(
                '${query}', 
                aws_commons.create_s3_uri('${s3Bucket}', '${s3Prefix}', 'us-east-1')
            );
        `;

        console.log(`Executing export for ${table} with watermark > ${watermark}`);
        await client.query(exportSql);
        console.log(`Export successful to s3://${s3Bucket}/${s3Prefix}`);

    } catch (err) {
        console.error(`Export failed: ${err}`);
        throw err;
    } finally {
        await client.end();
    }
}

exports.handler = async (event) => {
    console.log("Starting sync process...");

    const config = {
        tables: [
            { table_name: "orders", watermark_col: "updated_at" },
            { table_name: "customers", watermark_col: "updated_at" }
        ]
    };

    const s3Bucket = process.env.S3_BUCKET;

    try {
        // 1. Get Secrets
        const secrets = await getSecrets();

        const auroraParams = {
            host: secrets.aurora_host,
            database: secrets.aurora_db,
            user: secrets.aurora_user,
            password: secrets.aurora_password
        };

        const snowflakeParams = {
            user: secrets.snowflake_user,
            password: secrets.snowflake_password,
            account: secrets.snowflake_account,
            warehouse: 'COMPUTE_WH',
            database: 'SYNC_DB',
            schema: 'STAGING'
        };

        // 2. Iterate and Sync
        for (const tableCfg of config.tables) {
            const watermark = await getSnowflakeWatermark(
                snowflakeParams,
                tableCfg.table_name,
                tableCfg.watermark_col
            );

            await exportFromAurora(auroraParams, s3Bucket, tableCfg, watermark);
        }

        return {
            statusCode: 200,
            body: JSON.stringify('Sync completed successfully')
        };

    } catch (err) {
        console.error(`Error: ${err}`);
        return {
            statusCode: 500,
            body: JSON.stringify(`Error: ${err.message}`)
        };
    }
};
