import React from 'react'
import { BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts'
import { HardDrive, Zap, TrendingUp, Database } from 'lucide-react'

const logTypeDistribution = [
  { name: 'Error Logs', value: 234567, color: '#ef4444' },
  { name: 'Slow Query Logs', value: 567890, color: '#f59e0b' },
  { name: 'General Logs', value: 123456, color: '#3b82f6' }
]

const compressionByDay = [
  { day: 'Mon', original: 450, compressed: 62 },
  { day: 'Tue', original: 420, compressed: 58 },
  { day: 'Wed', original: 480, compressed: 66 },
  { day: 'Thu', original: 460, compressed: 64 },
  { day: 'Fri', original: 490, compressed: 68 },
  { day: 'Sat', original: 380, compressed: 53 },
  { day: 'Sun', original: 360, compressed: 50 }
]

const topInstances = [
  { instance: 'aurora-prod-mysql-42', logs: 89234, size: '124 GB' },
  { instance: 'aurora-prod-mysql-15', logs: 76543, size: '98 GB' },
  { instance: 'aurora-prod-mysql-78', logs: 65432, size: '87 GB' },
  { instance: 'aurora-prod-mysql-23', logs: 54321, size: '76 GB' },
  { instance: 'aurora-prod-mysql-91', logs: 43210, size: '65 GB' }
]

const CustomTooltip = ({ active, payload, label }) => {
  if (active && payload && payload.length) {
    return (
      <div className="bg-white dark:bg-gray-800 p-3 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700">
        <p className="text-sm font-medium text-gray-900 dark:text-white">{label}</p>
        {payload.map((entry, index) => (
          <p key={index} className="text-sm text-gray-600 dark:text-gray-400">
            {entry.name}: {entry.value.toLocaleString()}
          </p>
        ))}
      </div>
    )
  }
  return null
}

export default function Metrics() {
  return (
    <div>
      <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">System Metrics</h2>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <HardDrive className="h-8 w-8 text-primary-500 dark:text-primary-400" />
            <span className="text-2xl font-bold text-gray-900 dark:text-white">2.4 TB</span>
          </div>
          <p className="text-sm text-gray-600 dark:text-gray-400">Total Data Processed</p>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">Last 30 days</p>
        </div>
        
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <Zap className="h-8 w-8 text-yellow-500 dark:text-yellow-400" />
            <span className="text-2xl font-bold text-gray-900 dark:text-white">7.2x</span>
          </div>
          <p className="text-sm text-gray-600 dark:text-gray-400">Compression Ratio</p>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">Average</p>
        </div>
        
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <TrendingUp className="h-8 w-8 text-green-500 dark:text-green-400" />
            <span className="text-2xl font-bold text-gray-900 dark:text-white">1,234</span>
          </div>
          <p className="text-sm text-gray-600 dark:text-gray-400">Logs/Minute</p>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">Current rate</p>
        </div>
        
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <div className="flex items-center justify-between mb-2">
            <Database className="h-8 w-8 text-purple-500 dark:text-purple-400" />
            <span className="text-2xl font-bold text-gray-900 dark:text-white">298</span>
          </div>
          <p className="text-sm text-gray-600 dark:text-gray-400">Active Instances</p>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">Out of 316 total</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 mb-8">
        {/* Log Type Distribution */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">Log Type Distribution</h3>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={logTypeDistribution}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={(entry) => `${entry.name}: ${(entry.value / 1000).toFixed(0)}k`}
                  outerRadius={80}
                  fill="#8884d8"
                  dataKey="value"
                >
                  {logTypeDistribution.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={entry.color} />
                  ))}
                </Pie>
                <Tooltip content={<CustomTooltip />} />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Compression Stats */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">Storage Compression (GB)</h3>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={compressionByDay}>
                <CartesianGrid strokeDasharray="3 3" stroke="#374151" opacity={0.3} />
                <XAxis dataKey="day" stroke="#6B7280" tick={{ fill: '#9CA3AF' }} />
                <YAxis stroke="#6B7280" tick={{ fill: '#9CA3AF' }} />
                <Tooltip content={<CustomTooltip />} />
                <Legend wrapperStyle={{ color: '#9CA3AF' }} />
                <Bar dataKey="original" fill="#94a3b8" name="Original Size" />
                <Bar dataKey="compressed" fill="#3b82f6" name="Compressed Size" />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      {/* Top Instances */}
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-4">Top Log Producers</h3>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
            <thead className="bg-gray-50 dark:bg-gray-700">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  Instance ID
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  Total Logs
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  Data Size
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  Activity
                </th>
              </tr>
            </thead>
            <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
              {topInstances.map((instance, idx) => (
                <tr key={instance.instance}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900 dark:text-white">
                    {instance.instance}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                    {instance.logs.toLocaleString()}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                    {instance.size}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="w-full bg-gray-200 dark:bg-gray-600 rounded-full h-2">
                      <div 
                        className="bg-primary-600 dark:bg-primary-400 h-2 rounded-full"
                        style={{ width: `${100 - (idx * 15)}%` }}
                      />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}