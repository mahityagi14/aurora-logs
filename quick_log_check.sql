-- Quick Aurora Log Check Commands

-- 1. Check if slow query logging is enabled
SHOW VARIABLES LIKE 'slow_query_log';

-- 2. Check slow query threshold (queries slower than this are logged)
SHOW VARIABLES LIKE 'long_query_time';

-- 3. Check how many slow queries have been recorded
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- 4. See recent slow queries from performance schema
SELECT 
    LEFT(DIGEST_TEXT, 100) as query_pattern,
    COUNT_STAR as times_executed,
    ROUND(AVG_TIMER_WAIT/1000000000000, 2) as avg_seconds,
    ROUND(MAX_TIMER_WAIT/1000000000000, 2) as max_seconds
FROM performance_schema.events_statements_summary_by_digest
WHERE AVG_TIMER_WAIT/1000000000000 > 1  -- Queries averaging over 1 second
   OR DIGEST_TEXT LIKE '%SLEEP%'
   OR DIGEST_TEXT LIKE '%BENCHMARK%'
ORDER BY AVG_TIMER_WAIT DESC
LIMIT 10;

-- 5. Check for errors in recent queries
SELECT 
    LEFT(SQL_TEXT, 100) as query,
    ERRORS,
    MESSAGE_TEXT
FROM performance_schema.events_statements_history_long
WHERE ERRORS > 0
ORDER BY TIMER_END DESC
LIMIT 10;