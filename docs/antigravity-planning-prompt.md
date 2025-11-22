You are an expert software architect and data engineer tasked with planning and building "aurora-snowflake-sync" - an automated data backup and synchronization pipeline for AWS Aurora PostgreSQL (v2) to Snowflake.

This project will create an AWS aurora v2 postgresql database backup etl system that uses an s3 bucket that snowflake will read and ingest into tables in snowflake data lake.  The project will need to use Terraform cloud for IaC for all aws resources and aws configurations. The project will need to use hashicorp vault for secrets storage and retrieval.  The project needs to not impact production database operations, but needs to replicate all data changes from the aurora database schema for customers and orders to snowflake for data analysis and reporting.


PROJECT OVERVIEW:
Build a production-ready system that automatically backs up and synchronizes data from AWS Aurora PostgreSQL v2 databases to Snowflake data warehouse with reliable scheduling, incremental backups, and comprehensive monitoring.

YOUR TASK:
Create a detailed, step-by-step implementation plan that covers:

1. ARCHITECTURE DESIGN
   - System architecture diagram and components
   - Data flow from Aurora to Snowflake
   - Authentication and security model
   - Scalability and performance considerations
   - Error handling and retry mechanisms

2. TECHNICAL STACK
   - Programming language(s) recommendation with justification
   - AWS services needed (Lambda, ECS, EventBridge, S3, etc.)
   - Snowflake connectors and integration methods
   - Infrastructure as Code tools (Terraform Cloud)
   - Monitoring and logging solutions

3. CORE FEATURES
   - Initial full database backup/sync
   - Incremental synchronization strategy (CDC or timestamp-based)
   - Configurable sync schedules
   - Multi-table and multi-schema support
   - Data type mapping between PostgreSQL and Snowflake
   - Connection pooling and resource management

4. DATA PIPELINE STAGES
   - Data extraction from Aurora (methods: pg_dump, logical replication, CDC)
   - Transformation requirements (if any)
   - Staging strategy (S3 external snowflake stage)
   - Loading into Snowflake (COPY, Snowpipe, streaming)
   - Validation and reconciliation

5. CONFIGURATION & DEPLOYMENT
   - Configuration file structure (YAML/JSON)
   - Environment variable management
   - Secrets management (Hashicorp Vault, AWS Secrets Manager)
   - CI/CD pipeline setup
   - Deployment strategies (blue-green, canary)

6. MONITORING & OBSERVABILITY
   - Logging strategy (CloudWatch, Snowflake query history)
   - Metrics to track (sync latency, row counts, errors)
   - Alerting mechanisms
   - Dashboard recommendations

7. ERROR HANDLING & RESILIENCE
   - Connection failure recovery
   - Partial sync failure handling
   - Data consistency checks
   - Rollback mechanisms
   - Dead letter queues for failed records

8. SECURITY CONSIDERATIONS
   - IAM roles and policies
   - Network security (VPC, security groups)
   - Encryption at rest and in transit
   - Credential rotation
   - Audit logging

9. TESTING STRATEGY
   - Unit tests for core logic
   - Integration tests with Aurora and Snowflake
   - End-to-end testing approach
   - Performance testing
   - Disaster recovery testing

10. DOCUMENTATION REQUIREMENTS
    - README with setup instructions
    - Architecture documentation
    - Configuration guide
    - Troubleshooting guide
    - API/CLI reference

11. IMPLEMENTATION PHASES
    - Phase 1: MVP with basic full sync
    - Phase 2: Incremental sync capability
    - Phase 3: Advanced features and optimization
    - Phase 4: Production hardening

12. PROJECT STRUCTURE
    - Recommended directory layout
    - Module organization
    - Configuration file locations
    - Test structure

DELIVERABLES:
1. Detailed technical specification document
2. Architecture diagrams
3. Implementation roadmap with time estimates
4. Risk assessment and mitigation strategies
5. List of dependencies and prerequisites
6. Sample configuration files
7. Initial project scaffolding structure

CONSTRAINTS:
- Must work with Aurora PostgreSQL v2
- Must be cost-effective for AWS resources
- Should support databases of various sizes (GB to TB)
- Must provide near-real-time sync capability (configurable)
- Should be maintainable by a small team

SUCCESS CRITERIA:
- Successfully syncs 100% of data without loss
- Handles schema changes gracefully
- Completes full sync within acceptable timeframe
- Minimal operational overhead
- Clear error messages and logging
- Easy to configure and deploy

Please provide a comprehensive plan that a development team can follow to build this system from scratch. Include best practices, potential pitfalls to avoid, and recommendations based on industry standards for data pipeline development.