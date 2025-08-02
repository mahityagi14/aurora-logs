#!/bin/bash

# One-liner to generate Aurora logs
# This will create both slow queries and errors

echo "Generating Aurora MySQL logs..."

mysql -h aurora-mysql-poc-01-instance-1.cepmue6m8uzp.us-east-1.rds.amazonaws.com \
      -u admin \
      -pMzn1442000 \
      -e "
-- Quick slow queries
SELECT 'Generating slow query 1' as status, SLEEP(5);
SELECT 'Generating slow query 2' as status, BENCHMARK(100000000, MD5('test'));

-- Quick errors (will show errors but continue)
SELCT 1;
SELECT * FROM does_not_exist;
SELECT 1/0;
SELECT INVALID_FUNC();
" 2>&1

echo "Done! Aurora will export logs to S3 within 5-15 minutes."
echo "Check s3://company-aurora-logs-poc/slowquery/ and /error/"