import React from 'react'
import ReactDOM from 'react-dom/client'
import { HashRouter } from 'react-router-dom'
import App from './App'
import { ThemeProvider } from './contexts/ThemeContext'
import './index.css'

// Add error boundary and console logging
window.addEventListener('error', (e) => {
  console.error('Global error:', e.error);
});

window.addEventListener('unhandledrejection', (e) => {
  console.error('Unhandled promise rejection:', e.reason);
});

try {
  const root = ReactDOM.createRoot(document.getElementById('root'));
  console.log('React root created successfully');
  
  root.render(
    <React.StrictMode>
      <ThemeProvider>
        <HashRouter>
          <App />
        </HashRouter>
      </ThemeProvider>
    </React.StrictMode>
  );
  console.log('App rendered successfully');
} catch (error) {
  console.error('Error during app initialization:', error);
  document.getElementById('root').innerHTML = `<div style="color: red; padding: 20px;">Error: ${error.message}</div>`;
}