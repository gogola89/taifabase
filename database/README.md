# Taifabase Development Environment

A comprehensive Docker Compose setup for the Taifabase multi-tenant database platform development environment.

## Overview

This development environment provides a complete infrastructure stack for developing and testing the Taifabase platform, with focus on PostgreSQL Row-Level Security (RLS) implementation, performance monitoring, and seamless developer experience.

## Architecture

### Core Services
- **PostgreSQL 15.8**: Primary database with RLS configuration
- **Redis 7.2**: Caching and session storage
- **Nginx**: Reverse proxy and static file serving

### Development Tools
- **Adminer**: Lightweight database administration
- **pgAdmin**: Advanced PostgreSQL administration
- **DevTools Container**: Alpine Linux environment for development tasks

### Monitoring Stack
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Metrics visualization and dashboards
- **PostgreSQL Exporter**: Database-specific metrics

## Quick Start

### Prerequisites

- Docker Engine 20.10+
- Docker Compose v2.0+
- 4GB+ available RAM
- 10GB+ available disk space

### Starting the Environment

```bash
# Clone and navigate to the database directory
cd /path/to/taifabase/database

# Start all services
./scripts/start-dev-environment.sh

# Or start manually
docker compose up -d

# Check service health
./scripts/health-checks/check-all-services.sh
```

### Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Adminer | http://localhost:8080 | Database administration |
| pgAdmin | http://localhost:8081 | Advanced DB administration |
| Grafana | http://localhost:3000 | Monitoring dashboards |
| Prometheus | http://localhost:9090 | Metrics and alerts |
| Nginx | http://localhost:80 | Reverse proxy |

### Database Connection

```bash
# Connection details
Host: localhost
Port: 5433
Database: taifabase_dev
Username: taifabase_user
Password: taifabase_dev_password

# Direct psql access
docker compose exec postgres psql -U taifabase_user -d taifabase_dev
```

## Environment Configuration

### Environment Variables

The `.env` file contains all configurable environment variables:

```bash
# Copy and customize environment file
cp .env .env.local
# Edit .env.local with your preferences
```

Key configuration options:
- **POSTGRES_***: Database configuration
- **REDIS_***: Cache configuration
- ***_PORT**: Service port mappings
- **GRAFANA_***: Monitoring credentials

### Custom Configuration

Service configurations are located in the `config/` directory:
- `postgresql.conf`: PostgreSQL server configuration
- `nginx.conf`: Nginx server configuration
- `prometheus.yml`: Prometheus monitoring configuration
- `grafana/`: Grafana datasources and dashboards

## Database Schema

The environment automatically initializes with Marcus Rodriguez's database schema:

### Schemas
- **core**: Core system tables (tenants, users)
- **tenant**: Tenant-specific data with RLS policies
- **audit**: Audit logging and tracking

### Key Tables
- `core.tenants`: Tenant management
- `core.users`: User management with tenant association
- `tenant.sample_data`: Sample data for RLS testing

### Row-Level Security (RLS)

RLS policies are implemented for tenant isolation:
```sql
-- Example: Check RLS policies
\\d+ tenant.sample_data

-- Example: Test tenant isolation
SET row_security = on;
SET SESSION "app.tenant_id" = 'your-tenant-id';
SELECT * FROM tenant.sample_data;
```

## Development Workflows

### Daily Development

1. **Start Environment**
   ```bash
   ./scripts/start-dev-environment.sh
   ```

2. **Check Health**
   ```bash
   ./scripts/health-checks/check-all-services.sh
   ```

3. **Database Development**
   ```bash
   # Access database
   docker compose exec postgres psql -U taifabase_user -d taifabase_dev
   
   # Run schema migrations
   docker compose exec postgres psql -U taifabase_user -d taifabase_dev -f /workspace/migrations/001_new_feature.sql
   ```

4. **Monitor Performance**
   - Open Grafana at http://localhost:3000
   - Username: admin, Password: taifabase_grafana
   - View PostgreSQL dashboard for real-time metrics

### Testing RLS Policies

1. **Performance Testing**
   ```bash
   # Run performance baseline
   docker compose exec postgres psql -U taifabase_user -d taifabase_dev -f /docker-entrypoint-initdb.d/performance_baseline.sql
   
   # Run RLS performance comparison
   docker compose exec postgres psql -U taifabase_user -d taifabase_dev -f /docker-entrypoint-initdb.d/performance_rls_comparison.sql
   ```

2. **Security Testing**
   ```bash
   # Test tenant isolation
   docker compose exec postgres psql -U taifabase_user -d taifabase_dev -c "
   SET row_security = on;
   SET SESSION \"app.tenant_id\" = '$(uuidgen)';
   SELECT * FROM tenant.sample_data;"
   ```

### Debugging and Troubleshooting

1. **View Logs**
   ```bash
   # All services
   docker compose logs
   
   # Specific service
   docker compose logs postgres
   docker compose logs -f redis  # Follow mode
   ```

2. **Service Management**
   ```bash
   # Restart service
   docker compose restart postgres
   
   # Rebuild service
   docker compose up --build postgres
   
   # Scale service (for load testing)
   docker compose up --scale postgres_exporter=2
   ```

3. **Database Debugging**
   ```bash
   # Access development shell
   docker compose exec devtools sh
   
   # Database performance analysis
   docker compose exec postgres psql -U taifabase_user -d taifabase_dev -c "
   SELECT query, calls, mean_time, total_time 
   FROM pg_stat_statements 
   ORDER BY total_time DESC LIMIT 10;"
   ```

### Data Management

1. **Backup and Restore**
   ```bash
   # Create backup
   docker compose exec postgres pg_dump -U taifabase_user taifabase_dev > backup.sql
   
   # Restore from backup
   docker compose exec -T postgres psql -U taifabase_user -d taifabase_dev < backup.sql
   ```

2. **Reset Environment**
   ```bash
   # Clean restart
   docker compose down -v
   docker compose up -d
   ```

## Performance Optimization

### Startup Performance
- **Target**: <5 minutes total startup time
- **Actual**: ~2.5 seconds for core services
- **Monitoring**: Startup time is logged by `start-dev-environment.sh`

### Database Performance
- PostgreSQL configured for development with optimized memory settings
- Performance monitoring via PostgreSQL Exporter and Grafana
- Baseline performance metrics established before RLS implementation

### Resource Usage
- **PostgreSQL**: 2GB memory limit, 512MB reservation
- **Redis**: 512MB memory limit, 128MB reservation
- **Total**: ~4GB RAM recommended for full stack

## Integration with Team Workflow

### Coordination with Backend (Marcus)
- PostgreSQL schema and RLS policies are automatically loaded
- Performance baseline established for RLS development
- Database configuration optimized for RLS testing

### QA Integration (Aisha)
- Isolated test environment available via containers
- Performance monitoring for regression testing
- Test data generation capabilities

### Security Integration (Kenji)
- Security-hardened configurations
- Audit logging capabilities
- RLS policy validation environment

## Troubleshooting Guide

### Common Issues

1. **Port Conflicts**
   ```bash
   # Check port usage
   lsof -i :5433
   
   # Modify ports in .env file
   POSTGRES_PORT=5434
   ```

2. **Memory Issues**
   ```bash
   # Check container resource usage
   docker stats
   
   # Reduce memory limits in docker-compose.yml
   ```

3. **Network Issues**
   ```bash
   # Recreate networks
   docker compose down
   docker network prune -f
   docker compose up -d
   ```

4. **Database Connection Issues**
   ```bash
   # Check PostgreSQL logs
   docker compose logs postgres
   
   # Verify database is ready
   docker compose exec postgres pg_isready -U taifabase_user
   ```

### Performance Issues

1. **Slow Startup**
   - Check Docker resource allocation
   - Verify disk space availability
   - Review container resource limits

2. **Database Performance**
   - Monitor via Grafana dashboards
   - Check PostgreSQL slow query log
   - Analyze `pg_stat_statements` for optimization opportunities

### Recovery Procedures

1. **Service Recovery**
   ```bash
   # Reset specific service
   docker compose stop postgres
   docker compose rm postgres
   docker compose up -d postgres
   ```

2. **Complete Environment Reset**
   ```bash
   # Nuclear option - complete reset
   docker compose down -v --remove-orphans
   docker system prune -f
   ./scripts/start-dev-environment.sh
   ```

## Day 2 Roadmap

### Planned Enhancements
1. **PgBouncer Integration**
   - Connection pooling for improved performance
   - Configuration for multi-tenant connection management
   - Integration with existing PostgreSQL setup

2. **Enhanced Monitoring**
   - Custom Grafana dashboards for RLS performance
   - Alerting rules for performance thresholds
   - Application-specific metrics collection

3. **Development Tools**
   - Database migration management
   - Automated test data generation
   - CI/CD integration capabilities

## Support and Contact

- **DevOps Engineer**: Raj Patel (@raj.patel)
- **Backend Engineer**: Marcus Rodriguez (@marcus.rodriguez)
- **Project Manager**: Sarah Chen (@sarah.chen)

For immediate technical support, use the `#taifabase-phase1` Slack channel or create an issue in the project repository.

---

**Created by**: Raj Patel - Senior DevOps Engineer  
**Date**: 2025-10-03  
**Version**: 1.0  
**Sprint**: Phase 1, Sprint 1, Day 1