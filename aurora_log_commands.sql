-- Aurora MySQL Log Generation Commands
-- Run these commands to generate slow queries and errors

-- 1. SLOW QUERIES (will be logged in slow query log)

-- Slow Query 1: Direct SLEEP command (5 seconds)
SELECT 'Starting Slow Query Generation' as status;
SELECT SLEEP(5) as slow_query_sleep;

-- Slow Query 2: Heavy computation with BENCHMARK
SELECT BENCHMARK(100000000, MD5('aurora-test-log')) as slow_query_benchmark;

-- Slow Query 3: Create and populate test table
CREATE DATABASE IF NOT EXISTS aurora_log_test;
USE aurora_log_test;

DROP TABLE IF EXISTS test_log_data;
CREATE TABLE test_log_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data VARCHAR(255),
    number_field INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert 1000 rows
INSERT INTO test_log_data (data, number_field) 
SELECT 
    CONCAT('Test row ', n),
    FLOOR(RAND() * 1000)
FROM (
    SELECT a.n + b.n * 10 + c.n * 100 AS n
    FROM 
        (SELECT 0 AS n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 
         UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
        (SELECT 0 AS n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 
         UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b,
        (SELECT 0 AS n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 
         UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) c
) numbers
WHERE n < 1000;

-- Slow Query 4: Cartesian product (very slow)
SELECT COUNT(*) as cartesian_count 
FROM test_log_data t1, test_log_data t2 
WHERE t1.id <= 100 AND t2.id <= 100;

-- Slow Query 5: Multiple SLEEP in subquery
SELECT id, data, (SELECT SLEEP(0.01)) as delay 
FROM test_log_data 
WHERE id <= 100;

-- 2. ERROR QUERIES (will be logged in error log)

SELECT 'Starting Error Generation' as status;

-- Error 1: Syntax error
SELCT * FROM test_log_data;

-- Error 2: Table doesn't exist
SELECT * FROM table_that_does_not_exist;

-- Error 3: Column doesn't exist
SELECT non_existent_column FROM test_log_data;

-- Error 4: Division by zero
SELECT id, number_field / 0 as division_error FROM test_log_data LIMIT 5;

-- Error 5: Invalid function call
SELECT FUNCTION_DOES_NOT_EXIST(data) FROM test_log_data;

-- Error 6: Duplicate primary key
INSERT INTO test_log_data (id, data) VALUES (1, 'duplicate'), (1, 'duplicate');

-- Error 7: Data too long for column
INSERT INTO test_log_data (data) VALUES (REPEAT('x', 1000));

-- Error 8: Invalid date format
SELECT STR_TO_DATE('2024-13-45', '%Y-%m-%d') as invalid_date;

-- Error 9: Invalid data type
INSERT INTO test_log_data (number_field) VALUES ('not_a_number');

-- Error 10: Wrong number of columns
INSERT INTO test_log_data (id, data, number_field) VALUES (9999, 'test');

SELECT 'Log generation completed! Check S3 in 5-15 minutes.' as final_status;