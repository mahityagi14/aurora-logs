-- Check Aurora MySQL Logs Status

-- 1. Check slow query log settings
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
SHOW VARIABLES LIKE 'slow_query_log_file';
SHOW VARIABLES LIKE 'log_output';

-- 2. Check error log settings
SHOW VARIABLES LIKE 'log_error';
SHOW VARIABLES LIKE 'log_warnings';

-- 3. Check general log (if enabled)
SHOW VARIABLES LIKE 'general_log';
SHOW VARIABLES LIKE 'general_log_file';

-- 4. Check current processlist for running queries
SHOW FULL PROCESSLIST;

-- 5. Check if slow queries were logged (from performance schema)
SELECT 
    DIGEST_TEXT,
    COUNT_STAR as execution_count,
    SUM_TIMER_WAIT/1000000000000 as total_time_sec,
    AVG_TIMER_WAIT/1000000000000 as avg_time_sec,
    MAX_TIMER_WAIT/1000000000000 as max_time_sec
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT LIKE '%SLEEP%' 
   OR DIGEST_TEXT LIKE '%BENCHMARK%'
   OR AVG_TIMER_WAIT/1000000000000 > 1
ORDER BY AVG_TIMER_WAIT DESC
LIMIT 10;

-- 6. Check recent statements from performance schema
SELECT 
    SQL_TEXT,
    TIMER_WAIT/1000000000000 as duration_sec,
    ERRORS,
    WARNINGS
FROM performance_schema.events_statements_history_long
WHERE SQL_TEXT LIKE '%SLEEP%' 
   OR SQL_TEXT LIKE '%BENCHMARK%'
   OR ERRORS > 0
ORDER BY TIMER_END DESC
LIMIT 20;

-- 7. Check if any errors were recorded
SELECT 
    SQL_TEXT,
    ERRORS,
    MYSQL_ERRNO,
    RETURNED_SQLSTATE,
    MESSAGE_TEXT
FROM performance_schema.events_statements_history_long
WHERE ERRORS > 0
ORDER BY TIMER_END DESC
LIMIT 10;

-- 8. Check slow query count from status
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- 9. Check uptime to see when server started
SHOW GLOBAL STATUS LIKE 'Uptime';

-- 10. For Aurora specific - check if logs are being exported
SELECT @@aurora_version;