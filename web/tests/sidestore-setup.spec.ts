import { test, expect } from '@playwright/test'

const guide = '/installation-sidestore'
const storageKey = 'nanashi.sidestore.setup.v1'

test('first-time installation opens the local guide without external documentation', async ({ page }) => {
  await page.goto('/#installer')
  await page.getByRole('button', { name: 'Première installation', exact: true }).click()
  await page.getByRole('link', { name: 'Configurer SideStore pas à pas' }).click()
  await expect(page).toHaveURL(new RegExp(`${guide}$`))
  await expect(page.getByRole('heading', { level: 1, name: 'Installation SideStore' })).toBeVisible()
  await expect(page).toHaveTitle('Installation SideStore — Nanashi')
  await expect(page.locator('a[href*="docs.sidestore.io"]')).toHaveCount(0)
  await expect(page.locator('input[type="password"], input[type="email"]')).toHaveCount(0)
})

test('Mac and Windows expose the right direct downloads', async ({ page }) => {
  await page.goto(guide)
  await page.getByRole('button', { name: 'Mac', exact: true }).click()
  await expect(page.locator('a[href$="/iloader-darwin-universal.dmg"]')).toBeVisible()
  await expect(page.locator('a[href$="/iloader-windows-x64.msi"]')).not.toBeVisible()
  await page.getByRole('button', { name: 'Windows', exact: true }).click()
  await expect(page.locator('a[href$="/iloader-windows-x64.msi"]')).toBeVisible()
  await expect(page.locator('a[href="https://www.apple.com/itunes/download/win64"]')).toBeVisible()
  await expect(page.locator('a[href$="/iloader-darwin-universal.dmg"]')).not.toBeVisible()
})

test('progress survives a refresh and previous steps remain freely accessible', async ({ page }) => {
  await page.goto(guide)
  await page.getByRole('button', { name: 'Windows', exact: true }).click()
  for (let i = 0; i < 3; i++) await page.getByRole('button', { name: 'C’est fait, continuer', exact: true }).click()
  await expect(page.locator('#setup-step-heading')).toHaveText('Préparer l’iPhone')
  await expect(page.locator('#setup-step-heading')).toBeFocused()
  await page.reload()
  await expect(page.locator('#setup-step-heading')).toHaveText('Préparer l’iPhone')
  await page.getByRole('button', { name: 'Étape 1 : Préparer l’ordinateur', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Windows', exact: true })).toHaveAttribute('aria-pressed', 'true')
  await page.getByRole('button', { name: 'Étape 5 : Activer SideStore', exact: true }).click()
  await expect(page.locator('#setup-step-heading')).toHaveText('Activer SideStore')
  await expect(page.getByText(/DAYS/).first()).toBeVisible()
  await page.getByRole('button', { name: 'Étape 6 : Installer Nanashi', exact: true }).click()
  await expect(page.getByRole('link', { name: 'Installer Nanashi', exact: true })).toHaveAttribute('href', '/#installer')
  // Browsing the guide never attempts an installation or claims device verification.
  await expect(page.locator('a[href^="sidestore:"]')).toHaveCount(0)
  await expect(page.getByText(/installation détectée|Nanashi est installée/i)).toHaveCount(0)
})

test('invalid saved progress falls back to a usable first step', async ({ page }) => {
  await page.addInitScript(key => localStorage.setItem(key, '{bad json'), storageKey)
  await page.goto(guide)
  await expect(page.locator('#setup-step-heading')).toHaveText('Préparer l’ordinateur')
  await page.getByRole('button', { name: 'C’est fait, continuer', exact: true }).click()
  await expect(page.locator('#setup-step-heading')).toHaveText('Brancher l’iPhone')
})

test('a reader joining on the final step can explicitly finish and reset the guide', async ({ page }) => {
  await page.goto(guide)
  await page.getByRole('button', { name: 'Étape 6 : Installer Nanashi', exact: true }).click()
  await page.getByRole('button', { name: 'Marquer le guide comme terminé', exact: true }).click()
  await expect(page.getByRole('status').filter({ hasText: 'Guide marqué comme terminé' })).toBeVisible()
  await page.reload()
  await expect(page.getByRole('status').filter({ hasText: 'Guide marqué comme terminé' })).toBeVisible()
  await page.getByRole('button', { name: 'Recommencer le guide', exact: true }).click()
  await expect(page.locator('#setup-step-heading')).toHaveText('Préparer l’ordinateur')
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('value', '0')
  await page.reload()
  await expect(page.locator('#setup-step-heading')).toHaveText('Préparer l’ordinateur')
})

test('blocked browser storage does not block setup', async ({ page }) => {
  await page.addInitScript(() => {
    Storage.prototype.getItem = () => { throw new DOMException('Blocked', 'SecurityError') }
    Storage.prototype.setItem = () => { throw new DOMException('Blocked', 'SecurityError') }
    Storage.prototype.removeItem = () => { throw new DOMException('Blocked', 'SecurityError') }
  })
  await page.goto(guide)
  await page.getByRole('button', { name: 'C’est fait, continuer', exact: true }).click()
  await expect(page.locator('#setup-step-heading')).toHaveText('Brancher l’iPhone')
})

test('all steps remain reachable at 320px with large text and reduced motion', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 640 })
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto(`${guide}/`)
  await page.evaluate(() => { document.documentElement.style.fontSize = '150%' })
  const names = ['Préparer l’ordinateur', 'Brancher l’iPhone', 'Installer SideStore', 'Préparer l’iPhone', 'Activer SideStore', 'Installer Nanashi']
  for (let i = 0; i < names.length; i++) {
    await page.getByRole('button', { name: `Étape ${i + 1} : ${names[i]}`, exact: true }).click()
    await expect(page.locator('#setup-step-heading')).toHaveText(names[i])
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  }
  await page.getByRole('link', { name: 'Installer Nanashi', exact: true }).scrollIntoViewIfNeeded()
  await expect(page.getByRole('link', { name: 'Installer Nanashi', exact: true })).toBeVisible()
})
