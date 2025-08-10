import React, { useState } from 'react'
import { Routes, Route, Link, useLocation } from 'react-router-dom'
import { Database, Activity, AlertCircle, Settings, BarChart3, Home, Moon, Sun, Menu, X, ChevronRight } from 'lucide-react'
import { Transition, Dialog } from '@headlessui/react'
import { useTheme } from './contexts/ThemeContext'
import Dashboard from './pages/Dashboard'
import Instances from './pages/Instances'
import Metrics from './pages/Metrics'
import Issues from './pages/Issues'
import Configuration from './pages/Configuration'

function App() {
  const location = useLocation()
  const { isDarkMode, toggleDarkMode } = useTheme()
  const [sidebarOpen, setSidebarOpen] = useState(false)
  
  const navigation = [
    { name: 'Dashboard', path: '/', icon: Home },
    { name: 'RDS Instances', path: '/instances', icon: Database },
    { name: 'Metrics', path: '/metrics', icon: BarChart3 },
    { name: 'Active Jobs', path: '/jobs', icon: Activity },
    { name: 'Issues', path: '/issues', icon: AlertCircle },
    { name: 'Configuration', path: '/config', icon: Settings }
  ]

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Mobile sidebar */}
      <Transition.Root show={sidebarOpen} as={React.Fragment}>
        <Dialog as="div" className="relative z-50 lg:hidden" onClose={setSidebarOpen}>
          <Transition.Child
            as={React.Fragment}
            enter="transition-opacity ease-linear duration-300"
            enterFrom="opacity-0"
            enterTo="opacity-100"
            leave="transition-opacity ease-linear duration-300"
            leaveFrom="opacity-100"
            leaveTo="opacity-0"
          >
            <div className="fixed inset-0 bg-gray-900/80" />
          </Transition.Child>

          <div className="fixed inset-0 flex">
            <Transition.Child
              as={React.Fragment}
              enter="transition ease-in-out duration-300 transform"
              enterFrom="-translate-x-full"
              enterTo="translate-x-0"
              leave="transition ease-in-out duration-300 transform"
              leaveFrom="translate-x-0"
              leaveTo="-translate-x-full"
            >
              <Dialog.Panel className="relative mr-16 flex w-full max-w-xs flex-1">
                <Transition.Child
                  as={React.Fragment}
                  enter="ease-in-out duration-300"
                  enterFrom="opacity-0"
                  enterTo="opacity-100"
                  leave="ease-in-out duration-300"
                  leaveFrom="opacity-100"
                  leaveTo="opacity-0"
                >
                  <div className="absolute left-full top-0 flex w-16 justify-center pt-5">
                    <button type="button" className="-m-2.5 p-2.5" onClick={() => setSidebarOpen(false)}>
                      <span className="sr-only">Close sidebar</span>
                      <X className="h-6 w-6 text-white" aria-hidden="true" />
                    </button>
                  </div>
                </Transition.Child>
                <div className="flex grow flex-col gap-y-5 overflow-y-auto bg-white dark:bg-gray-900 px-6 pb-4 ring-1 ring-white/10">
                  <div className="flex h-16 shrink-0 items-center">
                    <Database className="h-8 w-8 text-indigo-600 dark:text-indigo-400" />
                    <span className="ml-3 text-xl font-semibold text-gray-900 dark:text-white">Aurora Logs</span>
                  </div>
                  <nav className="flex flex-1 flex-col">
                    <ul role="list" className="flex flex-1 flex-col gap-y-7">
                      <li>
                        <ul role="list" className="-mx-2 space-y-1">
                          {navigation.map((item) => {
                            const Icon = item.icon
                            const isActive = location.pathname === item.path
                            return (
                              <li key={item.name}>
                                <Link
                                  to={item.path}
                                  onClick={() => setSidebarOpen(false)}
                                  className={`group flex gap-x-3 rounded-md p-2 text-sm leading-6 font-semibold ${
                                    isActive
                                      ? 'bg-gray-50 dark:bg-gray-800 text-indigo-600 dark:text-indigo-400'
                                      : 'text-gray-700 dark:text-gray-400 hover:text-indigo-600 dark:hover:text-indigo-400 hover:bg-gray-50 dark:hover:bg-gray-800'
                                  }`}
                                >
                                  <Icon className="h-6 w-6 shrink-0" aria-hidden="true" />
                                  {item.name}
                                </Link>
                              </li>
                            )
                          })}
                        </ul>
                      </li>
                    </ul>
                  </nav>
                </div>
              </Dialog.Panel>
            </Transition.Child>
          </div>
        </Dialog>
      </Transition.Root>

      {/* Static sidebar for desktop */}
      <div className="hidden lg:fixed lg:inset-y-0 lg:z-50 lg:flex lg:w-72 lg:flex-col">
        <div className="flex grow flex-col gap-y-5 overflow-y-auto bg-white dark:bg-gray-900 px-6 pb-4 border-r border-gray-200 dark:border-gray-800">
          <div className="flex h-16 shrink-0 items-center">
            <Database className="h-8 w-8 text-indigo-600 dark:text-indigo-400" />
            <span className="ml-3 text-xl font-semibold text-gray-900 dark:text-white">Aurora Log System</span>
          </div>
          <nav className="flex flex-1 flex-col">
            <ul role="list" className="flex flex-1 flex-col gap-y-7">
              <li>
                <ul role="list" className="-mx-2 space-y-1">
                  {navigation.map((item) => {
                    const Icon = item.icon
                    const isActive = location.pathname === item.path
                    return (
                      <li key={item.name}>
                        <Link
                          to={item.path}
                          className={`group flex gap-x-3 rounded-md p-2 text-sm leading-6 font-semibold transition-colors ${
                            isActive
                              ? 'bg-indigo-50 dark:bg-indigo-950/50 text-indigo-600 dark:text-indigo-400'
                              : 'text-gray-700 dark:text-gray-400 hover:text-indigo-600 dark:hover:text-indigo-400 hover:bg-gray-50 dark:hover:bg-gray-800'
                          }`}
                        >
                          <Icon className="h-6 w-6 shrink-0" aria-hidden="true" />
                          {item.name}
                          {isActive && (
                            <ChevronRight className="ml-auto h-5 w-5 shrink-0 text-gray-400" aria-hidden="true" />
                          )}
                        </Link>
                      </li>
                    )
                  })}
                </ul>
              </li>
              <li className="mt-auto">
                <div className="flex items-center gap-x-4 px-2 py-3 text-sm font-semibold leading-6 text-gray-900 dark:text-white">
                  <div className="flex h-2 w-2 shrink-0 rounded-full bg-green-500 animate-pulse" />
                  <span className="text-xs text-gray-500 dark:text-gray-400">System Status: Operational</span>
                </div>
              </li>
            </ul>
          </nav>
        </div>
      </div>

      <div className="lg:pl-72">
        {/* Top bar */}
        <div className="sticky top-0 z-40 flex h-16 shrink-0 items-center gap-x-4 border-b border-gray-200 dark:border-gray-800 bg-white/95 dark:bg-gray-900/95 backdrop-blur px-4 shadow-sm sm:gap-x-6 sm:px-6 lg:px-8">
          <button
            type="button"
            className="-m-2.5 p-2.5 text-gray-700 dark:text-gray-400 lg:hidden"
            onClick={() => setSidebarOpen(true)}
          >
            <span className="sr-only">Open sidebar</span>
            <Menu className="h-6 w-6" aria-hidden="true" />
          </button>

          {/* Separator */}
          <div className="h-6 w-px bg-gray-200 dark:bg-gray-800 lg:hidden" aria-hidden="true" />

          <div className="flex flex-1 gap-x-4 self-stretch lg:gap-x-6">
            <div className="flex items-center gap-x-4 lg:gap-x-6 ml-auto">
              <span className="hidden sm:block text-sm text-gray-500 dark:text-gray-400">
                Environment: <span className="font-medium text-gray-900 dark:text-white">Production</span>
              </span>
              
              {/* Theme toggle */}
              <button
                onClick={toggleDarkMode}
                className="relative rounded-full bg-white dark:bg-gray-800 p-1.5 text-gray-400 hover:text-gray-500 dark:hover:text-gray-300 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900"
              >
                <span className="sr-only">Toggle theme</span>
                {isDarkMode ? (
                  <Sun className="h-5 w-5" aria-hidden="true" />
                ) : (
                  <Moon className="h-5 w-5" aria-hidden="true" />
                )}
              </button>

              {/* Separator */}
              <div className="hidden lg:block lg:h-6 lg:w-px lg:bg-gray-200 dark:lg:bg-gray-800" aria-hidden="true" />

              {/* Profile dropdown placeholder */}
              <div className="relative">
                <button className="flex items-center gap-x-2 rounded-full bg-white dark:bg-gray-800 p-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:focus:ring-offset-gray-900">
                  <span className="h-8 w-8 rounded-full bg-gradient-to-r from-indigo-500 to-purple-500 flex items-center justify-center text-white text-sm font-medium">
                    AS
                  </span>
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Main content */}
        <main className="py-10">
          <div className="px-4 sm:px-6 lg:px-8">
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/instances" element={<Instances />} />
              <Route path="/metrics" element={<Metrics />} />
              <Route path="/jobs" element={
                <div className="rounded-lg bg-white dark:bg-gray-800 shadow-sm ring-1 ring-gray-900/5 dark:ring-gray-100/5 p-6">
                  <h2 className="text-lg font-medium text-gray-900 dark:text-white">Active Jobs</h2>
                  <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">Coming soon...</p>
                </div>
              } />
              <Route path="/issues" element={<Issues />} />
              <Route path="/config" element={<Configuration />} />
            </Routes>
          </div>
        </main>
      </div>
    </div>
  )
}

export default App