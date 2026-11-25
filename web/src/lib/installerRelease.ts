/** Populated only after preview packages have passed their build checks and are published. */
export interface InstallerPackage { url: string; sha256: string; size: number }
export interface InstallerRelease { version: string; releaseURL: string; mac: InstallerPackage; windows: InstallerPackage }
export const INSTALLER_RELEASE: InstallerRelease | null = {
  "version": "0.1.2-preview.1",
  "releaseURL": "https://github.com/mkinvest57/nanashi-installer/releases/tag/v0.1.2-preview.1",
  "mac": {
    "url": "https://github.com/mkinvest57/nanashi-installer/releases/download/v0.1.2-preview.1/Nanashi-Installer-macOS.dmg",
    "sha256": "88f14fe7379bc809fe22e7ee95bc2f08cb0a858f5a1d384d60e8cbee48a79d1b",
    "size": 26631340
  },
  "windows": {
    "url": "https://github.com/mkinvest57/nanashi-installer/releases/download/v0.1.2-preview.1/Nanashi-Installer-Windows.exe",
    "sha256": "45e72dc48c268189da3e939b667504ec242f8000b263963e98a9949cc77b8669",
    "size": 7805240
  }
}
