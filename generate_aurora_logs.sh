#!/bin/bash

# Aurora MySQL Log Generator Script
# This script connects to Aurora MySQL and generates slow queries and errors

echo "========================================="
echo "Aurora MySQL Log Generator"
echo "========================================="

# Connection details
HOST="aurora-mysql-poc-01-instance-1.cepmue6m8uzp.us-east-1.rds.amazonaws.com"
USER="admin"
PASSWORD="Mzn1442000"
DATABASE="mydb"

echo "Connecting to Aurora MySQL at $HOST..."

# Function to run MySQL commands
run_mysql() {
    mysql -h "$HOST" -u "$USER" -p"$PASSWORD" "$DATABASE" -e "$1" 2>&1
}

# Create test database and table
echo -e "\n1. Creating test table..."
run_mysql "CREATE DATABASE IF NOT EXISTS log_test;"
run_mysql "USE log_test; CREATE TABLE IF NOT EXISTS test_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);"

# Insert test data
echo -e "\n2. Inserting test data..."
for i in {1..100}; do
    run_mysql "USE log_test; INSERT INTO test_data (data) VALUES ('Test record $i');"
done

echo -e "\n3. Generating SLOW QUERIES (these will appear in slow query log)..."

# Slow Query 1: Using SLEEP
echo "   - Running query with SLEEP(5)..."
run_mysql "SELECT 'Slow Query 1', SLEEP(5);"

# Slow Query 2: Heavy computation
echo "   - Running BENCHMARK query..."
run_mysql "SELECT 'Slow Query 2', BENCHMARK(100000000, MD5('test'));"

# Slow Query 3: Large table scan
echo "   - Running full table scan..."
run_mysql "USE log_test; SELECT COUNT(*) FROM test_data t1, test_data t2 WHERE t1.id > 0 AND t2.id > 0;"

# Slow Query 4: Complex subquery
echo "   - Running complex subquery..."
run_mysql "USE log_test; SELECT * FROM test_data WHERE id IN (SELECT id FROM test_data WHERE data LIKE '%Test%');"

echo -e "\n4. Generating ERROR LOGS (these will appear in error log)..."

# Error 1: Syntax error
echo "   - Generating syntax error..."
run_mysql "SELCT * FROM test_data;" || echo "     ✓ Syntax error generated"

# Error 2: Table doesn't exist
echo "   - Generating table not found error..."
run_mysql "SELECT * FROM non_existent_table;" || echo "     ✓ Table not found error generated"

# Error 3: Division by zero
echo "   - Generating division by zero error..."
run_mysql "SELECT 1/0;" || echo "     ✓ Division by zero error generated"

# Error 4: Duplicate key
echo "   - Generating duplicate key error..."
run_mysql "USE log_test; INSERT INTO test_data (id) VALUES (1), (1);" || echo "     ✓ Duplicate key error generated"

# Error 5: Invalid function
echo "   - Generating invalid function error..."
run_mysql "SELECT INVALID_FUNCTION();" || echo "     ✓ Invalid function error generated"

echo -e "\n========================================="
echo "✅ Log generation completed!"
echo "========================================="
echo ""
echo "Aurora will export these logs to S3 based on its schedule."
echo "The logs will appear in:"
echo "  - s3://company-aurora-logs-poc/error/"
echo "  - s3://company-aurora-logs-poc/slowquery/"
echo ""
echo "The Discovery service will detect new log files and process them."
echo "Check DynamoDB tables and OpenObserve for processed logs."