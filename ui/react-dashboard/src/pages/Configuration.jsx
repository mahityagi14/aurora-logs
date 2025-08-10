import React, { useState } from 'react'
import { Save, RefreshCw, Database, Clock, Server, Shield } from 'lucide-react'

export default function Configuration() {
  const [config, setConfig] = useState({
    discovery: {
      interval: 300,
      batchSize: 10,
      maxConcurrent: 5,
      rdsApiTimeout: 30
    },
    processor: {
      batchSize: 100,
      compressionLevel: 6,
      maxRetries: 3,
      retryDelay: 5
    },
    kafka: {
      topic: 'aurora-logs',
      partitions: 10,
      replicationFactor: 3,
      retention: 168
    },
    openobserve: {
      endpoint: 'http://openobserve-alb-355407172.us-east-1.elb.amazonaws.com',
      batchSize: 1000,
      flushInterval: 10,
      maxRetries: 3
    }
  })

  const [saved, setSaved] = useState(false)

  const handleSave = () => {
    setSaved(true)
    setTimeout(() => setSaved(false), 3000)
  }

  const ConfigSection = ({ title, icon: Icon, children }) => (
    <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6 mb-6">
      <div className="flex items-center mb-4">
        <Icon className="h-5 w-5 text-primary-600 dark:text-primary-400 mr-2" />
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">{title}</h3>
      </div>
      {children}
    </div>
  )

  const ConfigField = ({ label, value, unit, onChange, type = "number" }) => (
    <div className="mb-4">
      <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">{label}</label>
      <div className="flex items-center">
        <input
          type={type}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md focus:ring-2 focus:ring-primary-500 focus:border-transparent bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
        />
        {unit && <span className="ml-2 text-sm text-gray-500 dark:text-gray-400">{unit}</span>}
      </div>
    </div>
  )

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-2xl font-bold text-gray-900 dark:text-white">System Configuration</h2>
        <button
          onClick={handleSave}
          className="flex items-center px-4 py-2 bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors"
        >
          <Save className="h-4 w-4 mr-2" />
          Save Changes
        </button>
      </div>

      {saved && (
        <div className="mb-6 p-4 bg-green-100 dark:bg-green-900/20 border border-green-400 dark:border-green-600 text-green-700 dark:text-green-400 rounded-lg">
          Configuration saved successfully!
        </div>
      )}

      <ConfigSection title="Discovery Service" icon={Database}>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <ConfigField
            label="Discovery Interval"
            value={config.discovery.interval}
            unit="seconds"
            onChange={(val) => setConfig({
              ...config,
              discovery: { ...config.discovery, interval: val }
            })}
          />
          <ConfigField
            label="Batch Size"
            value={config.discovery.batchSize}
            unit="instances"
            onChange={(val) => setConfig({
              ...config,
              discovery: { ...config.discovery, batchSize: val }
            })}
          />
          <ConfigField
            label="Max Concurrent Discoveries"
            value={config.discovery.maxConcurrent}
            onChange={(val) => setConfig({
              ...config,
              discovery: { ...config.discovery, maxConcurrent: val }
            })}
          />
          <ConfigField
            label="RDS API Timeout"
            value={config.discovery.rdsApiTimeout}
            unit="seconds"
            onChange={(val) => setConfig({
              ...config,
              discovery: { ...config.discovery, rdsApiTimeout: val }
            })}
          />
        </div>
      </ConfigSection>

      <ConfigSection title="Processor Service" icon={RefreshCw}>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <ConfigField
            label="Processing Batch Size"
            value={config.processor.batchSize}
            unit="logs"
            onChange={(val) => setConfig({
              ...config,
              processor: { ...config.processor, batchSize: val }
            })}
          />
          <ConfigField
            label="Compression Level"
            value={config.processor.compressionLevel}
            unit="1-9"
            onChange={(val) => setConfig({
              ...config,
              processor: { ...config.processor, compressionLevel: val }
            })}
          />
          <ConfigField
            label="Max Retries"
            value={config.processor.maxRetries}
            onChange={(val) => setConfig({
              ...config,
              processor: { ...config.processor, maxRetries: val }
            })}
          />
          <ConfigField
            label="Retry Delay"
            value={config.processor.retryDelay}
            unit="seconds"
            onChange={(val) => setConfig({
              ...config,
              processor: { ...config.processor, retryDelay: val }
            })}
          />
        </div>
      </ConfigSection>

      <ConfigSection title="Kafka Configuration" icon={Server}>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <ConfigField
            label="Topic Name"
            value={config.kafka.topic}
            type="text"
            onChange={(val) => setConfig({
              ...config,
              kafka: { ...config.kafka, topic: val }
            })}
          />
          <ConfigField
            label="Partitions"
            value={config.kafka.partitions}
            onChange={(val) => setConfig({
              ...config,
              kafka: { ...config.kafka, partitions: val }
            })}
          />
          <ConfigField
            label="Replication Factor"
            value={config.kafka.replicationFactor}
            onChange={(val) => setConfig({
              ...config,
              kafka: { ...config.kafka, replicationFactor: val }
            })}
          />
          <ConfigField
            label="Retention Period"
            value={config.kafka.retention}
            unit="hours"
            onChange={(val) => setConfig({
              ...config,
              kafka: { ...config.kafka, retention: val }
            })}
          />
        </div>
      </ConfigSection>

      <ConfigSection title="OpenObserve Settings" icon={Shield}>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div className="md:col-span-2">
            <ConfigField
              label="Endpoint URL"
              value={config.openobserve.endpoint}
              type="text"
              onChange={(val) => setConfig({
                ...config,
                openobserve: { ...config.openobserve, endpoint: val }
              })}
            />
          </div>
          <ConfigField
            label="Batch Size"
            value={config.openobserve.batchSize}
            unit="logs"
            onChange={(val) => setConfig({
              ...config,
              openobserve: { ...config.openobserve, batchSize: val }
            })}
          />
          <ConfigField
            label="Flush Interval"
            value={config.openobserve.flushInterval}
            unit="seconds"
            onChange={(val) => setConfig({
              ...config,
              openobserve: { ...config.openobserve, flushInterval: val }
            })}
          />
        </div>
      </ConfigSection>
    </div>
  )
}