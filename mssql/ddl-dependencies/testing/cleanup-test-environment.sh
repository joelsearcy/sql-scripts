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
