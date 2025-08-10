import React, { useState, Fragment } from 'react'
import { Switch, Listbox, Transition } from '@headlessui/react'
import { MagnifyingGlassIcon, FunnelIcon, CheckIcon, ChevronUpDownIcon } from '@heroicons/react/20/solid'
import { ServerStackIcon, ExclamationTriangleIcon, DocumentTextIcon, ClockIcon } from '@heroicons/react/24/outline'
import { mockInstances } from '../utils/mockData'

function classNames(...classes) {
  return classes.filter(Boolean).join(' ')
}

const filterOptions = [
  { id: 'all', name: 'All Instances' },
  { id: 'enabled', name: 'Active Only' },
  { id: 'disabled', name: 'Inactive Only' }
]

export default function Instances() {
  const [searchTerm, setSearchTerm] = useState('')
  const [instances, setInstances] = useState(mockInstances)
  const [selectedFilter, setSelectedFilter] = useState(filterOptions[0])

  const toggleLogType = (instanceId, logType) => {
    setInstances(instances.map(instance => 
      instance.id === instanceId 
        ? { 
            ...instance, 
            [logType]: { 
              ...instance[logType], 
              enabled: !instance[logType].enabled 
            }
          }
        : instance
    ))
  }

  const filteredInstances = instances.filter(instance => {
    const matchesSearch = instance.id.toLowerCase().includes(searchTerm.toLowerCase()) ||
                         instance.clusterId.toLowerCase().includes(searchTerm.toLowerCase())
    const matchesFilter = selectedFilter.id === 'all' || 
                         (selectedFilter.id === 'enabled' && (instance.errorLogs.enabled || instance.slowQueryLogs.enabled)) ||
                         (selectedFilter.id === 'disabled' && (!instance.errorLogs.enabled && !instance.slowQueryLogs.enabled))
    return matchesSearch && matchesFilter
  })

  return (
    <div>
      {/* Page header */}
      <div className="sm:flex sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">RDS Instances</h1>
          <p className="mt-2 text-sm text-gray-700 dark:text-gray-300">
            Manage log collection settings for your Aurora MySQL instances
          </p>
        </div>
        <div className="mt-4 sm:ml-16 sm:mt-0 sm:flex-none">
          <button
            type="button"
            className="block rounded-md bg-indigo-600 px-3 py-2 text-center text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
          >
            Refresh Instances
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="mt-8 flex flex-col sm:flex-row gap-4">
        <div className="flex-1">
          <label htmlFor="search" className="sr-only">
            Search
          </label>
          <div className="relative rounded-md shadow-sm">
            <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
              <MagnifyingGlassIcon className="h-5 w-5 text-gray-400" aria-hidden="true" />
            </div>
            <input
              type="search"
              name="search"
              id="search"
              className="block w-full rounded-md border-0 py-2 pl-10 pr-3 text-gray-900 dark:text-white ring-1 ring-inset ring-gray-300 dark:ring-gray-700 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 dark:bg-gray-800 sm:text-sm sm:leading-6"
              placeholder="Search instances..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </div>
        <Listbox value={selectedFilter} onChange={setSelectedFilter}>
          {({ open }) => (
            <>
              <div className="relative w-full sm:w-48">
                <Listbox.Button className="relative w-full cursor-default rounded-md bg-white dark:bg-gray-800 py-2 pl-3 pr-10 text-left text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-gray-700 focus:outline-none focus:ring-2 focus:ring-indigo-600 sm:text-sm sm:leading-6">
                  <span className="flex items-center">
                    <FunnelIcon className="h-5 w-5 text-gray-400" aria-hidden="true" />
                    <span className="ml-3 block truncate">{selectedFilter.name}</span>
                  </span>
                  <span className="pointer-events-none absolute inset-y-0 right-0 ml-3 flex items-center pr-2">
                    <ChevronUpDownIcon className="h-5 w-5 text-gray-400" aria-hidden="true" />
                  </span>
                </Listbox.Button>

                <Transition
                  show={open}
                  as={Fragment}
                  leave="transition ease-in duration-100"
                  leaveFrom="opacity-100"
                  leaveTo="opacity-0"
                >
                  <Listbox.Options className="absolute z-10 mt-1 max-h-56 w-full overflow-auto rounded-md bg-white dark:bg-gray-800 py-1 text-base shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none sm:text-sm">
                    {filterOptions.map((option) => (
                      <Listbox.Option
                        key={option.id}
                        className={({ active }) =>
                          classNames(
                            active ? 'bg-indigo-600 text-white' : 'text-gray-900 dark:text-white',
                            'relative cursor-default select-none py-2 pl-3 pr-9'
                          )
                        }
                        value={option}
                      >
                        {({ selected, active }) => (
                          <>
                            <span className={classNames(selected ? 'font-semibold' : 'font-normal', 'ml-3 block truncate')}>
                              {option.name}
                            </span>
                            {selected ? (
                              <span
                                className={classNames(
                                  active ? 'text-white' : 'text-indigo-600',
                                  'absolute inset-y-0 right-0 flex items-center pr-4'
                                )}
                              >
                                <CheckIcon className="h-5 w-5" aria-hidden="true" />
                              </span>
                            ) : null}
                          </>
                        )}
                      </Listbox.Option>
                    ))}
                  </Listbox.Options>
                </Transition>
              </div>
            </>
          )}
        </Listbox>
      </div>

      {/* Instances Table */}
      <div className="mt-8 overflow-hidden shadow ring-1 ring-black ring-opacity-5 md:rounded-lg">
        <table className="min-w-full divide-y divide-gray-300 dark:divide-gray-700">
          <thead className="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th scope="col" className="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-white sm:pl-6">
                Instance ID
              </th>
              <th scope="col" className="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                Cluster
              </th>
              <th scope="col" className="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                Status
              </th>
              <th scope="col" className="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                Region/AZ
              </th>
              <th scope="col" className="px-3 py-3.5 text-center text-sm font-semibold text-gray-900 dark:text-white">
                Error Logs
              </th>
              <th scope="col" className="px-3 py-3.5 text-center text-sm font-semibold text-gray-900 dark:text-white">
                Slow Query Logs
              </th>
              <th scope="col" className="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                Last Processed
              </th>
              <th scope="col" className="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                Total Size
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700 bg-white dark:bg-gray-900">
            {filteredInstances.map((instance) => (
              <tr key={instance.id} className="hover:bg-gray-50 dark:hover:bg-gray-800">
                <td className="whitespace-nowrap py-4 pl-4 pr-3 text-sm sm:pl-6">
                  <div className="flex items-center">
                    <ServerStackIcon className="h-5 w-5 text-gray-400 mr-3" />
                    <div>
                      <div className="font-medium text-gray-900 dark:text-white">{instance.id}</div>
                      <div className="text-gray-500 dark:text-gray-400">{instance.instanceClass}</div>
                    </div>
                  </div>
                </td>
                <td className="whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400">
                  {instance.clusterId}
                </td>
                <td className="whitespace-nowrap px-3 py-4 text-sm">
                  <span className={classNames(
                    instance.status === 'available'
                      ? 'text-green-800 bg-green-100 dark:text-green-400 dark:bg-green-900/30'
                      : 'text-yellow-800 bg-yellow-100 dark:text-yellow-400 dark:bg-yellow-900/30',
                    'inline-flex rounded-full px-2 text-xs font-semibold leading-5'
                  )}>
                    {instance.status}
                  </span>
                </td>
                <td className="whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400">
                  {instance.region} / {instance.az}
                </td>
                <td className="whitespace-nowrap px-3 py-4 text-sm text-center">
                  <div className="flex flex-col items-center">
                    <Switch
                      checked={instance.errorLogs.enabled}
                      onChange={() => toggleLogType(instance.id, 'errorLogs')}
                      className={classNames(
                        instance.errorLogs.enabled ? 'bg-indigo-600' : 'bg-gray-200 dark:bg-gray-700',
                        'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-600 focus:ring-offset-2'
                      )}
                    >
                      <span className="sr-only">Enable error logs</span>
                      <span
                        aria-hidden="true"
                        className={classNames(
                          instance.errorLogs.enabled ? 'translate-x-5' : 'translate-x-0',
                          'pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out'
                        )}
                      />
                    </Switch>
                    <span className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                      {instance.errorLogs.count} logs
                    </span>
                  </div>
                </td>
                <td className="whitespace-nowrap px-3 py-4 text-sm text-center">
                  <div className="flex flex-col items-center">
                    <Switch
                      checked={instance.slowQueryLogs.enabled}
                      onChange={() => toggleLogType(instance.id, 'slowQueryLogs')}
                      className={classNames(
                        instance.slowQueryLogs.enabled ? 'bg-indigo-600' : 'bg-gray-200 dark:bg-gray-700',
                        'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-600 focus:ring-offset-2'
                      )}
                    >
                      <span className="sr-only">Enable slow query logs</span>
                      <span
                        aria-hidden="true"
                        className={classNames(
                          instance.slowQueryLogs.enabled ? 'translate-x-5' : 'translate-x-0',
                          'pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out'
                        )}
                      />
                    </Switch>
                    <span className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                      {instance.slowQueryLogs.count} logs
                    </span>
                  </div>
                </td>
                <td className="whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400">
                  <div className="flex items-center">
                    <ClockIcon className="h-4 w-4 mr-1" />
                    {instance.errorLogs.lastProcessed || instance.slowQueryLogs.lastProcessed
                      ? new Date(instance.errorLogs.lastProcessed || instance.slowQueryLogs.lastProcessed).toLocaleString()
                      : 'Never'
                    }
                  </div>
                </td>
                <td className="whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400">
                  {instance.errorLogs.size} + {instance.slowQueryLogs.size}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}