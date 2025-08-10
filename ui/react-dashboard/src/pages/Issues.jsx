import React, { useState } from 'react'
import { AlertCircle, AlertTriangle, Info, XCircle, CheckCircle, Clock } from 'lucide-react'
import { mockIssues } from '../utils/mockData'

const severityConfig = {
  critical: { icon: XCircle, color: 'text-red-600 dark:text-red-400', bg: 'bg-red-100 dark:bg-red-900/20' },
  warning: { icon: AlertTriangle, color: 'text-yellow-600 dark:text-yellow-400', bg: 'bg-yellow-100 dark:bg-yellow-900/20' },
  info: { icon: Info, color: 'text-blue-600 dark:text-blue-400', bg: 'bg-blue-100 dark:bg-blue-900/20' }
}

export default function Issues() {
  const [issues, setIssues] = useState(mockIssues)
  const [selectedSeverity, setSelectedSeverity] = useState('all')

  const filteredIssues = selectedSeverity === 'all' 
    ? issues 
    : issues.filter(issue => issue.severity === selectedSeverity)

  const resolveIssue = (issueId) => {
    setIssues(issues.map(issue => 
      issue.id === issueId 
        ? { ...issue, status: 'resolved' }
        : issue
    ))
  }

  const issueTypeName = (type) => {
    const typeNames = {
      'api-throttle': 'API Throttling',
      'circuit-breaker': 'Circuit Breaker',
      'processing-delay': 'Processing Delay',
      'connection-error': 'Connection Error'
    }
    return typeNames[type] || type
  }

  return (
    <div>
      <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">System Issues</h2>

      {/* Issue Summary */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <button
          onClick={() => setSelectedSeverity('all')}
          className={`p-4 rounded-lg border-2 transition-colors ${
            selectedSeverity === 'all' 
              ? 'border-primary-500 bg-primary-50 dark:bg-primary-950/50 dark:border-primary-400' 
              : 'border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 hover:border-gray-300 dark:hover:border-gray-600'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-gray-600 dark:text-gray-400">All Issues</span>
            <span className="text-2xl font-bold text-gray-900 dark:text-white">{issues.length}</span>
          </div>
        </button>

        <button
          onClick={() => setSelectedSeverity('critical')}
          className={`p-4 rounded-lg border-2 transition-colors ${
            selectedSeverity === 'critical' 
              ? 'border-red-500 bg-red-50 dark:bg-red-950/50 dark:border-red-400' 
              : 'border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 hover:border-gray-300 dark:hover:border-gray-600'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-red-600 dark:text-red-400">Critical</span>
            <span className="text-2xl font-bold text-red-600 dark:text-red-400">
              {issues.filter(i => i.severity === 'critical').length}
            </span>
          </div>
        </button>

        <button
          onClick={() => setSelectedSeverity('warning')}
          className={`p-4 rounded-lg border-2 transition-colors ${
            selectedSeverity === 'warning' 
              ? 'border-yellow-500 bg-yellow-50 dark:bg-yellow-950/50 dark:border-yellow-400' 
              : 'border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 hover:border-gray-300 dark:hover:border-gray-600'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-yellow-600 dark:text-yellow-400">Warning</span>
            <span className="text-2xl font-bold text-yellow-600 dark:text-yellow-400">
              {issues.filter(i => i.severity === 'warning').length}
            </span>
          </div>
        </button>

        <button
          onClick={() => setSelectedSeverity('info')}
          className={`p-4 rounded-lg border-2 transition-colors ${
            selectedSeverity === 'info' 
              ? 'border-blue-500 bg-blue-50 dark:bg-blue-950/50 dark:border-blue-400' 
              : 'border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 hover:border-gray-300 dark:hover:border-gray-600'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-blue-600 dark:text-blue-400">Info</span>
            <span className="text-2xl font-bold text-blue-600 dark:text-blue-400">
              {issues.filter(i => i.severity === 'info').length}
            </span>
          </div>
        </button>
      </div>

      {/* Issues List */}
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">Active Issues</h3>
        </div>
        <div className="divide-y divide-gray-200 dark:divide-gray-700">
          {filteredIssues.map(issue => {
            const config = severityConfig[issue.severity]
            const Icon = config.icon
            
            return (
              <div key={issue.id} className="p-6 hover:bg-gray-50 dark:hover:bg-gray-700/50">
                <div className="flex items-start justify-between">
                  <div className="flex items-start space-x-3">
                    <div className={`p-2 rounded-lg ${config.bg}`}>
                      <Icon className={`h-5 w-5 ${config.color}`} />
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center space-x-2">
                        <h4 className="text-sm font-semibold text-gray-900 dark:text-white">
                          {issueTypeName(issue.type)}
                        </h4>
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                          issue.status === 'active' 
                            ? 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-400' 
                            : 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400'
                        }`}>
                          {issue.status}
                        </span>
                      </div>
                      <p className="text-sm text-gray-600 dark:text-gray-300 mt-1">{issue.message}</p>
                      <div className="flex items-center space-x-4 mt-2 text-xs text-gray-500 dark:text-gray-400">
                        <span>Instance: {issue.instance}</span>
                        <span className="flex items-center">
                          <Clock className="h-3 w-3 mr-1" />
                          {new Date(issue.timestamp).toLocaleString()}
                        </span>
                        <span>Occurrences: {issue.count}</span>
                      </div>
                    </div>
                  </div>
                  {issue.status === 'active' && (
                    <button
                      onClick={() => resolveIssue(issue.id)}
                      className="ml-4 px-3 py-1 text-sm font-medium text-green-600 dark:text-green-400 hover:text-green-700 dark:hover:text-green-300 hover:bg-green-50 dark:hover:bg-green-900/20 rounded-md transition-colors"
                    >
                      Mark Resolved
                    </button>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}