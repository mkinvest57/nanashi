import type { Platform } from '../components/PlatformTabs'
import { httpsURL } from './releases'

type DeviceHints = { userAgent: string; platform?: string; maxTouchPoints?: number }

/** Select a phone guide, never infer whether SideStore or Nanashi is installed. */
export function detectPhonePlatform(hints: DeviceHints): Platform | null {
  if (/Android/i.test(hints.userAgent)) return 'android'
  if (/iPhone|iPad|iPod/i.test(hints.userAgent)
    || (hints.platform === 'MacIntel' && (hints.maxTouchPoints ?? 0) > 1)) return 'ios'
  return null
}

export function sideStoreInstallURL(downloadURL: string): string | null {
  return httpsURL(downloadURL) ? `sidestore://install?url=${encodeURIComponent(downloadURL)}` : null
}

export function androidVersionLabel(minSDK: number): string {
  const versions: Record<number, string> = {
    26: '8', 27: '8.1', 28: '9', 29: '10', 30: '11', 31: '12',
    32: '12L', 33: '13', 34: '14', 35: '15', 36: '16',
  }
  return versions[minSDK] ? `Android ${versions[minSDK]} ou version ultérieure` : 'Compatibilité précisée dans les notes de version'
}
