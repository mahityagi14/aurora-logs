import React from 'react'
import { ArrowUpIcon, ArrowDownIcon } from '@heroicons/react/20/solid'
import { CursorArrowRaysIcon, ServerStackIcon, DocumentTextIcon, CircleStackIcon } from '@heroicons/react/24/outline'
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Area, AreaChart } from 'recharts'
import { mockMetrics, mockJobs } from '../utils/mockData'

function classNames(...classes) {
  return classes.filter(Boolean).join(' ')
}

const stats = [
  { 
    name: 'Total RDS Instances', 
    stat: mockMetrics.totalInstances, 
    previousStat: 312, 
    change: '1.28%', 
    changeType: 'increase',
    icon: ServerStackIcon,
    color: 'bg-blue-500'
  },
  { 
    name: 'Logs Processed', 
    stat: '1.54M', 
    previousStat: '1.37M', 
    change: '12.5%', 
    changeType: 'increase',
    icon: DocumentTextIcon,
    color: 'bg-green-500'
  },
  { 
    name: 'Compression Ratio', 
    stat: `${mockMetrics.compressionRatio}:1`, 
    previousStat: '6.8:1', 
    change: '5.88%', 
    changeType: 'increase',
    icon: CircleStackIcon,
    color: 'bg-purple-500'
  },
  { 
    name: 'Error Rate', 
    stat: mockMetrics.errorRate, 
    previousStat: '0.025%', 
    change: '2.3%', 
    changeType: 'decrease',
    icon: CursorArrowRaysIcon,
    color: 'bg-yellow-500'
  }
]

// Custom gradient definitions
const gradients = (
  <defs>
    <linearGradient id="colorProcessed" x1="0" y1="0" x2="0" y2="1">
      <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.3}/>
      <stop offset="95%" stopColor="#3b82f6" stopOpacity={0}/>
    </linearGradient>
    <linearGradient id="colorErrors" x1="0" y1="0" x2="0" y2="1">
      <stop offset="5%" stopColor="#ef4444" stopOpacity={0.3}/>
      <stop offset="95%" stopColor="#ef4444" stopOpacity={0}/>
    </linearGradient>
  </defs>
)

export default function Dashboard() {
  return (
    <div>
      <div className="mb-8">
        <h3 className="text-base font-semibold leading-6 text-gray-900 dark:text-white">Last 24 hours</h3>
        <dl className="mt-5 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {stats.map((item) => (
            <div
              key={item.name}
              className="relative overflow-hidden rounded-lg bg-white dark:bg-gray-800 px-4 pt-5 pb-12 shadow sm:px-6 sm:pt-6"
            >
              <dt>
                <div className={classNames(item.color, 'absolute rounded-md p-3')}>
                  <item.icon className="h-6 w-6 text-white" aria-hidden="true" />
                </div>
                <p className="ml-16 truncate text-sm font-medium text-gray-500 dark:text-gray-400">{item.name}</p>
              </dt>
              <dd className="ml-16 flex items-baseline pb-6 sm:pb-7">
                <p className="text-2xl font-semibold text-gray-900 dark:text-white">{item.stat}</p>
                <p
                  className={classNames(
                    item.changeType === 'increase' ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400',
                    'ml-2 flex items-baseline text-sm font-semibold'
                  )}
                >
                  {item.changeType === 'increase' ? (
                    <ArrowUpIcon className="h-5 w-5 flex-shrink-0 self-center text-green-500" aria-hidden="true" />
                  ) : (
                    <ArrowDownIcon className="h-5 w-5 flex-shrink-0 self-center text-red-500" aria-hidden="true" />
                  )}
                  <span className="sr-only"> {item.changeType === 'increase' ? 'Increased' : 'Decreased'} by </span>
                  {item.change}
                </p>
                <div className="absolute inset-x-0 bottom-0 bg-gray-50 dark:bg-gray-700/50 px-4 py-4 sm:px-6">
                  <div className="text-sm">
                    <a href="#" className="font-medium text-indigo-600 dark:text-indigo-400 hover:text-indigo-500 dark:hover:text-indigo-300">
                      View details<span className="sr-only"> {item.name} stats</span>
                    </a>
                  </div>
                </div>
              </dd>
            </div>
          ))}
        </dl>
      </div>

      {/* Chart Section */}
      <div className="grid grid-cols-1 gap-8 lg:grid-cols-2">
        <div className="rounded-lg bg-white dark:bg-gray-800 shadow">
          <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
            <h3 className="text-base font-semibold leading-6 text-gray-900 dark:text-white">Log Processing Trend</h3>
            <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">Number of logs processed per 10 minutes</p>
          </div>
          <div className="p-6">
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={mockMetrics.lastHourStats}>
                  {gradients}
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" strokeOpacity={0.5} />
                  <XAxis 
                    dataKey="time" 
                    stroke="#6b7280"
                    tick={{ fill: '#6b7280', fontSize: 12 }}
                  />
                  <YAxis 
                    stroke="#6b7280"
                    tick={{ fill: '#6b7280', fontSize: 12 }}
                  />
                  <Tooltip 
                    contentStyle={{ 
                      backgroundColor: 'rgba(255, 255, 255, 0.95)', 
                      border: '1px solid #e5e7eb',
                      borderRadius: '6px'
                    }}
                  />
                  <Area
                    type="monotone"
                    dataKey="processed"
                    stroke="#3b82f6"
                    strokeWidth={2}
                    fill="url(#colorProcessed)"
                    name="Logs Processed"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>

        <div className="rounded-lg bg-white dark:bg-gray-800 shadow">
          <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
            <h3 className="text-base font-semibold leading-6 text-gray-900 dark:text-white">Error Rate Trend</h3>
            <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">Errors per 10 minutes</p>
          </div>
          <div className="p-6">
            <div className="h-64">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={mockMetrics.lastHourStats}>
                  {gradients}
                  <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" strokeOpacity={0.5} />
                  <XAxis 
                    dataKey="time" 
                    stroke="#6b7280"
                    tick={{ fill: '#6b7280', fontSize: 12 }}
                  />
                  <YAxis 
                    stroke="#6b7280"
                    tick={{ fill: '#6b7280', fontSize: 12 }}
                  />
                  <Tooltip 
                    contentStyle={{ 
                      backgroundColor: 'rgba(255, 255, 255, 0.95)', 
                      border: '1px solid #e5e7eb',
                      borderRadius: '6px'
                    }}
                  />
                  <Area
                    type="monotone"
                    dataKey="errors"
                    stroke="#ef4444"
                    strokeWidth={2}
                    fill="url(#colorErrors)"
                    name="Errors"
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>
        </div>
      </div>

      {/* Active Jobs Section */}
      <div className="mt-8">
        <div className="overflow-hidden bg-white dark:bg-gray-800 shadow sm:rounded-lg">
          <div className="px-4 py-5 sm:px-6">
            <h3 className="text-base font-semibold leading-6 text-gray-900 dark:text-white">Active Processing Jobs</h3>
            <p className="mt-1 max-w-2xl text-sm text-gray-500 dark:text-gray-400">Currently running log processing tasks</p>
          </div>
          <div className="border-t border-gray-200 dark:border-gray-700">
            <ul role="list" className="divide-y divide-gray-200 dark:divide-gray-700">
              {mockJobs.map((job) => (
                <li key={job.id} className="px-4 py-4 sm:px-6">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center">
                      <div className="flex-shrink-0">
                        <div className="h-10 w-10 rounded-full bg-indigo-100 dark:bg-indigo-900/30 flex items-center justify-center">
                          <ServerStackIcon className="h-5 w-5 text-indigo-600 dark:text-indigo-400" />
                        </div>
                      </div>
                      <div className="ml-4">
                        <div className="font-medium text-gray-900 dark:text-white">{job.instanceId}</div>
                        <div className="text-sm text-gray-500 dark:text-gray-400">Processing {job.logType} logs</div>
                      </div>
                    </div>
                    <div className="flex items-center">
                      <div className="mr-4 text-right">
                        <div className="text-sm font-medium text-gray-900 dark:text-white">{job.progress}%</div>
                        <div className="text-sm text-gray-500 dark:text-gray-400">{job.filesProcessed} of {job.totalFiles} files</div>
                      </div>
                      <div className="w-32">
                        <div className="overflow-hidden rounded-full bg-gray-200 dark:bg-gray-700">
                          <div
                            className="h-2 rounded-full bg-indigo-600 dark:bg-indigo-500 transition-all duration-300"
                            style={{ width: `${job.progress}%` }}
                          />
                        </div>
                      </div>
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}