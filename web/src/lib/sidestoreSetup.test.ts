import { describe, expect, it } from 'vitest'
import { initialSetupProgress, readSetupProgress, saveSetupProgress, SETUP_STORAGE_KEY } from './sidestoreSetup'

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
})
