# Aurora Log System React Dashboard

A modern React 19.1 dashboard for monitoring and managing Aurora MySQL log collection.

## Features

- **Dashboard Overview**: Real-time metrics, processing rates, and active jobs
- **RDS Instance Management**: Enable/disable log collection per instance
- **Metrics Visualization**: Log distribution, compression stats, and top producers
- **Issue Tracking**: Monitor and resolve system issues
- **Configuration**: Adjust system parameters

## Prerequisites

- Node.js 18+ 
- npm or yarn

## Installation

```bash
cd ui/react-dashboard
npm install
```

## Development

```bash
npm run dev
```

The dashboard will be available at http://localhost:3000

## Build

```bash
npm run build
```

## Project Structure

```
react-dashboard/
├── src/
│   ├── components/     # Reusable components
│   ├── pages/         # Page components
│   │   ├── Dashboard.jsx
│   │   ├── Instances.jsx
│   │   ├── Metrics.jsx
│   │   ├── Issues.jsx
│   │   └── Configuration.jsx
│   ├── utils/         # Utilities and mock data
│   ├── App.jsx        # Main app component
│   └── main.jsx       # Entry point
├── public/            # Static assets
└── package.json
```

## Mock Data

Currently using mock data from `src/utils/mockData.js`. In production, this would connect to the backend APIs.

## Technologies Used

- React 19.1
- React Router for navigation
- Recharts for data visualization
- Tailwind CSS for styling
- Lucide React for icons
- Vite for build tooling