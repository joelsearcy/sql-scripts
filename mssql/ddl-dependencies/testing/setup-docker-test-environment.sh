#!/bin/bash

# Docker Test Environment Setup Script
# Author: Joel Searcy
# Created: September 2025
#
# Purpose: Set up Docker containers for testing ToggleSchemabinding procedures
# across SQL Server 2019, 2022, and 2025 versions
#
# Prerequisites:
# - Docker and Docker Compose installed
# - At least 8GB RAM available
# - 20GB disk space for all containers

set -e  # Exit on any error

echo "================================================================================"
echo "SQL Server ToggleSchemabinding Testing Environment Setup"
echo "================================================================================"
echo ""

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.test.yml"
ENV_FILE="$SCRIPT_DIR/.env.test"

# SQL Server versions to test
SQL_2019_IMAGE="mcr.microsoft.com/mssql/server:2019-latest"
SQL_2022_IMAGE="mcr.microsoft.com/mssql/server:2022-latest"
SQL_2025_IMAGE="mcr.microsoft.com/mssql/server:2025-latest"

# Default password (should be changed for production)
SA_PASSWORD="StrongPassword123!"

# Network configuration
DOCKER_NETWORK="sqlserver-test-network"

# Function to check Docker installation
check_docker() {
    echo "Checking Docker installation..."
    if ! command -v docker &> /dev/null; then
        echo "ERROR: Docker is not installed or not in PATH"
        echo "Please install Docker from https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo "ERROR: Docker Compose is not installed or not in PATH"
        echo "Please install Docker Compose from https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    echo "✓ Docker and Docker Compose are available"
}

# Function to check system resources
check_resources() {
    echo "Checking system resources..."
    
    # Check available memory (Linux/macOS)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        AVAILABLE_RAM=$(free -g | awk '/^Mem:/{print $7}')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        AVAILABLE_RAM=$(vm_stat | awk '/Pages free:/{print $3}' | sed 's/\.//' | awk '{print $1 * 4 / 1024 / 1024}')
    else
        echo "WARNING: Cannot check available RAM on this OS. Ensure you have at least 8GB available."
        AVAILABLE_RAM=8
    fi
    
    if [[ $AVAILABLE_RAM -lt 6 ]]; then
        echo "WARNING: Less than 6GB RAM available. SQL Server containers may not start properly."
        echo "Available RAM: ${AVAILABLE_RAM}GB"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✓ Sufficient RAM available: ${AVAILABLE_RAM}GB"
    fi
    
    # Check available disk space
    AVAILABLE_DISK=$(df -h "$SCRIPT_DIR" | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $AVAILABLE_DISK -lt 15 ]]; then
        echo "WARNING: Less than 15GB disk space available."
        echo "Available disk space: ${AVAILABLE_DISK}GB"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✓ Sufficient disk space available: ${AVAILABLE_DISK}GB"
    fi
}

# Function to create environment file
create_env_file() {
    echo "Creating environment configuration..."
    
    cat > "$ENV_FILE" << EOF
# SQL Server Test Environment Configuration
# Generated: $(date)

# SQL Server SA Password
SA_PASSWORD=$SA_PASSWORD

# SQL Server Images
SQL_2019_IMAGE=$SQL_2019_IMAGE
SQL_2022_IMAGE=$SQL_2022_IMAGE
SQL_2025_IMAGE=$SQL_2025_IMAGE

# Port mappings (external:internal)
SQL_2019_PORT=1419:1433
SQL_2022_PORT=1422:1433
SQL_2025_PORT=1425:1433

# Container names
SQL_2019_CONTAINER=sqlserver-2019-test
SQL_2022_CONTAINER=sqlserver-2022-test
SQL_2025_CONTAINER=sqlserver-2025-test

# Network
DOCKER_NETWORK=$DOCKER_NETWORK

# Volume paths
SCRIPTS_PATH=$SCRIPT_DIR
DATA_PATH=$SCRIPT_DIR/data
LOGS_PATH=$SCRIPT_DIR/logs
EOF
    
    echo "✓ Environment file created: $ENV_FILE"
}

# Function to create Docker Compose file
create_docker_compose() {
    echo "Creating Docker Compose configuration..."
    
    mkdir -p "$SCRIPT_DIR/data"
    mkdir -p "$SCRIPT_DIR/logs"
    
    cat > "$DOCKER_COMPOSE_FILE" << 'EOF'
networks:
  sqlserver-test-network:
    driver: bridge

services:
  sqlserver-2019:
    image: ${SQL_2019_IMAGE}
    container_name: ${SQL_2019_CONTAINER}
    hostname: sqlserver-2019
    user: "0:0"  # Run as root to avoid permission issues with mounted volumes
    environment:
      - ACCEPT_EULA=Y
      - SA_PASSWORD=${SA_PASSWORD}
      - MSSQL_PID=Developer
      - MSSQL_AGENT_ENABLED=true
      - MSSQL_ENABLE_HADR=1
      - MSSQL_RUN_AS_ROOT=1  # Explicitly allow running as root
    ports:
      - "1419:1433"
    volumes:
      - ./data/sql2019:/var/opt/mssql/data:rw
      - ./logs/sql2019:/var/opt/mssql/log:rw
      - ./test-results:/test-results:rw
      - ${SCRIPTS_PATH}:/scripts:ro
    networks:
      - sqlserver-test-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P '${SA_PASSWORD}' -C -Q 'SELECT 1' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  sqlserver-2022:
    image: ${SQL_2022_IMAGE}
    container_name: ${SQL_2022_CONTAINER}
    hostname: sqlserver-2022
    user: "0:0"  # Run as root to avoid permission issues with mounted volumes
    environment:
      - ACCEPT_EULA=Y
      - SA_PASSWORD=${SA_PASSWORD}
      - MSSQL_PID=Developer
      - MSSQL_AGENT_ENABLED=true
      - MSSQL_ENABLE_HADR=1
      - MSSQL_RUN_AS_ROOT=1  # Explicitly allow running as root
    ports:
      - "1422:1433"
    volumes:
      - ./data/sql2022:/var/opt/mssql/data:rw
      - ./logs/sql2022:/var/opt/mssql/log:rw
      - ./test-results:/test-results:rw
      - ${SCRIPTS_PATH}:/scripts:ro
    networks:
      - sqlserver-test-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P '${SA_PASSWORD}' -C -Q 'SELECT 1' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  sqlserver-2025:
    image: ${SQL_2025_IMAGE}
    container_name: ${SQL_2025_CONTAINER}
    hostname: sqlserver-2025
    user: "0:0"  # Run as root to avoid permission issues with mounted volumes
    environment:
      - ACCEPT_EULA=Y
      - SA_PASSWORD=${SA_PASSWORD}
      - MSSQL_PID=Developer
      - MSSQL_AGENT_ENABLED=true
      - MSSQL_ENABLE_HADR=1
      - MSSQL_RUN_AS_ROOT=1  # Explicitly allow running as root
    ports:
      - "1425:1433"
    volumes:
      - ./data/sql2025:/var/opt/mssql/data:rw
      - ./logs/sql2025:/var/opt/mssql/log:rw
      - ./test-results:/test-results:rw
      - ${SCRIPTS_PATH}:/scripts:ro
    networks:
      - sqlserver-test-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P '${SA_PASSWORD}' -C -Q 'SELECT 1' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # SQL Server client container for running tests
  sqlserver-client:
    image: ${SQL_2022_IMAGE}
    container_name: sqlserver-test-client
    hostname: test-client
    environment:
      - ACCEPT_EULA=Y
    volumes:
      - ${SCRIPTS_PATH}:/scripts:rw
      - ./test-results:/test-results:rw
    networks:
      - sqlserver-test-network
    command: sleep infinity
    restart: unless-stopped

EOF
    
    echo "✓ Docker Compose file created: $DOCKER_COMPOSE_FILE"
}

# Function to pull Docker images
pull_images() {
    echo "Pulling SQL Server Docker images..."
    echo "This may take several minutes depending on your internet connection..."
    
    echo "Pulling SQL Server 2019..."
    docker pull $SQL_2019_IMAGE
    
    echo "Pulling SQL Server 2022..."
    docker pull $SQL_2022_IMAGE
    
    echo "Pulling SQL Server 2025..."
    docker pull $SQL_2025_IMAGE
    
    echo "✓ Docker images pulled successfully"
}

# Function to prepare data directories with correct permissions
prepare_data_directories() {
    echo "Preparing data directories with correct permissions..."
    
    # Remove any existing directories that might have restrictive permissions
    if [ -d "$SCRIPT_DIR/data" ] || [ -d "$SCRIPT_DIR/logs" ]; then
        echo "Removing existing data/logs directories to reset permissions..."
        sudo rm -rf "$SCRIPT_DIR/data" "$SCRIPT_DIR/logs" 2>/dev/null || true
    fi
    
    # Create data and log directories if they don't exist
    mkdir -p "$SCRIPT_DIR/data/sql2019"
    mkdir -p "$SCRIPT_DIR/data/sql2022"
    mkdir -p "$SCRIPT_DIR/data/sql2025"
    mkdir -p "$SCRIPT_DIR/logs/sql2019"
    mkdir -p "$SCRIPT_DIR/logs/sql2022"
    mkdir -p "$SCRIPT_DIR/logs/sql2025"
    
    # Set proper permissions for SQL Server 2025 (which runs as non-root by default)
    # Make directories readable/writable by all users to ensure compatibility
    chmod 777 "$SCRIPT_DIR/data/sql2025" || {
        echo "WARNING: Could not set permissions on sql2025 data directory"
        echo "You may need to run: sudo chmod 777 $SCRIPT_DIR/data/sql2025"
    }
    chmod 777 "$SCRIPT_DIR/logs/sql2025" || {
        echo "WARNING: Could not set permissions on sql2025 logs directory"
        echo "You may need to run: sudo chmod 777 $SCRIPT_DIR/logs/sql2025"
    }
    
    # Also set permissions for other versions for consistency
    chmod 755 "$SCRIPT_DIR/data/sql2019" 2>/dev/null || true
    chmod 755 "$SCRIPT_DIR/data/sql2022" 2>/dev/null || true
    chmod 755 "$SCRIPT_DIR/logs/sql2019" 2>/dev/null || true
    chmod 755 "$SCRIPT_DIR/logs/sql2022" 2>/dev/null || true
    
    echo "✓ Data directories prepared successfully"
}

# Function to start containers
start_containers() {
    echo "Starting SQL Server containers..."
    
    cd "$SCRIPT_DIR"
    docker-compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d
    
    echo "Waiting for SQL Server instances to be ready..."
    echo "This may take 2-3 minutes for initial startup..."
    
    # Wait for containers to be healthy
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if docker-compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" ps | grep -q "healthy"; then
            echo "✓ SQL Server containers are ready"
            break
        fi
        
        echo "Waiting for SQL Server to start... (${wait_time}s elapsed)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        echo "WARNING: Containers may not be fully ready yet. Check with 'docker-compose ps'"
    fi
}

# Function to test connections
test_connections() {
    echo "Testing SQL Server connections..."
    
    # Test SQL Server 2019
    echo "Testing SQL Server 2019 (port 1419)..."
    if docker exec sqlserver-2019-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT @@VERSION" &>/dev/null; then
        echo "✓ SQL Server 2019 connection successful"
    else
        echo "✗ SQL Server 2019 connection failed"
    fi
    
    # Test SQL Server 2022
    echo "Testing SQL Server 2022 (port 1422)..."
    if docker exec sqlserver-2022-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT @@VERSION" &>/dev/null; then
        echo "✓ SQL Server 2022 connection successful"
    else
        echo "✗ SQL Server 2022 connection failed"
    fi
    
    # Test SQL Server 2025
    echo "Testing SQL Server 2025 (port 1425)..."
    if docker exec sqlserver-2025-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT @@VERSION" &>/dev/null; then
        echo "✓ SQL Server 2025 connection successful"
    else
        echo "✗ SQL Server 2025 connection failed"
    fi
}

# Function to create helper scripts
create_helper_scripts() {
    echo "Creating helper scripts..."
    
    # Create connection test script
    cat > "$SCRIPT_DIR/test-connections.sh" << 'EOF'
#!/bin/bash
# Test connections to all SQL Server instances

echo "Testing SQL Server connections..."
echo "================================="

# Load environment
source "$(dirname "$0")/.env.test"

echo "SQL Server 2019 (localhost:1419):"
docker exec sqlserver-2019-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT 'SQL Server 2019: ' + @@VERSION"
echo ""

echo "SQL Server 2022 (localhost:1422):"
docker exec sqlserver-2022-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT 'SQL Server 2022: ' + @@VERSION"
echo ""

echo "SQL Server 2025 (localhost:1425):"
docker exec sqlserver-2025-test /opt/mssql-tools18/bin/sqlcmd -S localhost -U SA -P "$SA_PASSWORD" -C -Q "SELECT 'SQL Server 2025: ' + @@VERSION"
echo ""
EOF
    
    chmod +x "$SCRIPT_DIR/test-connections.sh"
    
    # Create stop script
    cat > "$SCRIPT_DIR/stop-test-environment.sh" << 'EOF'
#!/bin/bash
# Stop the test environment

echo "Stopping SQL Server test environment..."
cd "$(dirname "$0")"
docker-compose -f docker-compose.test.yml --env-file .env.test down

echo "Test environment stopped."
echo "To remove all data, run: rm -rf data/ logs/"
EOF
    
    chmod +x "$SCRIPT_DIR/stop-test-environment.sh"
    
    # Create cleanup script
    cat > "$SCRIPT_DIR/cleanup-test-environment.sh" << 'EOF'
#!/bin/bash
# Clean up the test environment completely

echo "Cleaning up SQL Server test environment..."
cd "$(dirname "$0")"

# Stop containers
docker-compose -f docker-compose.test.yml --env-file .env.test down -v

# Remove data and logs
read -p "Remove all test data and logs? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf data/ logs/ test-results/
    echo "✓ Data and logs removed"
fi

# Remove images (optional)
read -p "Remove SQL Server Docker images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker rmi mcr.microsoft.com/mssql/server:2019-latest
    docker rmi mcr.microsoft.com/mssql/server:2022-latest
    docker rmi mcr.microsoft.com/mssql/server:2025-preview-latest 2>/dev/null || true
    echo "✓ Docker images removed"
fi

echo "Cleanup complete!"
EOF
    
    chmod +x "$SCRIPT_DIR/cleanup-test-environment.sh"
    
    # Create run tests script
    cat > "$SCRIPT_DIR/run-all-tests.sh" << 'EOF'
#!/bin/bash
# Run tests against all SQL Server versions

echo "Running ToggleSchemabinding tests against all SQL Server versions..."
echo "===================================================================="

# Load environment
source "$(dirname "$0")/.env.test"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/test-results"
mkdir -p "$RESULTS_DIR"

# Function to run SQL script
run_sql_script() {
    local server=$1
    local port=$2
    local script_path=$3
    local output_file=$4
    
    echo "Running $script_path on $server..."
    docker exec ${server} /opt/mssql-tools18/bin/sqlcmd \
        -S localhost \
        -U SA \
        -P "$SA_PASSWORD" \
        -i "/scripts/$script_path" \
        -o "/test-results/$output_file" \
        -e -W -C
}

# Function to run SQL script from /tmp/ directory
run_tmp_sql_script() {
    local server=$1
    local port=$2
    local script_path=$3
    local output_file=$4
    local db_name=$5
    
    echo "Running $script_path on $server..."
    docker exec ${server} /opt/mssql-tools18/bin/sqlcmd \
        -S localhost \
        -U SA \
        -P "$SA_PASSWORD" \
        -i "/tmp/$script_path" \
        -o "/test-results/$output_file" \
        -d "$db_name" \
        -e -W -C
}

# Create test databases on all instances
echo "Setting up test databases..."

# First, initialize databases and schemas
run_sql_script "sqlserver-2019-test" "1419" "00-initialize-database.sql" "init-2019.log"
run_sql_script "sqlserver-2022-test" "1422" "00-initialize-database.sql" "init-2022.log"
run_sql_script "sqlserver-2025-test" "1425" "00-initialize-database.sql" "init-2025.log"

# Then create the complex schema objects
run_sql_script "sqlserver-2019-test" "1419" "01-setup-complex-enterprise-schema.sql" "setup-2019.log"
run_sql_script "sqlserver-2022-test" "1422" "01-setup-complex-enterprise-schema.sql" "setup-2022.log"
run_sql_script "sqlserver-2025-test" "1425" "01-setup-complex-enterprise-schema.sql" "setup-2025.log"

# Install procedures on each version
echo "Installing procedures..."

# Create ToggleSchemabinding procedures on all instances
run_sql_script "sqlserver-2019-test" "1419" "02-setup-toggle-schemabinding.sql" "install-2019.log"
run_sql_script "sqlserver-2022-test" "1422" "02-setup-toggle-schemabinding.sql" "install-2022.log"
run_sql_script "sqlserver-2025-test" "1425" "02-setup-toggle-schemabinding.sql" "install-2025.log"

# Run performance tests
echo "Running performance tests..."
echo "EXEC Performance.sp_RunPerformanceTests 'SQL Server 2019', 'SQL2019', 30, 1" > /tmp/perf_test_2019.sql
echo "EXEC Performance.sp_RunPerformanceTests 'SQL Server 2022', 'SQL2022', 30, 1" > /tmp/perf_test_2022.sql
echo "EXEC Performance.sp_RunPerformanceTests 'SQL Server 2025', 'SQL2025', 30, 1" > /tmp/perf_test_2025.sql

# Copy test scripts to containers and run
docker cp /tmp/perf_test_2019.sql sqlserver-2019-test:/tmp/
docker cp /tmp/perf_test_2022.sql sqlserver-2022-test:/tmp/
docker cp /tmp/perf_test_2025.sql sqlserver-2025-test:/tmp/

run_tmp_sql_script "sqlserver-2019-test" "1419" "perf_test_2019.sql" "performance-2019.log" "SchemabindingTestDB"
run_tmp_sql_script "sqlserver-2022-test" "1422" "perf_test_2022.sql" "performance-2022.log" "SchemabindingTestDB"
run_tmp_sql_script "sqlserver-2025-test" "1425" "perf_test_2025.sql" "performance-2025.log" "SchemabindingTestDB"

# Run correctness validation
echo "Running correctness validation..."
echo "EXEC Validation.sp_RunCorrectnessValidation 'SQL Server 2019', 'SQL2019'" > /tmp/validation_2019.sql
echo "EXEC Validation.sp_RunCorrectnessValidation 'SQL Server 2022', 'SQL2022'" > /tmp/validation_2022.sql
echo "EXEC Validation.sp_RunCorrectnessValidation 'SQL Server 2025', 'SQL2025'" > /tmp/validation_2025.sql

docker cp /tmp/validation_2019.sql sqlserver-2019-test:/tmp/
docker cp /tmp/validation_2022.sql sqlserver-2022-test:/tmp/
docker cp /tmp/validation_2025.sql sqlserver-2025-test:/tmp/

run_tmp_sql_script "sqlserver-2019-test" "1419" "validation_2019.sql" "validation-2019.log" "SchemabindingTestDB"
run_tmp_sql_script "sqlserver-2022-test" "1422" "validation_2022.sql" "validation-2022.log" "SchemabindingTestDB"
run_tmp_sql_script "sqlserver-2025-test" "1425" "validation_2025.sql" "validation-2025.log" "SchemabindingTestDB"

echo ""
echo "All tests completed!"
echo "Results are available in: $RESULTS_DIR"
echo ""
echo "To view results:"
echo "  ls -la $RESULTS_DIR"
echo "  cat $RESULTS_DIR/performance-*.log"
echo "  cat $RESULTS_DIR/validation-*.log"
EOF
    
    chmod +x "$SCRIPT_DIR/run-all-tests.sh"
    
    echo "✓ Helper scripts created:"
    echo "  - test-connections.sh: Test connectivity to all instances"
    echo "  - stop-test-environment.sh: Stop all containers"
    echo "  - cleanup-test-environment.sh: Clean up everything"
    echo "  - run-all-tests.sh: Run complete test suite"
}

# Function to display connection information
display_connection_info() {
    echo ""
    echo "================================================================================"
    echo "SQL Server Test Environment Ready!"
    echo "================================================================================"
    echo ""
    echo "Connection Information:"
    echo "----------------------"
    echo "SQL Server 2019:"
    echo "  Host: localhost"
    echo "  Port: 1419"
    echo "  Username: SA"
    echo "  Password: $SA_PASSWORD"
    echo ""
    echo "SQL Server 2022:"
    echo "  Host: localhost"
    echo "  Port: 1422"
    echo "  Username: SA"
    echo "  Password: $SA_PASSWORD"
    echo ""
    echo "SQL Server 2025:"
    echo "  Host: localhost"
    echo "  Port: 1425"
    echo "  Username: SA"
    echo "  Password: $SA_PASSWORD"
    echo ""
    echo "Available Scripts:"
    echo "-----------------"
    echo "  ./test-connections.sh          - Test all connections"
    echo "  ./run-all-tests.sh            - Run complete test suite"
    echo "  ./stop-test-environment.sh     - Stop containers"
    echo "  ./cleanup-test-environment.sh  - Full cleanup"
    echo ""
    echo "Docker Commands:"
    echo "---------------"
    echo "  docker-compose ps              - Check container status"
    echo "  docker-compose logs            - View container logs"
    echo "  docker-compose logs -f         - Follow container logs"
    echo ""
    echo "To connect with sqlcmd:"
    echo "  # SQL Server 2019"
    echo "  sqlcmd -S localhost,1419 -U SA -P '$SA_PASSWORD'"
    echo ""
    echo "  # SQL Server 2022"
    echo "  sqlcmd -S localhost,1422 -U SA -P '$SA_PASSWORD'"
    echo ""
    echo "  # SQL Server 2025"
    echo "  sqlcmd -S localhost,1425 -U SA -P '$SA_PASSWORD'"
    echo ""
    echo "Next Steps:"
    echo "----------"
    echo "1. Test connections: ./test-connections.sh"
    echo "2. Run tests: ./run-all-tests.sh"
    echo "3. Review results in: ./test-results/"
    echo ""
}

# Main execution
main() {
    echo "Starting SQL Server test environment setup..."
    echo ""
    
    check_docker
    check_resources
    create_env_file
    create_docker_compose
    pull_images
    prepare_data_directories
    start_containers
    test_connections
    create_helper_scripts
    display_connection_info
    
    echo "Setup completed successfully!"
}

# Run main function
main "$@"