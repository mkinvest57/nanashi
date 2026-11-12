/** Populated only after preview packages have passed their build checks and are published. */
export interface InstallerPackage { url: string; sha256: string; size: number }
export interface InstallerRelease { version: string; releaseURL: string; mac: InstallerPackage; windows: InstallerPackage }
export const INSTALLER_RELEASE: InstallerRelease | null = {
  "version": "0.1.1-preview.1",
  "releaseURL": "https://github.com/mkinvest57/nanashi-installer/releases/tag/v0.1.1-preview.1",
  "mac": {
    "url": "https://github.com/mkinvest57/nanashi-installer/releases/download/v0.1.1-preview.1/Nanashi-Installer-macOS.dmg",
    "sha256": "64bf347dff6f8cab3052a9d6073a00da130a5703f2b7dfe0a1437b64729e9cf9",
    "size": 20462310
  },
  "windows": {
    "url": "https://github.com/mkinvest57/nanashi-installer/releases/download/v0.1.1-preview.1/Nanashi-Installer-Windows.exe",
    "sha256": "0b194249b75ff674198eba18d67d92613cae9e7b611b41a3a3b8b8f955fc7f31",
    "size": 6451119
  }
}
