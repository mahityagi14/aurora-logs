#!/bin/bash

# Script to run the React dashboard locally

echo "Aurora Log System - React Dashboard"
echo "===================================="
echo ""
echo "Setting up and running the dashboard..."
echo ""

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

echo ""
echo "Starting development server..."
echo "The dashboard will be available at http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Run the development server
npm run dev