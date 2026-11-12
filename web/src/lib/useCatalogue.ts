import { useEffect, useState } from 'react'
import { fetchCatalogue } from './releases'
import type { Catalogue } from './releases'

type CatalogueState = { status: 'loading' } | { status: 'ready'; data: Catalogue } | { status: 'error' }

export function useCatalogue() {
  const [state, setState] = useState<CatalogueState>({ status: 'loading' })
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    const controller = new AbortController()
    let active = true
    setState({ status: 'loading' })
    const timer = window.setTimeout(() => controller.abort(), 12_000)
    fetchCatalogue(controller.signal).then(data => {
      if (active) setState({ status: 'ready', data })
    }).catch(() => { if (active) setState({ status: 'error' }) })
      .finally(() => window.clearTimeout(timer))
    return () => { active = false; controller.abort(); window.clearTimeout(timer) }
  }, [attempt])
  return { state, retry: () => setAttempt(value => value + 1) }
}
