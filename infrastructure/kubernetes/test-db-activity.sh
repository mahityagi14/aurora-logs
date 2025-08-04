#!/bin/bash

# Aurora MySQL connection details
DB_HOST=$(aws rds describe-db-clusters --db-cluster-identifier aurora-mysql-poc-01 --query 'DBClusters[0].Endpoint' --output text)
DB_USER="admin"
DB_PASS=$(aws secretsmanager get-secret-value --secret-id aurora-mysql-poc-01-secret --query SecretString --output text | jq -r .password)
DB_NAME="testdb"

echo "Connecting to Aurora MySQL at $DB_HOST..."

# Create test database and table
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "
CREATE TABLE IF NOT EXISTS test_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);"

echo "Generating test queries..."

# Generate some slow queries
for i in {1..5}; do
    echo "Running slow query $i..."
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "
    SELECT SLEEP(2), COUNT(*) FROM test_logs t1 
    CROSS JOIN test_logs t2 
    WHERE t1.data LIKE '%test%' AND t2.data LIKE '%slow%';"
done

# Generate some errors
echo "Generating error conditions..."
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SELECT * FROM non_existent_table;" 2>&1 || true
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "INSERT INTO test_logs (id, data) VALUES (1, 'duplicate');" 2>&1 || true
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "INSERT INTO test_logs (id, data) VALUES (1, 'duplicate');" 2>&1 || true

# Insert test data
echo "Inserting test data..."
for i in {1..100}; do
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "
    INSERT INTO test_logs (data) VALUES ('Test log entry $i at $(date)');"
done

echo "Test activity generation completed!"