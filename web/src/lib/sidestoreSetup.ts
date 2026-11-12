export const SETUP_STORAGE_KEY = 'nanashi.sidestore.setup.v1'
export const SETUP_GUIDE_URL = 'https://nanashi-mk.vercel.app/installation-sidestore'

export const SETUP_STEPS = [
  { id: 'computer', title: 'Préparer l’ordinateur', short: 'Ordinateur' },
  { id: 'connect', title: 'Brancher l’iPhone', short: 'Connexion' },
  { id: 'install', title: 'Installer SideStore', short: 'SideStore' },
  { id: 'prepare', title: 'Préparer l’iPhone', short: 'iPhone' },
  { id: 'activate', title: 'Activer SideStore', short: 'Activation' },
  { id: 'nanashi', title: 'Installer Nanashi', short: 'Nanashi' },
] as const

export type StepId = typeof SETUP_STEPS[number]['id']
export type SetupComputer = 'mac' | 'windows'
export interface SetupProgress {
  version: 1
  step: StepId
  computer: SetupComputer
  confirmed: StepId[]
}

type ProgressStorage = Pick<Storage, 'getItem' | 'setItem'>
const isStepId = (value: unknown): value is StepId => SETUP_STEPS.some(step => step.id === value)

export function initialSetupProgress(computer: SetupComputer = 'mac'): SetupProgress {
  return { version: 1, step: 'computer', computer, confirmed: [] }
}

export function readSetupProgress(storage: ProgressStorage | null, fallbackComputer: SetupComputer = 'mac'): SetupProgress {
  const fallback = initialSetupProgress(fallbackComputer)
  try {
    const raw = storage?.getItem(SETUP_STORAGE_KEY)
    if (!raw) return fallback
    const saved: unknown = JSON.parse(raw)
    if (!saved || typeof saved !== 'object') return fallback
    const value = saved as Record<string, unknown>
    if (value.version !== 1 || !isStepId(value.step)
      || (value.computer !== 'mac' && value.computer !== 'windows')
      || !Array.isArray(value.confirmed) || !value.confirmed.every(isStepId)) return fallback
    return { version: 1, step: value.step, computer: value.computer, confirmed: [...new Set(value.confirmed)] }
  } catch {
    return fallback
  }
}

export function saveSetupProgress(storage: ProgressStorage | null, progress: SetupProgress): boolean {
  try {
    if (!storage) return false
    storage.setItem(SETUP_STORAGE_KEY, JSON.stringify(progress))
    return true
  } catch {
    return false
  }
}

export const SETUP_LINKS = {
  mac: 'https://github.com/nab138/iloader/releases/latest/download/iloader-darwin-universal.dmg',
  windows: 'https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.msi',
  windowsExe: 'https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.exe',
  itunes: 'https://www.apple.com/itunes/download/win64',
  itunesStore: 'https://apps.microsoft.com/store/detail/9PB2MZ1ZMB1S',
  appleDevices: 'https://apps.microsoft.com/detail/9np83lwlpz9k',
  localDevVPN: 'https://apps.apple.com/app/localdevvpn/id6755608044',
  iloaderSource: 'https://github.com/nab138/iloader',
} as const
