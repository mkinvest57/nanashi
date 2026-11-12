import { afterEach, describe, expect, it, vi } from 'vitest'
import { fetchCatalogue, newestCatalogue, parseCatalogue, REPOSITORY } from './releases'

const artifact = { version: '12.1.0', build: 446, size: 12345678, sha256: 'a'.repeat(64), downloadURL: `${REPOSITORY}/releases/download/nanashi-446/Nanashi.ipa` }
const valid = () => ({ schemaVersion: 1, repository: REPOSITORY, updatedAt: '2026-11-12T00:00:00Z',
  latest: { version: '12.1.0', releaseURL: `${REPOSITORY}/releases/tag/nanashi-446`, publishedAt: '2026-11-12T00:00:00Z',
    ios: { ...artifact, bundleIdentifier: 'com.rayanmakhlouf.noopdev.noop', minOSVersion: '16.0' },
    android: { ...artifact, downloadURL: `${REPOSITORY}/releases/download/nanashi-446/Nanashi.apk`, applicationId: 'com.rayanmakhlouf.nanashi', minSDK: 26 } },
  sideStore: { sourceURL: 'https://nanashi.example/altstore-source.json', addSourceURL: 'javascript:alert(1)' } })

describe('release catalogue boundary', () => {
  it('accepts a truthful no-release catalogue', () => {
    expect(parseCatalogue({ schemaVersion: 1, repository: REPOSITORY, latest: null }).latest).toBeNull()
  })
  it('rejects unknown schemas and repositories', () => {
    expect(() => parseCatalogue({ ...valid(), schemaVersion: 2 })).toThrow()
    expect(() => parseCatalogue({ ...valid(), repository: 'https://example.com' })).toThrow()
  })
  it('normalizes build numbers and derives SideStore URI from HTTPS source only', () => {
    const parsed = parseCatalogue(valid())
    expect(parsed.latest?.ios?.build).toBe('446')
    expect(parsed.sideStore?.addSourceURL).toBe('sidestore://source?url=https%3A%2F%2Fnanashi.example%2Faltstore-source.json')
  })
  it.each(['javascript:alert(1)', 'http://example.com/a.ipa', 'https://secret@example.com/a.ipa'])('omits unsafe download %s while keeping another platform', downloadURL => {
    const data = valid(); data.latest.ios.downloadURL = downloadURL
    const parsed = parseCatalogue(data)
    expect(parsed.latest?.ios).toBeUndefined()
    expect(parsed.sideStore).toBeUndefined()
    expect(parsed.latest?.android).toBeDefined()
  })
  it('never offers a download missing its checksum or with a different app identity', () => {
    const data = valid(); data.latest.ios.bundleIdentifier = 'com.wrong.app'; data.latest.android.sha256 = ''
    expect(parseCatalogue(data).latest).not.toHaveProperty('ios')
    expect(parseCatalogue(data).latest).not.toHaveProperty('android')
  })
  it('handles a single-platform release without advertising SideStore', () => {
    const data = valid(); const input = { ...data, latest: { ...data.latest, ios: undefined }, sideStore: null }
    expect(parseCatalogue(input).latest?.android).toBeDefined()
    expect(parseCatalogue(input).sideStore).toBeUndefined()
  })
  it('does not offer an APK for another Android application', () => {
    const data = valid(); data.latest.android.applicationId = 'com.somebody.else'
    const parsed = parseCatalogue(data)
    expect(parsed.latest?.android).toBeUndefined()
    expect(parsed.latest?.ios).toBeDefined()
  })
  it.each(['ios', 'android'] as const)('omits a %s artifact whose version differs from the release', platform => {
    const data = valid(); data.latest[platform].version = '0.0.1'
    expect(parseCatalogue(data).latest?.[platform]).toBeUndefined()
  })
})

function releaseAt(version: string, publishedAt: string) {
  const data = valid()
  data.latest.version = version
  data.latest.ios.version = version
  data.latest.android.version = version
  data.latest.publishedAt = publishedAt
  return data
}

const empty = () => ({ schemaVersion: 1, repository: REPOSITORY, latest: null })
const response = (body: unknown, remote = false) => new Response(JSON.stringify(remote ? { fields: { manifest: { stringValue: JSON.stringify(body) } } } : body))

describe('catalogue freshness', () => {
  it('prefers a usable local release over an empty remote catalogue', () => {
    const local = parseCatalogue(valid())
    expect(newestCatalogue(local, parseCatalogue(empty()))).toBe(local)
  })
  it('ignores recently updated metadata for an older release', () => {
    const local = parseCatalogue(releaseAt('12.2.0', '2026-11-12T00:00:00Z'))
    const remote = parseCatalogue({ ...releaseAt('12.1.0', '2026-11-11T00:00:00Z'), updatedAt: '2030-01-01T00:00:00Z' })
    expect(newestCatalogue(local, remote)).toBe(local)
  })
  it('compares version counters numerically instead of lexically', () => {
    const local = parseCatalogue(releaseAt('12.2.0', '2026-11-12T00:00:00Z'))
    const remote = parseCatalogue(releaseAt('12.10.0', '2026-11-11T00:00:00Z'))
    expect(newestCatalogue(local, remote)).toBe(remote)
  })
  it('uses publication time when marketing versions agree', () => {
    const local = parseCatalogue(releaseAt('12.2.0', '2026-11-12T00:00:00Z'))
    const remote = parseCatalogue(releaseAt('12.2.0', '2026-11-13T00:00:00Z'))
    expect(newestCatalogue(local, remote)).toBe(remote)
  })
  it('does not prefer a newer catalogue containing no eligible artifacts', () => {
    const local = parseCatalogue(valid())
    const invalid = releaseAt('99.0.0', '2026-11-13T00:00:00Z')
    invalid.latest.ios.bundleIdentifier = 'com.wrong.app'
    invalid.latest.android.sha256 = ''
    expect(newestCatalogue(local, parseCatalogue(invalid))).toBe(local)
  })
})

describe('metadata-only Firebase comparison and fallback', () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers() })
  const timers = () => vi.stubGlobal('window', { setTimeout, clearTimeout })
  const pendingResponse = (_url: string, init: RequestInit) => new Promise((_resolve, reject) => {
    init.signal?.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')))
  })
  function mockCatalogues(local: unknown, remote: unknown) {
    const fetch = vi.fn().mockImplementation((url: string) => Promise.resolve(response(url === '/releases.json' ? local : remote, url !== '/releases.json')))
    vi.stubGlobal('fetch', fetch)
    return fetch
  }
  it('starts both metadata requests together and reads without credentials', async () => {
    timers()
    const fetch = mockCatalogues(valid(), valid())
    const pending = fetchCatalogue(new AbortController().signal, 'nanashi-test')
    expect(fetch).toHaveBeenCalledTimes(2)
    expect(fetch.mock.calls[0][0]).toBe('/releases.json')
    expect(fetch.mock.calls[1][0]).toContain('/documents/catalogue/stable')
    expect(fetch.mock.calls[0][1].credentials).toBe('omit')
    expect(fetch.mock.calls[1][1].credentials).toBe('omit')
    expect((await pending).latest?.ios?.build).toBe('446')
  })
  it('a seeded empty Firestore document cannot hide published files', async () => {
    timers(); mockCatalogues(valid(), empty())
    expect((await fetchCatalogue(new AbortController().signal, 'nanashi-test')).latest?.version).toBe('12.1.0')
  })
  it('a stale remote mirror cannot hide a newer static release', async () => {
    timers(); mockCatalogues(releaseAt('12.3.0', '2026-11-12T00:00:00Z'), valid())
    expect((await fetchCatalogue(new AbortController().signal, 'nanashi-test')).latest?.version).toBe('12.3.0')
  })
  it('selects a newer remote release before a static deployment catches up', async () => {
    timers(); mockCatalogues(valid(), releaseAt('12.3.0', '2026-11-13T00:00:00Z'))
    expect((await fetchCatalogue(new AbortController().signal, 'nanashi-test')).latest?.version).toBe('12.3.0')
  })
  it.each([403, 404, 500])('uses static metadata when Firestore returns %s', async status => {
    timers()
    const fetch = vi.fn().mockImplementation((url: string) => Promise.resolve(url === '/releases.json' ? response(valid()) : new Response('{}', { status })))
    vi.stubGlobal('fetch', fetch)
    expect((await fetchCatalogue(new AbortController().signal, 'nanashi-test')).latest?.version).toBe('12.1.0')
  })
  it('uses Firebase when the static catalogue request fails', async () => {
    timers()
    const fetch = vi.fn().mockImplementation((url: string) => url === '/releases.json' ? Promise.reject(new TypeError('Network error')) : Promise.resolve(response(valid(), true)))
    vi.stubGlobal('fetch', fetch)
    expect((await fetchCatalogue(new AbortController().signal, 'nanashi-test')).latest?.version).toBe('12.1.0')
  })
  it('uses Firebase when static metadata is malformed', async () => {
    timers(); mockCatalogues({ bad: true }, valid())
    expect((await fetchCatalogue(new AbortController().signal, 'nanashi-test')).latest?.version).toBe('12.1.0')
  })
  it('uses static metadata when remote metadata is malformed', async () => {
    timers(); mockCatalogues(valid(), { bad: true })
    expect((await fetchCatalogue(new AbortController().signal, 'nanashi-test')).latest?.version).toBe('12.1.0')
  })
  it('reports unavailability only if both sources fail validation', async () => {
    timers(); mockCatalogues({ bad: true }, { bad: true })
    await expect(fetchCatalogue(new AbortController().signal, 'nanashi-test')).rejects.toThrow('Release catalogue unavailable')
  })
  it('bounds the remote request to three seconds', async () => {
    vi.useFakeTimers(); timers()
    const fetch = vi.fn().mockImplementation((url: string, init: RequestInit) => url === '/releases.json' ? Promise.resolve(response(valid())) : pendingResponse(url, init))
    vi.stubGlobal('fetch', fetch)
    const pending = fetchCatalogue(new AbortController().signal, 'nanashi-test')
    await vi.advanceTimersByTimeAsync(3000)
    expect((await pending).latest?.version).toBe('12.1.0')
    expect(fetch).toHaveBeenCalledTimes(2)
  })
  it('cancels both in-flight reads when the caller leaves the page', async () => {
    timers()
    const controller = new AbortController()
    const fetch = vi.fn().mockImplementation(pendingResponse)
    vi.stubGlobal('fetch', fetch)
    const pending = fetchCatalogue(controller.signal, 'nanashi-test')
    controller.abort()
    await expect(pending).rejects.toMatchObject({ name: 'AbortError' })
    expect(fetch.mock.calls.every(args => (args[1] as RequestInit).signal?.aborted)).toBe(true)
    expect(fetch).toHaveBeenCalledTimes(2)
  })
  it('bounds static catalogue loading to five seconds while keeping a valid remote result', async () => {
    vi.useFakeTimers(); timers()
    const fetch = vi.fn().mockImplementation((url: string, init: RequestInit) => url === '/releases.json' ? pendingResponse(url, init) : Promise.resolve(response(valid(), true)))
    vi.stubGlobal('fetch', fetch)
    const pending = fetchCatalogue(new AbortController().signal, 'nanashi-test')
    await vi.advanceTimersByTimeAsync(5000)
    expect((await pending).latest?.version).toBe('12.1.0')
    expect(fetch.mock.calls[0][1].cache).toBe('no-cache')
  })
  it('does not start requests after cancellation', async () => {
    timers(); const fetch = mockCatalogues(valid(), valid())
    const controller = new AbortController(); controller.abort()
    await expect(fetchCatalogue(controller.signal, 'nanashi-test')).rejects.toMatchObject({ name: 'AbortError' })
    expect(fetch).not.toHaveBeenCalled()
  })
})
