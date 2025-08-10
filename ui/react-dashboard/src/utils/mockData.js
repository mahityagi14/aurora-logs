export const mockInstances = [
  {
    id: 'aurora-prod-mysql-1',
    clusterId: 'aurora-prod-cluster',
    instanceClass: 'db.r6g.2xlarge',
    engine: 'aurora-mysql',
    status: 'available',
    region: 'us-east-1',
    az: 'us-east-1a',
    lastSeen: new Date().toISOString(),
    errorLogs: { enabled: true, lastProcessed: '2025-01-06T10:30:00Z', count: 156, size: '12.3 MB' },
    slowQueryLogs: { enabled: true, lastProcessed: '2025-01-06T10:28:00Z', count: 342, size: '45.6 MB' },
    generalLogs: { enabled: false, lastProcessed: null, count: 0, size: '0 B' }
  },
  {
    id: 'aurora-prod-mysql-2',
    clusterId: 'aurora-prod-cluster',
    instanceClass: 'db.r6g.2xlarge',
    engine: 'aurora-mysql',
    status: 'available',
    logsEnabled: true,
    region: 'us-east-1',
    az: 'us-east-1b',
    lastSeen: new Date().toISOString(),
    errorLogs: { enabled: true, lastProcessed: '2025-01-06T10:29:00Z', count: 89, size: '8.7 MB' },
    slowQueryLogs: { enabled: true, lastProcessed: '2025-01-06T10:27:00Z', count: 567, size: '67.8 MB' },
    generalLogs: { enabled: false, lastProcessed: null, count: 0, size: '0 B' }
  },
  {
    id: 'aurora-staging-mysql-1',
    clusterId: 'aurora-staging-cluster',
    instanceClass: 'db.r6g.2xlarge',
    engine: 'aurora-mysql',
    status: 'available',
    logsEnabled: false,
    region: 'us-east-1',
    az: 'us-east-1a',
    lastSeen: new Date().toISOString(),
    errorLogs: { enabled: false, lastProcessed: null, count: 0, size: '0 B' },
    slowQueryLogs: { enabled: false, lastProcessed: null, count: 0, size: '0 B' },
    generalLogs: { enabled: false, lastProcessed: null, count: 0, size: '0 B' }
  }
]

export const mockMetrics = {
  totalInstances: 316,
  activeInstances: 298,
  totalLogsProcessed: 1542367,
  totalSizeProcessed: '2.4 TB',
  compressedSize: '342 GB',
  compressionRatio: 7.2,
  processingRate: '1,234 logs/min',
  errorRate: '0.02%',
  lastHourStats: [
    { time: '10:00', processed: 72000, errors: 12 },
    { time: '10:10', processed: 68000, errors: 8 },
    { time: '10:20', processed: 71000, errors: 15 },
    { time: '10:30', processed: 69500, errors: 10 },
    { time: '10:40', processed: 70000, errors: 7 },
    { time: '10:50', processed: 73000, errors: 11 },
    { time: '11:00', processed: 71500, errors: 9 }
  ]
}

export const mockIssues = [
  {
    id: 'issue-001',
    severity: 'critical',
    type: 'api-throttle',
    instance: 'aurora-prod-mysql-15',
    message: 'RDS API throttling detected - rate limit exceeded',
    timestamp: '2025-01-06T10:45:23Z',
    count: 5,
    status: 'active'
  },
  {
    id: 'issue-002',
    severity: 'warning',
    type: 'circuit-breaker',
    instance: 'aurora-prod-mysql-42',
    message: 'Circuit breaker opened - too many failed attempts',
    timestamp: '2025-01-06T10:32:15Z',
    count: 3,
    status: 'active'
  },
  {
    id: 'issue-003',
    severity: 'info',
    type: 'processing-delay',
    instance: 'aurora-prod-mysql-78',
    message: 'Log processing delayed - large file size (>1GB)',
    timestamp: '2025-01-06T10:28:45Z',
    count: 1,
    status: 'resolved'
  }
]

export const mockJobs = [
  {
    id: 'job-001',
    instanceId: 'aurora-prod-mysql-1',
    logType: 'error',
    status: 'processing',
    startTime: '2025-01-06T11:00:00Z',
    progress: 67,
    filesProcessed: 8,
    totalFiles: 12
  },
  {
    id: 'job-002',
    instanceId: 'aurora-prod-mysql-2',
    logType: 'slowquery',
    status: 'processing',
    startTime: '2025-01-06T10:58:00Z',
    progress: 45,
    filesProcessed: 5,
    totalFiles: 11
  }
]