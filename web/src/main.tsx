import '@fontsource-variable/nunito'
import './styles/app.css'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { HashRouter } from 'react-router-dom'
import { App } from './App'
import { DbProvider } from './data/DbContext'
import { applyTheme } from './pages/Settings'

// Apply the saved theme before the first paint to avoid a flash.
applyTheme((localStorage.getItem('livo.theme') as 'auto' | 'light' | 'dark') || 'auto')

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <HashRouter>
      <DbProvider>
        <App />
      </DbProvider>
    </HashRouter>
  </StrictMode>,
)

// Offline support: cache the app shell after the first visit. Production builds only, so dev reloads stay predictable.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => void navigator.serviceWorker.register('./sw.js'))
}
