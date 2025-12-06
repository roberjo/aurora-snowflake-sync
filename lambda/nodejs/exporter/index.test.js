/**
 * Unit tests for the Aurora-Snowflake Exporter Lambda Function
 * 
 * These tests validate the core functionality of the exporter including:
 * - Configuration handling
 * - Environment variable validation
 * - Error handling
 * - Data transformation logic
 */

// Mock the dependencies before requiring the module
jest.mock('pg');
jest.mock('snowflake-sdk');
jest.mock('node-vault');

const { Client } = require('pg');
const snowflake = require('snowflake-sdk');
const vault = require('node-vault');

// Import the handler after mocking
const { handler } = require('./index');

describe('Aurora-Snowflake Exporter Lambda', () => {
    let originalEnv;

    beforeEach(() => {
        // Save original environment
        originalEnv = { ...process.env };
        
        // Clear all mocks
        jest.clearAllMocks();
        
        // Reset environment variables
        process.env.S3_BUCKET = 'test-bucket';
        process.env.VAULT_ADDR = 'http://localhost:8200';
        process.env.VAULT_TOKEN = 'test-token';
    });

    afterEach(() => {
        // Restore original environment
        process.env = originalEnv;
    });

    describe('Environment Variable Validation', () => {
        test('should use S3_BUCKET environment variable', async () => {
            // Arrange
            const mockVaultClient = {
                read: jest.fn().mockResolvedValue({
                    data: {
                        data: {
                            aurora_host: 'localhost',
                            aurora_db: 'testdb',
                            aurora_user: 'user',
                            aurora_password: 'pass',
                            snowflake_account: 'account',
                            snowflake_user: 'user',
                            snowflake_password: 'pass'
                        }
                    }
                })
            };
            vault.mockReturnValue(mockVaultClient);

            const mockPgClient = {
                connect: jest.fn().mockResolvedValue(undefined),
                query: jest.fn().mockResolvedValue({ rows: [] }),
                end: jest.fn().mockResolvedValue(undefined)
            };
            Client.mockImplementation(() => mockPgClient);

            const mockSnowflakeConnection = {
                connect: jest.fn((callback) => {
                    const mockConn = {
                        execute: jest.fn(({ complete }) => {
                            complete(null, {}, [{ 'MAX(UPDATED_AT)': '2024-01-01 00:00:00' }]);
                        }),
                        destroy: jest.fn((callback) => callback(null, mockConn))
                    };
                    callback(null, mockConn);
                })
            };
            snowflake.createConnection.mockReturnValue(mockSnowflakeConnection);

            // Act
            const result = await handler({});

            // Assert
            expect(result.statusCode).toBe(200);
            expect(mockPgClient.connect).toHaveBeenCalled();
        });

        test('should handle missing S3_BUCKET gracefully', async () => {
            // Arrange
            delete process.env.S3_BUCKET;

            const mockVaultClient = {
                read: jest.fn().mockResolvedValue({
                    data: {
                        data: {
                            aurora_host: 'localhost',
                            aurora_db: 'testdb',
                            aurora_user: 'user',
                            aurora_password: 'pass',
                            snowflake_account: 'account',
                            snowflake_user: 'user',
                            snowflake_password: 'pass'
                        }
                    }
                })
            };
            vault.mockReturnValue(mockVaultClient);

            const mockSnowflakeConnection = {
                connect: jest.fn((callback) => {
                    const mockConn = {
                        execute: jest.fn(({ complete }) => {
                            complete(null, {}, [{ 'MAX(UPDATED_AT)': '2024-01-01 00:00:00' }]);
                        }),
                        destroy: jest.fn((callback) => callback(null, mockConn))
                    };
                    callback(null, mockConn);
                })
            };
            snowflake.createConnection.mockReturnValue(mockSnowflakeConnection);

            // Act
            const result = await handler({});

            // Assert - Should handle undefined S3_BUCKET
            expect(result).toBeDefined();
        });
    });

    describe('Vault Integration', () => {
        test('should retrieve secrets from Vault', async () => {
            // Arrange
            const mockSecrets = {
                aurora_host: 'aurora.example.com',
                aurora_db: 'production',
                aurora_user: 'admin',
                aurora_password: 'secret123',
                snowflake_account: 'myaccount',
                snowflake_user: 'sfuser',
                snowflake_password: 'sfpass'
            };

            const mockVaultClient = {
                read: jest.fn().mockResolvedValue({
                    data: { data: mockSecrets }
                })
            };
            vault.mockReturnValue(mockVaultClient);

            const mockPgClient = {
                connect: jest.fn().mockResolvedValue(undefined),
                query: jest.fn().mockResolvedValue({ rows: [] }),
                end: jest.fn().mockResolvedValue(undefined)
            };
            Client.mockImplementation(() => mockPgClient);

            const mockSnowflakeConnection = {
                connect: jest.fn((callback) => {
                    const mockConn = {
                        execute: jest.fn(({ complete }) => {
                            complete(null, {}, [{ 'MAX(UPDATED_AT)': '2024-01-01 00:00:00' }]);
                        }),
                        destroy: jest.fn((callback) => callback(null, mockConn))
                    };
                    callback(null, mockConn);
                })
            };
            snowflake.createConnection.mockReturnValue(mockSnowflakeConnection);

            // Act
            const result = await handler({});

            // Assert
            expect(vault).toHaveBeenCalledWith({
                apiVersion: 'v1',
                endpoint: 'http://localhost:8200',
                token: 'test-token'
            });
            expect(mockVaultClient.read).toHaveBeenCalledWith('aurora-snowflake-sync');
            expect(result.statusCode).toBe(200);
        });

        test('should handle Vault connection errors', async () => {
            // Arrange
            const mockVaultClient = {
                read: jest.fn().mockRejectedValue(new Error('Vault connection failed'))
            };
            vault.mockReturnValue(mockVaultClient);

            // Act
            const result = await handler({});

            // Assert
            expect(result.statusCode).toBe(500);
            expect(result.body).toContain('Error');
        });
    });

    describe('Snowflake Watermark Retrieval', () => {
        test('should return default watermark when no data exists', async () => {
            // Arrange
            const mockVaultClient = {
                read: jest.fn().mockResolvedValue({
                    data: {
                        data: {
                            aurora_host: 'localhost',
                            aurora_db: 'testdb',
                            aurora_user: 'user',
                            aurora_password: 'pass',
                            snowflake_account: 'account',
                            snowflake_user: 'user',
                            snowflake_password: 'pass'
                        }
                    }
                })
            };
            vault.mockReturnValue(mockVaultClient);

            const mockPgClient = {
                connect: jest.fn().mockResolvedValue(undefined),
                query: jest.fn().mockResolvedValue({ rows: [] }),
                end: jest.fn().mockResolvedValue(undefined)
            };
            Client.mockImplementation(() => mockPgClient);

            const mockSnowflakeConnection = {
                connect: jest.fn((callback) => {
                    const mockConn = {
                        execute: jest.fn(({ complete }) => {
                            // Return empty result
                            complete(null, {}, []);
                        }),
                        destroy: jest.fn((callback) => callback(null, mockConn))
                    };
                    callback(null, mockConn);
                })
            };
            snowflake.createConnection.mockReturnValue(mockSnowflakeConnection);

            // Act
            const result = await handler({});

            // Assert
            expect(result.statusCode).toBe(200);
        });

        test('should handle Snowflake connection errors', async () => {
            // Arrange
            const mockVaultClient = {
                read: jest.fn().mockResolvedValue({
                    data: {
                        data: {
                            aurora_host: 'localhost',
                            aurora_db: 'testdb',
                            aurora_user: 'user',
                            aurora_password: 'pass',
                            snowflake_account: 'account',
                            snowflake_user: 'user',
                            snowflake_password: 'pass'
                        }
                    }
                })
            };
            vault.mockReturnValue(mockVaultClient);

            const mockSnowflakeConnection = {
                connect: jest.fn((callback) => {
                    callback(new Error('Snowflake connection failed'), null);
                })
            };
            snowflake.createConnection.mockReturnValue(mockSnowflakeConnection);

            // Act
            const result = await handler({});

            // Assert
            expect(result.statusCode).toBe(500);
            expect(result.body).toContain('Error');
        });
    });

    describe('Aurora Export', () => {
        test('should successfully export data from Aurora', async () => {
            // Arrange
            const mockVaultClient = {
                read: jest.fn().mockResolvedValue({
                    data: {
                        data: {
                            aurora_host: 'localhost',
                            aurora_db: 'testdb',
                            aurora_user: 'user',
                            aurora_password: 'pass',
                            snowflake_account: 'account',
                            snowflake_user: 'user',
                            snowflake_password: 'pass'
                        }
                    }
                })
            };
            vault.mockReturnValue(mockVaultClient);

            const mockPgClient = {
                connect: jest.fn().mockResolvedValue(undefined),
                query: jest.fn().mockResolvedValue({ rows: [] }),
                end: jest.fn().mockResolvedValue(undefined)
            };
            Client.mockImplementation(() => mockPgClient);

            const mockSnowflakeConnection = {
                connect: jest.fn((callback) => {
                    const mockConn = {
                        execute: jest.fn(({ complete }) => {
                            complete(null, {}, [{ 'MAX(UPDATED_AT)': '2024-01-01 00:00:00' }]);
                        }),
                        destroy: jest.fn((callback) => callback(null, mockConn))
                    };
                    callback(null, mockConn);
                })
            };
            snowflake.createConnection.mockReturnValue(mockSnowflakeConnection);

            // Act
            const result = await handler({});

            // Assert
            expect(result.statusCode).toBe(200);
            expect(mockPgClient.connect).toHaveBeenCalled();
            expect(mockPgClient.query).toHaveBeenCalled();
            expect(mockPgClient.end).toHaveBeenCalled();
        });

        test('should handle Aurora connection errors', async () => {
            // Arrange
            const mockVaultClient = {
                read: jest.fn().mockResolvedValue({
                    data: {
                        data: {
                            aurora_host: 'localhost',
                            aurora_db: 'testdb',
                            aurora_user: 'user',
                            aurora_password: 'pass',
                            snowflake_account: 'account',
                            snowflake_user: 'user',
                            snowflake_password: 'pass'
                        }
                    }
                })
            };
            vault.mockReturnValue(mockVaultClient);

            const mockPgClient = {
                connect: jest.fn().mockRejectedValue(new Error('Aurora connection failed')),
                end: jest.fn().mockResolvedValue(undefined)
            };
            Client.mockImplementation(() => mockPgClient);

            const mockSnowflakeConnection = {
                connect: jest.fn((callback) => {
                    const mockConn = {
                        execute: jest.fn(({ complete }) => {
                            complete(null, {}, [{ 'MAX(UPDATED_AT)': '2024-01-01 00:00:00' }]);
                        }),
                        destroy: jest.fn((callback) => callback(null, mockConn))
                    };
                    callback(null, mockConn);
                })
            };
            snowflake.createConnection.mockReturnValue(mockSnowflakeConnection);

            // Act
            const result = await handler({});

            // Assert
            expect(result.statusCode).toBe(500);
            expect(result.body).toContain('Error');
        });
    });

    describe('Complete Sync Process', () => {
        test('should complete sync for multiple tables', async () => {
            // Arrange
            const mockVaultClient = {
                read: jest.fn().mockResolvedValue({
                    data: {
                        data: {
                            aurora_host: 'localhost',
                            aurora_db: 'testdb',
                            aurora_user: 'user',
                            aurora_password: 'pass',
                            snowflake_account: 'account',
                            snowflake_user: 'user',
                            snowflake_password: 'pass'
                        }
                    }
                })
            };
            vault.mockReturnValue(mockVaultClient);

            const mockPgClient = {
                connect: jest.fn().mockResolvedValue(undefined),
                query: jest.fn().mockResolvedValue({ rows: [] }),
                end: jest.fn().mockResolvedValue(undefined)
            };
            Client.mockImplementation(() => mockPgClient);

            const mockSnowflakeConnection = {
                connect: jest.fn((callback) => {
                    const mockConn = {
                        execute: jest.fn(({ complete }) => {
                            complete(null, {}, [{ 'MAX(UPDATED_AT)': '2024-01-01 00:00:00' }]);
                        }),
                        destroy: jest.fn((callback) => callback(null, mockConn))
                    };
                    callback(null, mockConn);
                })
            };
            snowflake.createConnection.mockReturnValue(mockSnowflakeConnection);

            // Act
            const result = await handler({});

            // Assert
            expect(result.statusCode).toBe(200);
            expect(result.body).toContain('Sync completed successfully');
            
            // Should be called twice (once for orders, once for customers)
            expect(Client).toHaveBeenCalledTimes(2);
        });
    });
});
