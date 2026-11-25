/** Populated only after preview packages have passed their build checks and are published. */
export interface InstallerPackage { url: string; sha256: string; size: number }
export interface InstallerRelease { version: string; releaseURL: string; mac: InstallerPackage; windows: InstallerPackage }
export const INSTALLER_RELEASE: InstallerRelease | null = {
  "version": "0.1.3-preview.1",
  "releaseURL": "https://github.com/mkinvest57/nanashi-installer/releases/tag/v0.1.3-preview.1",
  "mac": {
    "url": "https://github.com/mkinvest57/nanashi-installer/releases/download/v0.1.3-preview.1/Nanashi-Installer-macOS.dmg",
    "sha256": "7a3b778594b41cd014772e5107d063b6c68b61469bba1b02e527b73896fd6bd3",
    "size": 26696424
  },
  "windows": {
    "url": "https://github.com/mkinvest57/nanashi-installer/releases/download/v0.1.3-preview.1/Nanashi-Installer-Windows.exe",
    "sha256": "cd964a023d5165cd28ebb6f5512b6e98ffb209914f8290cc37f0ab69cadf77fc",
    "size": 7822599
  }
}
