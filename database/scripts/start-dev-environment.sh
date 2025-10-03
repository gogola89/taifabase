#!/bin/bash

# Taifabase Development Environment - Startup Script
# This script starts the complete development environment with proper sequencing
# Created by: Raj Patel - DevOps Engineer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTUP_TIMEOUT=300  # 5 minutes
HEALTH_CHECK_SCRIPT="./scripts/health-checks/check-all-services.sh"

echo -e "${BLUE}Taifabase Development Environment - Startup${NC}"
echo "============================================="
echo ""

# Function to print with timestamp
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Function to check if environment is already running
check_existing_environment() {
    if docker compose ps | grep -q "Up"; then
        echo -e "${YELLOW}Warning: Some services are already running${NC}"
        echo "Current status:"
        docker compose ps
        echo ""
        read -p "Do you want to restart the environment? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Stopping existing services..."
            docker compose down
            echo ""
        else
            log "Continuing with existing services..."
            return 1
        fi
    fi
    return 0
}

# Function to pull latest images
pull_images() {
    log "Pulling latest Docker images..."
    docker compose pull --quiet
    echo -e "${GREEN}✓ Images updated${NC}"
    echo ""
}

# Function to start core services first
start_core_services() {
    log "Starting core services (PostgreSQL, Redis)..."
    docker compose up -d postgres redis
    
    # Wait for core services to be healthy
    log "Waiting for core services to be ready..."
    local max_attempts=60  # 5 minutes with 5-second intervals
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec -T postgres pg_isready -U taifabase_user -d taifabase_dev >/dev/null 2>&1 && \
           docker compose exec -T redis redis-cli -a taifabase_redis_password ping 2>/dev/null | grep -q "PONG"; then
            echo -e "${GREEN}✓ Core services are ready${NC}"
            return 0
        fi
        
        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}✗ Core services failed to start within timeout${NC}"
    return 1
}

# Function to start supporting services
start_supporting_services() {
    log "Starting supporting services..."
    docker compose up -d adminer pgadmin prometheus grafana postgres_exporter nginx devtools
    
    # Give services time to initialize
    sleep 10
    echo -e "${GREEN}✓ Supporting services started${NC}"
    echo ""
}

# Function to run post-startup checks
run_post_startup_checks() {
    log "Running post-startup health checks..."
    
    if [ -x "$HEALTH_CHECK_SCRIPT" ]; then
        bash "$HEALTH_CHECK_SCRIPT"
    else
        log "Health check script not found or not executable, running basic checks..."
        
        # Basic connectivity tests
        services=("localhost:5433" "localhost:6379" "localhost:8080" "localhost:8081" "localhost:3000" "localhost:9090")
        for service in "${services[@]}"; do
            host=$(echo $service | cut -d: -f1)
            port=$(echo $service | cut -d: -f2)
            if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
                echo -e "${GREEN}✓ $service is accessible${NC}"
            else
                echo -e "${RED}✗ $service is not accessible${NC}"
            fi
        done
    fi
}

# Function to display environment information
show_environment_info() {
    echo ""
    echo -e "${GREEN}🚀 Taifabase Development Environment is ready!${NC}"
    echo "================================================"
    echo ""
    echo "Service URLs:"
    echo "  📊 Database Admin (Adminer):    http://localhost:8080"
    echo "  🗄️  Database Admin (pgAdmin):    http://localhost:8081"
    echo "  📈 Monitoring (Grafana):        http://localhost:3000"
    echo "  🔍 Metrics (Prometheus):        http://localhost:9090"
    echo "  🌐 Reverse Proxy:               http://localhost:80"
    echo ""
    echo "Database Connection:"
    echo "  🐘 PostgreSQL:                  localhost:5433"
    echo "     Database: taifabase_dev"
    echo "     Username: taifabase_user"
    echo "     Password: taifabase_dev_password"
    echo ""
    echo "  🔴 Redis:                        localhost:6379"
    echo "     Password: taifabase_redis_password"
    echo ""
    echo "Useful Commands:"
    echo "  📋 Check status:                docker compose ps"
    echo "  📄 View logs:                   docker compose logs [service]"
    echo "  🔄 Restart service:             docker compose restart [service]"
    echo "  ⛔ Stop environment:            docker compose down"
    echo "  🔧 Health check:                ./scripts/health-checks/check-all-services.sh"
    echo ""
    echo "Development Tips:"
    echo "  • Use 'docker compose exec postgres psql -U taifabase_user -d taifabase_dev' for direct DB access"
    echo "  • Use 'docker compose exec devtools sh' for a development shell"
    echo "  • Log files are persisted in Docker volumes"
    echo "  • Configuration changes require service restart"
    echo ""
}

# Function to handle cleanup on script exit
cleanup() {
    if [ $? -ne 0 ]; then
        echo ""
        echo -e "${RED}Startup failed. Checking service status...${NC}"
        docker compose ps
        echo ""
        echo "View logs with: docker compose logs"
        echo "Clean up with: docker compose down"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Main execution
main() {
    # Check prerequisites
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: docker is not installed${NC}"
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        echo -e "${RED}Error: docker compose is not available${NC}"
        exit 1
    fi
    
    if [ ! -f "docker-compose.yml" ]; then
        echo -e "${RED}Error: docker-compose.yml not found${NC}"
        exit 1
    fi
    
    # Check if environment file exists
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}Warning: .env file not found. Using default values.${NC}"
        echo "Create .env file from .env.example for customization"
        echo ""
    fi
    
    # Start the environment
    check_existing_environment || return 0
    
    log "Starting Taifabase development environment..."
    echo ""
    
    # Record start time
    start_time=$(date +%s)
    
    # Pull latest images
    pull_images
    
    # Start services in proper order
    start_core_services || exit 1
    start_supporting_services
    
    # Calculate startup time
    end_time=$(date +%s)
    startup_duration=$((end_time - start_time))
    
    log "Total startup time: ${startup_duration} seconds"
    
    if [ $startup_duration -lt 300 ]; then  # Less than 5 minutes
        echo -e "${GREEN}✓ Startup time target met (<5 minutes)${NC}"
    else
        echo -e "${YELLOW}⚠ Startup time exceeded 5-minute target${NC}"
    fi
    
    echo ""
    
    # Run health checks
    run_post_startup_checks
    
    # Show environment information
    show_environment_info
}

# Check for command line arguments
case "${1:-}" in
    --help|-h)
        echo "Taifabase Development Environment Startup Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --pull         Force pull latest images before starting"
        echo "  --clean        Clean environment before starting"
        echo ""
        exit 0
        ;;
    --pull)
        log "Force pulling latest images..."
        docker compose pull
        ;;
    --clean)
        log "Cleaning environment..."
        docker compose down -v --remove-orphans
        docker system prune -f
        ;;
esac

# Execute main function
main "$@"