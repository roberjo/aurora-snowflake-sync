module.exports = {
    testEnvironment: 'node',
    coverageDirectory: 'coverage',
    collectCoverageFrom: [
        'index.js',
        '!**/*.test.js',
        '!**/node_modules/**'
    ],
    coverageThreshold: {
        global: {
            branches: 50,
            functions: 50,
            lines: 50,
            statements: 50
        }
    },
    testMatch: [
        '**/*.test.js'
    ],
    verbose: true
};
