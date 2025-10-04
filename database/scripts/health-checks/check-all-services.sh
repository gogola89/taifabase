#!/bin/bash

# Taifabase Development Environment - Service Health Check Script
# This script checks the health of all Docker Compose services
# Created by: Raj Patel - DevOps Engineer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
MAX_WAIT_TIME=300  # 5 minutes
CHECK_INTERVAL=5   # 5 seconds

echo -e "${BLUE}Taifabase Development Environment - Health Check${NC}"
echo "=================================================="
echo "Checking all services health status..."
echo ""

# Function to check if a service is healthy
check_service_health() {
    local service_name=$1
    local max_attempts=$((MAX_WAIT_TIME / CHECK_INTERVAL))
    local attempt=1

    echo -n "Checking $service_name... "

    while [ $attempt -le $max_attempts ]; do
        # Get service health status
        health_status=$(docker compose ps --format json | jq -r ".[] | select(.Service == \"$service_name\") | .Health")
        
        if [ "$health_status" = "healthy" ]; then
            echo -e "${GREEN}✓ Healthy${NC}"
            return 0
        elif [ "$health_status" = "unhealthy" ]; then
            echo -e "${RED}✗ Unhealthy${NC}"
            return 1
        elif [ "$health_status" = "starting" ] || [ "$health_status" = "" ]; then
            if [ $attempt -eq $max_attempts ]; then
                echo -e "${YELLOW}⚠ Timeout (still starting)${NC}"
                return 2
            fi
            sleep $CHECK_INTERVAL
            attempt=$((attempt + 1))
        else
            echo -e "${RED}✗ Unknown status: $health_status${NC}"
            return 1
        fi
    done
}

# Function to check service connectivity
check_service_connectivity() {
    local service_name=$1
    local port=$2
    local host=${3:-localhost}

    echo -n "Testing $service_name connectivity ($host:$port)... "
    
    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        echo -e "${GREEN}✓ Connected${NC}"
        return 0
    else
        echo -e "${RED}✗ Connection failed${NC}"
        return 1
    fi
}

# Function to check PostgreSQL specifically
check_postgres() {
    echo -n "Testing PostgreSQL direct connection (port 5434)... "

    if docker compose exec -T postgres pg_isready -U taifabase_user -d taifabase_dev >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PostgreSQL ready${NC}"

        # Check if database has expected tables
        echo -n "Verifying database schema... "
        table_count=$(docker compose exec -T postgres psql -U taifabase_user -d taifabase_dev -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN ('core', 'tenant');" | tr -d ' ')

        if [ "$table_count" -ge 3 ]; then
            echo -e "${GREEN}✓ Schema verified ($table_count tables)${NC}"
        else
            echo -e "${YELLOW}⚠ Schema incomplete ($table_count tables)${NC}"
        fi

        return 0
    else
        echo -e "${RED}✗ PostgreSQL not ready${NC}"
        return 1
    fi
}

# Function to check PgBouncer
check_pgbouncer() {
    echo -n "Testing PgBouncer connection pooling... "

    # Check if PgBouncer is responding
    if docker compose exec -T pgbouncer psql -h localhost -p 5432 -U taifabase_user -d pgbouncer -t -c "SHOW POOLS;" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PgBouncer operational${NC}"

        # Get pool statistics
        echo -n "PgBouncer pool status... "
        pool_info=$(docker compose exec -T pgbouncer psql -h localhost -p 5432 -U taifabase_user -d pgbouncer -t -c "SHOW POOLS;" | grep -v "^$" | head -1)

        if [ -n "$pool_info" ]; then
            echo -e "${GREEN}✓ Pools active${NC}"

            # Get detailed stats
            echo "  Pool details:"
            docker compose exec -T pgbouncer psql -h localhost -p 5432 -U taifabase_user -d pgbouncer -t -c "SHOW POOLS;" | grep taifabase_dev | awk '{print "    Database: "$1", Client Connections: "$3", Server Connections: "$4", Server Active: "$5}'

            # Get configuration
            echo -n "  PgBouncer pool mode... "
            pool_mode=$(docker compose exec -T pgbouncer psql -h localhost -p 5432 -U taifabase_user -d pgbouncer -t -c "SHOW CONFIG;" | grep pool_mode | awk '{print $3}')
            echo -e "${BLUE}$pool_mode${NC}"
        fi

        return 0
    else
        echo -e "${RED}✗ PgBouncer not ready${NC}"
        return 1
    fi
}

# Function to check Redis
check_redis() {
    echo -n "Testing Redis connection... "
    
    if docker compose exec -T redis redis-cli -a taifabase_redis_password ping 2>/dev/null | grep -q "PONG"; then
        echo -e "${GREEN}✓ Redis ready${NC}"
        return 0
    else
        echo -e "${RED}✗ Redis not ready${NC}"
        return 1
    fi
}

# Main health check execution
main() {
    local overall_health=0
    
    echo "1. Docker Compose Services Health:"
    echo "--------------------------------"

    # Check core services (Day 2: Added PgBouncer)
    for service in postgres pgbouncer redis; do
        if ! check_service_health "$service"; then
            overall_health=1
        fi
    done

    echo ""
    echo "2. Service Connectivity Tests:"
    echo "-----------------------------"

    # Check service connectivity (Day 2: Updated ports)
    check_service_connectivity "PostgreSQL (Direct)" 5434
    check_service_connectivity "PgBouncer (Pooled)" 5433
    check_service_connectivity "Redis" 6379
    check_service_connectivity "Adminer" 8080
    check_service_connectivity "pgAdmin" 8081
    check_service_connectivity "Grafana" 3000
    check_service_connectivity "Prometheus" 9090

    echo ""
    echo "3. Database-Specific Checks:"
    echo "---------------------------"

    check_postgres
    check_pgbouncer
    check_redis
    
    echo ""
    echo "4. Performance Check:"
    echo "-------------------"
    
    # Measure startup time from last restart
    echo -n "Checking overall startup performance... "
    start_time=$(docker compose ps --format json | jq -r '.[0].RunningFor')
    echo -e "${BLUE}Services running for: $start_time${NC}"
    
    echo ""
    echo "5. Resource Usage:"
    echo "-----------------"
    
    # Show resource usage
    echo "Container resource usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $(docker compose ps -q) 2>/dev/null || echo "Unable to fetch resource stats"
    
    echo ""
    echo "=============================================="
    
    if [ $overall_health -eq 0 ]; then
        echo -e "${GREEN}✓ All critical services are healthy!${NC}"
        echo ""
        echo "Service URLs (Day 2: Updated with PgBouncer):"
        echo "- Database (PgBouncer - Pooled): localhost:5433 [RECOMMENDED]"
        echo "- Database (PostgreSQL - Direct): localhost:5434 [For admin/debugging]"
        echo "- Cache (Redis): localhost:6379"
        echo "- DB Admin (Adminer): http://localhost:8080"
        echo "- DB Admin (pgAdmin): http://localhost:8081"
        echo "- Monitoring (Grafana): http://localhost:3000"
        echo "- Metrics (Prometheus): http://localhost:9090"
        echo "- Reverse Proxy: http://localhost:80"
        echo ""
        echo "Connection Tips:"
        echo "  • Use PgBouncer (port 5433) for all application connections"
        echo "  • Transaction pooling mode preserves RLS session state"
        echo "  • Direct PostgreSQL (port 5434) for maintenance only"
        return 0
    else
        echo -e "${RED}✗ Some services are not healthy${NC}"
        echo ""
        echo "Troubleshooting steps:"
        echo "1. Check logs: docker compose logs [service_name]"
        echo "2. Restart services: docker compose restart"
        echo "3. Rebuild if needed: docker compose up --build"
        return 1
    fi
}

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check if docker compose is available
if ! docker compose version &> /dev/null; then
    echo -e "${RED}Error: docker compose is not available${NC}"
    exit 1
fi

# Check if docker-compose.yml exists
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${RED}Error: $COMPOSE_FILE not found in current directory${NC}"
    exit 1
fi

# Check if services are running
if ! docker compose ps | grep -q "Up"; then
    echo -e "${YELLOW}Warning: No services appear to be running${NC}"
    echo "Start services with: docker compose up -d"
    exit 2
fi

# Run main health check
main
exit $?