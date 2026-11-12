export const REPOSITORY = 'https://github.com/mkinvest57/nanashi'

export interface Artifact {
  version: string
  build: string
  downloadURL: string
  size: number
  sha256: string
}
export interface IOSArtifact extends Artifact {
  bundleIdentifier: string
  minOSVersion: string
}
export interface AndroidArtifact extends Artifact {
  applicationId: string
  minSDK: number
}
export interface Release {
  version: string
  releaseURL: string
  publishedAt: string
  ios?: IOSArtifact
  android?: AndroidArtifact
}
export interface Catalogue {
  schemaVersion: 1
  repository: string
  updatedAt: string | null
  latest: Release | null
  sideStore?: { sourceURL: string; addSourceURL: string }
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}
function text(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}
export function httpsURL(value: unknown): value is string {
  if (!text(value)) return false
  try {
    const parsed = new URL(value)
    return parsed.protocol === 'https:' && !parsed.username && !parsed.password
  } catch { return false }
}
function date(value: unknown): value is string {
  return text(value) && Number.isFinite(Date.parse(value))
}
function parseArtifact(value: unknown): Artifact | undefined {
  if (!record(value) || !text(value.version)
    || !(text(value.build) || (Number.isSafeInteger(value.build) && Number(value.build) >= 0))
    || !httpsURL(value.downloadURL)
    || !Number.isSafeInteger(value.size) || Number(value.size) <= 0
    || typeof value.sha256 !== 'string' || !/^[a-f\d]{64}$/i.test(value.sha256)) return
  return {
    version: value.version, build: String(value.build), downloadURL: value.downloadURL,
    size: Number(value.size), sha256: value.sha256.toLowerCase(),
  }
}

/** Invalid artifacts are omitted independently; broken metadata never becomes a download button. */
export function parseCatalogue(input: unknown): Catalogue {
  if (!record(input) || input.schemaVersion !== 1 || input.repository !== REPOSITORY)
    throw new Error('Unsupported release catalogue')
  const result: Catalogue = { schemaVersion: 1, repository: REPOSITORY,
    updatedAt: date(input.updatedAt) ? input.updatedAt : null, latest: null }
  if (input.latest === null) return result
  const value = input.latest
  if (!record(value) || !text(value.version) || !httpsURL(value.releaseURL) || !date(value.publishedAt))
    throw new Error('Incomplete release metadata')
  const latest: Release = { version: value.version, releaseURL: value.releaseURL, publishedAt: value.publishedAt }
  const ios = parseArtifact(value.ios)
  if (ios && ios.version === latest.version && record(value.ios) && value.ios.bundleIdentifier === 'com.rayanmakhlouf.noopdev.noop'
    && text(value.ios.minOSVersion) && /^\d+(\.\d+){0,2}$/.test(value.ios.minOSVersion)) {
    latest.ios = { ...ios, bundleIdentifier: value.ios.bundleIdentifier, minOSVersion: value.ios.minOSVersion }
  }
  const android = parseArtifact(value.android)
  if (android && android.version === latest.version && record(value.android) && value.android.applicationId === 'com.rayanmakhlouf.nanashi'
    && Number.isSafeInteger(value.android.minSDK) && Number(value.android.minSDK) >= 26) {
    latest.android = { ...android, applicationId: value.android.applicationId, minSDK: Number(value.android.minSDK) }
  }
  result.latest = latest
  if (latest.ios && record(input.sideStore) && httpsURL(input.sideStore.sourceURL)) {
    // Derive the deep link from the validated HTTPS source instead of trusting an arbitrary URI.
    result.sideStore = { sourceURL: input.sideStore.sourceURL,
      addSourceURL: `sidestore://source?url=${encodeURIComponent(input.sideStore.sourceURL)}` }
  }
  return result
}

async function fetchFirebaseCatalogue(projectId: string, signal: AbortSignal): Promise<Catalogue> {
  const controller = new AbortController()
  const abort = () => controller.abort()
  if (signal.aborted) controller.abort()
  signal.addEventListener('abort', abort, { once: true })
  const timer = window.setTimeout(abort, 3_000)
  try {
    const endpoint = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/catalogue/stable`
    const response = await fetch(endpoint, { signal: controller.signal, credentials: 'omit' })
    if (!response.ok) throw new Error('Remote catalogue unavailable')
    const document: unknown = await response.json()
    if (!record(document) || !record(document.fields) || !record(document.fields.manifest)
      || typeof document.fields.manifest.stringValue !== 'string') throw new Error('Invalid remote catalogue')
    return parseCatalogue(JSON.parse(document.fields.manifest.stringValue))
  } finally {
    window.clearTimeout(timer)
    signal.removeEventListener('abort', abort)
  }
}

async function fetchStaticCatalogue(signal: AbortSignal): Promise<Catalogue> {
  const controller = new AbortController()
  const abort = () => controller.abort()
  if (signal.aborted) controller.abort()
  signal.addEventListener('abort', abort, { once: true })
  const timer = window.setTimeout(abort, 5_000)
  try {
    const response = await fetch('/releases.json', { signal: controller.signal, cache: 'no-cache', credentials: 'omit' })
    if (!response.ok) throw new Error('Release catalogue unavailable')
    return parseCatalogue(await response.json())
  } finally {
    window.clearTimeout(timer)
    signal.removeEventListener('abort', abort)
  }
}

function hasDownloads(catalogue: Catalogue): boolean {
  return !!(catalogue.latest?.ios || catalogue.latest?.android)
}

function compareVersions(left: string, right: string): number {
  if (!/^\d+\.\d+\.\d+$/.test(left) || !/^\d+\.\d+\.\d+$/.test(right)) return 0
  const a = left.split('.').map(Number)
  const b = right.split('.').map(Number)
  if (![...a, ...b].every(Number.isSafeInteger)) return 0
  for (let index = 0; index < a.length; index += 1) {
    if (a[index] !== b[index]) return a[index] > b[index] ? 1 : -1
  }
  return 0
}

/** A stale mirror must not hide a newer shipped catalogue, even after a successful read. */
export function newestCatalogue(local: Catalogue, remote: Catalogue): Catalogue {
  const localReady = hasDownloads(local)
  const remoteReady = hasDownloads(remote)
  if (localReady !== remoteReady) return localReady ? local : remote
  if (!localReady || !local.latest || !remote.latest) return local
  const versionOrder = compareVersions(remote.latest.version, local.latest.version)
  if (versionOrder !== 0) return versionOrder > 0 ? remote : local
  const publishedOrder = Date.parse(remote.latest.publishedAt) - Date.parse(local.latest.publishedAt)
  if (publishedOrder !== 0) return publishedOrder > 0 ? remote : local
  // Identical release dates should prefer the versioned local file. updatedAt is
  // deliberately ignored: copying old metadata does not make the release newer.
  return local
}

export async function fetchCatalogue(signal: AbortSignal, firebaseProjectId = import.meta.env.VITE_FIREBASE_PROJECT_ID): Promise<Catalogue> {
  if (signal.aborted) throw new DOMException('Aborted', 'AbortError')
  const local = fetchStaticCatalogue(signal)
  // One optional public document read, never a listener, account or health upload.
  if (typeof firebaseProjectId !== 'string' || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(firebaseProjectId)) return local
  const results = await Promise.allSettled([local, fetchFirebaseCatalogue(firebaseProjectId, signal)])
  if (signal.aborted) throw new DOMException('Aborted', 'AbortError')
  const [localResult, remoteResult] = results
  if (localResult.status === 'fulfilled' && remoteResult.status === 'fulfilled') return newestCatalogue(localResult.value, remoteResult.value)
  if (localResult.status === 'fulfilled') return localResult.value
  if (remoteResult.status === 'fulfilled') return remoteResult.value
  throw new Error('Release catalogue unavailable')
}

export function readableSize(bytes: number): string {
  return `${new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 1 }).format(bytes / 1024 / 1024)} Mo`
}
