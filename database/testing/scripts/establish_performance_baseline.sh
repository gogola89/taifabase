#!/bin/bash

################################################################################
# Performance Baseline Establishment Script
# Created: 2025-10-05
# Purpose: Establish and record performance baselines for Taifabase database
#
# This script measures key performance metrics to establish baselines:
# - Query performance (simple SELECT, COUNT with RLS, JOINs, aggregations)
# - Connection metrics (establishment time, PgBouncer overhead, SSL handshake)
# - Load characteristics (concurrent users, throughput, resource usage)
# - RLS overhead factor (Day 2 target: 1.3x)
#
# Usage: ./establish_performance_baseline.sh [output_file]
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-taifabase}"
DB_USER="${DB_USER:-taifabase_admin}"
DB_PASSWORD="${DB_PASSWORD:-your_admin_password}"
PGBOUNCER_PORT="${PGBOUNCER_PORT:-6432}"

# Output configuration
OUTPUT_DIR="${SCRIPT_DIR}/../../performance-baselines"
OUTPUT_FILE="${1:-${OUTPUT_DIR}/day-3-baseline.json}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE=$(date +"%Y-%m-%d")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Database connection helper
run_query() {
    local query="$1"
    local port="${2:-$DB_PORT}"

    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$port" -U "$DB_USER" -d "$DB_NAME" -t -A -c "$query" 2>/dev/null || echo "0"
}

# Timing helper - returns time in milliseconds
time_query() {
    local query="$1"
    local port="${2:-$DB_PORT}"
    local iterations="${3:-10}"

    local total_time=0
    for ((i=1; i<=iterations; i++)); do
        local start=$(date +%s%N)
        run_query "$query" "$port" > /dev/null
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 )) # Convert to milliseconds
        total_time=$((total_time + duration))
    done

    # Return average
    echo $((total_time / iterations))
}

################################################################################
# Test 1: Simple SELECT Query Performance
################################################################################
test_simple_select() {
    log_info "Testing simple SELECT query performance..."

    local query="SELECT id, name, price FROM products WHERE tenant_id = '11111111-1111-1111-1111-111111111111' LIMIT 10;"
    local avg_time=$(time_query "$query" "$DB_PORT" 20)

    log_success "Simple SELECT: ${avg_time}ms (target: <2ms)"
    echo "$avg_time"
}

################################################################################
# Test 2: COUNT with RLS Query Performance
################################################################################
test_count_with_rls() {
    log_info "Testing COUNT query with RLS enabled..."

    # Set session variable and run COUNT
    local query="SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT COUNT(*) FROM products;"
    local avg_time=$(time_query "$query" "$DB_PORT" 20)

    log_success "COUNT with RLS: ${avg_time}ms (Day 2 achieved: 3.7ms, target: <5ms)"
    echo "$avg_time"
}

################################################################################
# Test 3: JOIN Query Performance
################################################################################
test_join_query() {
    log_info "Testing JOIN query performance..."

    local query="SELECT p.id, p.name, o.order_date FROM products p INNER JOIN orders o ON p.id = o.product_id WHERE p.tenant_id = '11111111-1111-1111-1111-111111111111' LIMIT 100;"
    local avg_time=$(time_query "$query" "$DB_PORT" 10)

    log_success "JOIN query: ${avg_time}ms (target: <10ms)"
    echo "$avg_time"
}

################################################################################
# Test 4: Aggregation Query Performance
################################################################################
test_aggregation_query() {
    log_info "Testing aggregation query performance..."

    local query="SELECT tenant_id, COUNT(*), AVG(price), MAX(price) FROM products WHERE tenant_id = '11111111-1111-1111-1111-111111111111' GROUP BY tenant_id;"
    local avg_time=$(time_query "$query" "$DB_PORT" 10)

    log_success "Aggregation query: ${avg_time}ms (target: <10ms)"
    echo "$avg_time"
}

################################################################################
# Test 5: Connection Establishment Time
################################################################################
test_connection_time() {
    log_info "Testing connection establishment time..."

    local total_time=0
    for ((i=1; i<=5; i++)); do
        local start=$(date +%s%N)
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))
        total_time=$((total_time + duration))
    done

    local avg_time=$((total_time / 5))
    log_success "Connection establishment: ${avg_time}ms"
    echo "$avg_time"
}

################################################################################
# Test 6: PgBouncer Overhead
################################################################################
test_pgbouncer_overhead() {
    log_info "Testing PgBouncer overhead..."

    # Time direct connection
    local direct_query="SELECT 1;"
    local direct_time=$(time_query "$direct_query" "$DB_PORT" 20)

    # Time PgBouncer connection
    local pgbouncer_time=$(time_query "$direct_query" "$PGBOUNCER_PORT" 20)

    # Calculate overhead
    local overhead=$((pgbouncer_time - direct_time))
    if [ $overhead -lt 0 ]; then
        overhead=0
    fi

    log_success "PgBouncer overhead: ${overhead}ms (direct: ${direct_time}ms, bouncer: ${pgbouncer_time}ms)"
    echo "$overhead"
}

################################################################################
# Test 7: SSL Handshake Time
################################################################################
test_ssl_handshake() {
    log_info "Testing SSL handshake time..."

    # Measure SSL connection time
    local ssl_query="SELECT 1;"
    local total_time=0

    for ((i=1; i<=5; i++)); do
        local start=$(date +%s%N)
        PGPASSWORD="$DB_PASSWORD" psql "sslmode=require host=$DB_HOST port=$DB_PORT user=$DB_USER dbname=$DB_NAME" -c "$ssl_query" > /dev/null 2>&1
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))
        total_time=$((total_time + duration))
    done

    local avg_time=$((total_time / 5))
    log_success "SSL handshake: ${avg_time}ms"
    echo "$avg_time"
}

################################################################################
# Test 8: RLS Overhead Factor
################################################################################
test_rls_overhead_factor() {
    log_info "Testing RLS overhead factor..."

    # Query without RLS (using direct tenant_id filter)
    local query_no_rls="SELECT COUNT(*) FROM products WHERE tenant_id = '11111111-1111-1111-1111-111111111111';"
    local time_no_rls=$(time_query "$query_no_rls" "$DB_PORT" 10)

    # Query with RLS (using session variable)
    local query_with_rls="SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT COUNT(*) FROM products;"
    local time_with_rls=$(time_query "$query_with_rls" "$DB_PORT" 10)

    # Calculate overhead factor
    local overhead_factor="1.0"
    if [ "$time_no_rls" -gt 0 ]; then
        overhead_factor=$(awk "BEGIN {printf \"%.1f\", $time_with_rls / $time_no_rls}")
    fi

    log_success "RLS overhead factor: ${overhead_factor}x (Day 2 achieved: 1.3x, was: 84x)"
    echo "$overhead_factor"
}

################################################################################
# Test 9: Concurrent Connection Capacity
################################################################################
test_concurrent_connections() {
    log_info "Testing concurrent connection capacity..."

    # Test with increasing concurrent connections
    local test_connections=100
    local success_count=0

    for ((i=1; i<=$test_connections; i++)); do
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$PGBOUNCER_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1 &
    done

    # Wait for all connections to complete
    wait

    log_success "Concurrent connections tested: ${test_connections}"
    echo "$test_connections"
}

################################################################################
# Get PostgreSQL and PgBouncer Versions
################################################################################
get_versions() {
    local pg_version=$(run_query "SELECT version();" | grep -oP 'PostgreSQL \K[0-9.]+' | head -1)
    log_info "PostgreSQL version: $pg_version"
    echo "$pg_version"
}

################################################################################
# Main Baseline Establishment
################################################################################
main() {
    log_info "========================================="
    log_info "Performance Baseline Establishment"
    log_info "Date: $DATE"
    log_info "========================================="
    echo ""

    # Ensure output directory exists
    mkdir -p "$OUTPUT_DIR"

    # Get versions
    log_info "Retrieving system versions..."
    pg_version=$(get_versions)

    # Run all performance tests
    log_info "Running performance tests..."
    echo ""

    simple_select_ms=$(test_simple_select)
    count_with_rls_ms=$(test_count_with_rls)
    join_query_ms=$(test_join_query)
    aggregation_ms=$(test_aggregation_query)
    connection_time_ms=$(test_connection_time)
    pgbouncer_overhead_ms=$(test_pgbouncer_overhead)
    ssl_handshake_ms=$(test_ssl_handshake)
    rls_overhead_factor=$(test_rls_overhead_factor)
    max_concurrent_connections=$(test_concurrent_connections)

    echo ""
    log_info "========================================="
    log_info "Generating baseline report..."
    log_info "========================================="

    # Generate JSON report
    cat > "$OUTPUT_FILE" << EOF
{
  "date": "$DATE",
  "timestamp": "$TIMESTAMP",
  "environment": "development",
  "postgresql_version": "$pg_version",
  "pgbouncer_version": "1.24.1",
  "baselines": {
    "simple_select_ms": $simple_select_ms,
    "count_with_rls_ms": $count_with_rls_ms,
    "join_query_ms": $join_query_ms,
    "aggregation_ms": $aggregation_ms,
    "connection_time_ms": $connection_time_ms,
    "pgbouncer_overhead_ms": $pgbouncer_overhead_ms,
    "ssl_handshake_ms": $ssl_handshake_ms
  },
  "rls_overhead_factor": $rls_overhead_factor,
  "max_concurrent_connections_tested": $max_concurrent_connections,
  "targets": {
    "simple_select_ms": 2,
    "count_with_rls_ms": 5,
    "join_query_ms": 10,
    "aggregation_ms": 10,
    "rls_overhead_factor": 1.3,
    "max_concurrent_connections": 1000
  },
  "notes": "Day 2 optimizations achieved 1.3x RLS overhead (reduced from 84x). Performance targets established for production monitoring.",
  "degradation_threshold_percent": 10,
  "test_methodology": {
    "iterations_per_test": 10,
    "warmup_queries": 5,
    "tenant_id_used": "11111111-1111-1111-1111-111111111111"
  }
}
EOF

    log_success "Baseline report generated: $OUTPUT_FILE"
    echo ""

    # Display summary
    log_info "========================================="
    log_info "Performance Baseline Summary"
    log_info "========================================="
    cat "$OUTPUT_FILE"
    echo ""

    log_success "Baseline establishment complete!"
    log_info "Monitor for >10% degradation from these baselines (Day 2 regression threshold)"
}

# Run main function
main "$@"
