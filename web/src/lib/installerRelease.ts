/** Populated only after preview packages have passed their build checks and are published. */
export interface InstallerPackage { url: string; sha256: string; size: number }
export interface InstallerRelease { version: string; releaseURL: string; mac: InstallerPackage; windows: InstallerPackage }
export const INSTALLER_RELEASE: InstallerRelease | null = null
