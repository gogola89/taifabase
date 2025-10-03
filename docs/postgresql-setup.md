# PostgreSQL Setup Documentation
**Project**: Taifabase Phase 1  
**Engineer**: Marcus Rodriguez (Senior Backend Engineer)  
**Date**: 2025-10-03  
**Sprint**: 1, Day 1  
**Story**: US-101 - PostgreSQL Cluster Setup

## Environment Configuration

### PostgreSQL Version
- **Version**: PostgreSQL 15.8 (Debian 15.8-1.pgdg120+1)
- **Platform**: Docker container on x86_64-pc-linux-gnu
- **Compiler**: gcc (Debian 12.2.0-14) 12.2.0
- **Container Image**: postgres:15.8

### Database Cluster Details
- **Host**: localhost
- **Port**: 5433 (to avoid conflict with system PostgreSQL on 5432)
- **Database**: taifabase_dev
- **User**: taifabase_user
- **Password**: taifabase_dev_password (development only)

### Docker Configuration
```yaml
# Location: /home/bonnie/Projects/taifabase/database/docker-compose.yml
services:
  postgres:
    image: postgres:15.8
    container_name: taifabase_postgres
    environment:
      POSTGRES_DB: taifabase_dev
      POSTGRES_USER: taifabase_user
      POSTGRES_PASSWORD: taifabase_dev_password
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    ports:
      - "5433:5432"
```

## PostgreSQL Configuration Choices

### Memory and Performance Settings
```ini
# Optimized for development and RLS performance testing
shared_buffers = 256MB          # 25% of available RAM for development
effective_cache_size = 1GB      # Estimate of OS cache
work_mem = 16MB                 # Memory for sorting/hashing operations
maintenance_work_mem = 256MB    # Memory for maintenance operations
```

**Rationale**: These settings provide good performance for development while allowing for comprehensive RLS testing with sample datasets up to 25,000 records per tenant.

### Row Level Security Configuration
```ini
row_security = on               # Enable RLS globally
```

**Rationale**: Explicitly enabled to support multi-tenant RLS implementation. This is the foundation for tenant isolation.

### Logging and Monitoring
```ini
log_min_duration_statement = 1000  # Log queries taking > 1 second
log_statement = 'mod'               # Log all data-modifying statements
track_io_timing = on                # Track I/O timing for performance analysis
track_functions = all               # Track function performance
```

**Rationale**: Comprehensive logging to support performance baseline measurement and RLS impact analysis.

### WAL and Checkpoint Configuration
```ini
checkpoint_completion_target = 0.9  # Spread checkpoints over 90% of interval
wal_buffers = 16MB                  # WAL buffer size
max_wal_size = 2GB                  # Maximum WAL size before checkpoint
min_wal_size = 1GB                  # Minimum WAL size to maintain
```

**Rationale**: Optimized for development with good write performance and reasonable checkpoint frequency.

## Database Schema Design

### Core Schemas
1. **core**: Fundamental tables (tenants, users)
2. **tenant**: Multi-tenant data tables with RLS policies
3. **audit**: Audit logging and compliance tracking

### Key Tables Initialized
- `core.tenants`: Tenant master table
- `core.users`: User accounts with tenant association
- `tenant.sample_data`: Multi-tenant test data for RLS and performance testing

### Indexes for Performance
- Primary keys on all tables using UUID
- Foreign key indexes for tenant relationships
- Composite indexes for common query patterns
- GIN index on JSONB metadata column

## Extensions Enabled
- **uuid-ossp**: UUID generation functions
- **pg_stat_statements**: Query performance tracking

## Connection String
```bash
# Environment variable method (recommended)
export PGPASSWORD=taifabase_dev_password
psql -h localhost -p 5433 -U taifabase_user -d taifabase_dev

# Connection URL format
postgresql://taifabase_user:taifabase_dev_password@localhost:5433/taifabase_dev
```

## Health Check and Monitoring
- Container health check: `pg_isready` every 30 seconds
- Performance monitoring enabled with `pg_stat_statements`
- Query logging for statements > 1 second
- I/O timing tracking enabled

## Files Created
- `/home/bonnie/Projects/taifabase/database/docker-compose.yml` - Container orchestration
- `/home/bonnie/Projects/taifabase/database/config/postgresql.conf` - PostgreSQL configuration
- `/home/bonnie/Projects/taifabase/database/scripts/01_init_database.sql` - Database initialization
- `/home/bonnie/Projects/taifabase/database/scripts/02_test_data.sql` - Test data generation

## Next Steps
1. Performance baseline testing (without RLS)
2. RLS policy implementation and testing
3. Performance impact measurement with RLS enabled
4. Coordination with DevOps team for Docker Compose integration

## Team Coordination Notes
- **For Raj (DevOps)**: PostgreSQL service ready on port 5433, health checks configured
- **For Aisha (QA)**: Test database with 25,000+ sample records across 5 tenants ready for testing
- **For Kenji (Security)**: RLS foundation in place, ready for security review and policy validation

## Troubleshooting
- If port 5433 is occupied, modify docker-compose.yml to use alternative port
- Container logs: `docker compose logs postgres`
- Direct container access: `docker exec -it taifabase_postgres bash`