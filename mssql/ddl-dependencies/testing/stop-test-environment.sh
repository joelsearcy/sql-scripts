#!/bin/bash
# Stop the test environment

echo "Stopping SQL Server test environment..."
cd "$(dirname "$0")"
docker-compose -f docker-compose.test.yml --env-file .env.test down

echo "Test environment stopped."
echo "To remove all data, run: rm -rf data/ logs/"
