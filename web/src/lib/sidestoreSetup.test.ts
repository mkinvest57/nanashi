import { describe, expect, it } from 'vitest'
import { initialSetupProgress, readSetupProgress, saveSetupProgress, setupProgressFromURL, SETUP_IPHONE_URL, SETUP_LINKS, SETUP_STEPS, SETUP_STORAGE_KEY } from './sidestoreSetup'

function memoryStorage(raw: string | null) {
  let value = raw
  return { getItem: () => value, setItem: (key: string, next: string) => {
    expect(key).toBe(SETUP_STORAGE_KEY)
    value = next
  } }
}

describe('browser-local setup progress', () => {
  it.each([
    '{broken',
    JSON.stringify({ version: 2, step: 'activate', computer: 'mac', confirmed: [] }),
    JSON.stringify({ version: 1, step: 'unknown', computer: 'mac', confirmed: [] }),
    JSON.stringify({ version: 1, step: 'activate', computer: 'linux', confirmed: [] }),
    JSON.stringify({ version: 1, step: 'activate', computer: 'mac', confirmed: ['unknown'] }),
  ])('recovers safely from invalid stored state (%s)', raw => {
    expect(readSetupProgress(memoryStorage(raw), 'windows')).toEqual(initialSetupProgress('windows'))
  })

  it('restores only supported progress fields and does not count duplicates twice', () => {
    const storage = memoryStorage(JSON.stringify({ version: 1, step: 'activate', computer: 'windows', confirmed: ['computer', 'computer', 'connect'], extra: 'not part of progress' }))
    expect(readSetupProgress(storage)).toEqual({ version: 1, step: 'activate', computer: 'windows', confirmed: ['computer', 'connect'] })
  })

  it('round-trips progress without depending on a real browser', () => {
    const storage = memoryStorage(null)
    const progress = { ...initialSetupProgress('windows'), step: 'prepare' as const, confirmed: ['computer' as const] }
    expect(saveSetupProgress(storage, progress)).toBe(true)
    expect(readSetupProgress(storage)).toEqual(progress)
  })

  it('reports a storage failure without breaking navigation', () => {
    const storage = { getItem: () => { throw new Error('blocked') }, setItem: () => { throw new Error('full') } }
    expect(readSetupProgress(storage)).toEqual(initialSetupProgress())
    expect(saveSetupProgress(storage, initialSetupProgress())).toBe(false)
    expect(saveSetupProgress(null, initialSetupProgress())).toBe(false)
  })

  it('preserves completed six-step progress without marking the new automation stage complete', () => {
    const previous = { version: 1, step: 'nanashi', computer: 'windows', confirmed: ['computer', 'connect', 'install', 'prepare', 'activate', 'nanashi'] }
    const restored = readSetupProgress(memoryStorage(JSON.stringify(previous)))
    expect(restored).toEqual(previous)
    expect(restored.confirmed).not.toContain('automation')
    expect(restored.confirmed.length).toBeLessThan(SETUP_STEPS.length)
  })

  it('adds automation after Nanashi without renaming or reordering existing steps', () => {
    expect(SETUP_STEPS.map(step => step.id)).toEqual(['computer', 'connect', 'install', 'prepare', 'activate', 'nanashi', 'automation'])
    expect(SETUP_LINKS.shortcut).toBe('https://www.icloud.com/shortcuts/2afd063477f048f0a16f04c268ce9655')
  })
})

describe('setup step links', () => {
  const saved = { ...initialSetupProgress('windows'), step: 'connect' as const, confirmed: ['computer' as const] }

  it.each(['computer', 'connect', 'install', 'prepare', 'activate', 'nanashi', 'automation'] as const)(
    'opens the requested %s step without confirming actions or changing the chosen computer', step => {
      const result = setupProgressFromURL(saved, `?step=${step}&from=desktop`)
      expect(result).toEqual({ version: 1, step, computer: 'windows', confirmed: ['computer'] })
      expect(saved).toEqual({ version: 1, step: 'connect', computer: 'windows', confirmed: ['computer'] })
    },
  )

  it.each(['', '?from=desktop', '?step=', '?step=unknown', '?step=Prepare', '?step=%20prepare', '?step=__proto__', '?step=constructor', '?step=javascript%3Aalert(1)'])(
    'keeps saved progress when the URL has no supported step (%s)', search => {
      expect(setupProgressFromURL(saved, search)).toBe(saved)
    },
  )

  it('points the iPhone handoff at the preparation heading without inventing completed steps', () => {
    expect(SETUP_IPHONE_URL).toBe('https://nanashi-mk.vercel.app/installation-sidestore?step=prepare#setup-step-heading')
    const result = setupProgressFromURL(initialSetupProgress(), new URL(SETUP_IPHONE_URL).search)
    expect(result).toEqual({ version: 1, step: 'prepare', computer: 'mac', confirmed: [] })
  })
})
