import { lazy, StrictMode, Suspense } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import './styles.css'

const SideStoreSetup = lazy(() => import('./components/SideStoreSetup'))
const isSetupPage = window.location.pathname.replace(/\/$/, '') === '/installation-sidestore'

if (isSetupPage) {
  document.title = 'Installation SideStore — Nanashi'
  document.querySelector('meta[name="description"]')?.setAttribute('content',
    'Installez SideStore puis Nanashi sur votre iPhone. Un guide en français, étape par étape, avec les liens de téléchargement pour Mac et Windows.')
}

createRoot(document.getElementById('root')!).render(<StrictMode>
  {isSetupPage
    ? <Suspense fallback={<main className="page-width"><p role="status">Chargement du guide d’installation…</p><a href="/#installer">Retour à Nanashi</a></main>}><SideStoreSetup /></Suspense>
    : <App />}
</StrictMode>)
