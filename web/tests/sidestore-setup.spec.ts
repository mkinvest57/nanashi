import { test, expect } from '@playwright/test'
import { INSTALLER_RELEASE } from '../src/lib/installerRelease'

const guide = '/installation-sidestore'
const storageKey = 'nanashi.sidestore.setup.v1'
const iphoneStepURL = 'https://nanashi-mk.vercel.app/installation-sidestore?step=prepare#setup-step-heading'
const shortcutURL = 'https://www.icloud.com/shortcuts/2afd063477f048f0a16f04c268ce9655'

test('the existing SideStore guide stays accessible without external documentation', async ({ page }) => {
  await page.goto('/#installer')
  await page.getByRole('button', { name: 'Première installation', exact: true }).click()
  await page.getByRole('link', { name: INSTALLER_RELEASE ? 'Conserver le parcours SideStore existant' : 'Configurer SideStore pas à pas' }).click()
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
  await page.getByRole('button', { name: 'Étape 7 : Automatiser le renouvellement', exact: true }).click()
  await page.getByRole('button', { name: 'Marquer le guide comme terminé', exact: true }).click()
  await expect(page.getByRole('status').filter({ hasText: 'Guide marqué comme terminé' })).toBeVisible()
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('value', '7')
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('max', '7')
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
  const names = ['Préparer l’ordinateur', 'Brancher l’iPhone', 'Installer SideStore', 'Préparer l’iPhone', 'Activer SideStore', 'Installer Nanashi', 'Automatiser le renouvellement']
  for (let i = 0; i < names.length; i++) {
    const step = page.getByRole('button', { name: `Étape ${i + 1} : ${names[i]}`, exact: true })
    await step.click()
    const bounds = await step.boundingBox()
    expect(bounds?.width).toBeGreaterThanOrEqual(44)
    expect(bounds?.height).toBeGreaterThanOrEqual(44)
    await expect(page.locator('#setup-step-heading')).toHaveText(names[i])
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  }
  await page.getByRole('link', { name: 'Installer le raccourci', exact: true }).scrollIntoViewIfNeeded()
  await expect(page.getByRole('link', { name: 'Installer le raccourci', exact: true })).toBeVisible()
})

test('previously completed six-step progress remains intact and awaits the new automation confirmation', async ({ page }) => {
  await page.goto(guide)
  await page.getByRole('heading', { name: 'Installation SideStore', exact: true }).waitFor()
  const previous = { version: 1, step: 'nanashi', computer: 'windows', confirmed: ['computer', 'connect', 'install', 'prepare', 'activate', 'nanashi'] }
  await page.evaluate(({ key, value }) => localStorage.setItem(key, JSON.stringify(value)), { key: storageKey, value: previous })
  await page.reload()
  await expect(page.locator('#setup-step-heading')).toHaveText('Installer Nanashi')
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('value', '6')
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('max', '7')
  await expect(page.getByRole('status').filter({ hasText: 'Guide marqué comme terminé' })).toHaveCount(0)
  expect(await page.evaluate(key => JSON.parse(localStorage.getItem(key)!), storageKey)).toEqual(previous)

  await page.getByRole('button', { name: 'C’est fait, continuer', exact: true }).click()
  await expect(page.locator('#setup-step-heading')).toHaveText('Automatiser le renouvellement')
  await expect(page.getByRole('button', { name: 'Marquer le guide comme terminé', exact: true })).toBeVisible()
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('value', '6')
  await expect(page.getByRole('status').filter({ hasText: 'Guide marqué comme terminé' })).toHaveCount(0)
  await page.reload()
  await expect(page.locator('#setup-step-heading')).toHaveText('Automatiser le renouvellement')
  expect(await page.evaluate(key => JSON.parse(localStorage.getItem(key)!), storageKey)).toEqual({ ...previous, step: 'automation' })
})

test('the automation stage links the verified shared shortcut without running it or claiming installation', async ({ page }) => {
  await page.goto(`${guide}?step=automation#setup-step-heading`)
  await expect(page.locator('#setup-step-heading')).toHaveText('Automatiser le renouvellement')
  await expect(page.getByRole('link', { name: 'Installer le raccourci', exact: true })).toHaveAttribute('href', shortcutURL)
  await expect(page.getByText('Refresh All Apps', { exact: true }).first()).toBeVisible()
  await expect(page.locator('a[href^="sidestore://refresh"], a[href*="run-shortcut"]')).toHaveCount(0)
  await expect(page.getByRole('status').filter({ hasText: 'Guide marqué comme terminé' })).toHaveCount(0)
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('value', '0')
})

test('the preparation step offers a desktop QR and link directly to the same iPhone step', async ({ page }) => {
  await page.goto(guide)
  await page.getByRole('button', { name: 'Étape 4 : Préparer l’iPhone', exact: true }).click()
  const handoff = page.getByRole('region', { name: 'Ouvrez maintenant ce site sur votre iPhone' })
  await expect(handoff).toBeVisible()
  await expect(handoff.getByRole('img', { name: 'QR code pour ouvrir l’étape Préparer l’iPhone sur votre iPhone' })).toHaveAttribute('src', '/sidestore-iphone-qr.svg')
  await expect(handoff.getByRole('link', { name: 'Ouvrir cette étape sur l’iPhone', exact: true })).toHaveAttribute('href', iphoneStepURL)
  await expect(handoff.getByRole('button', { name: 'Copier le lien de cette étape', exact: true })).toBeVisible()
  // Avoid showing a second, generic QR that would lose the selected step.
  await expect(page.locator('img[src="/sidestore-setup-qr.svg"]')).toHaveCount(0)
  const qr = await page.request.get('/sidestore-iphone-qr.svg')
  expect(qr.status()).toBe(200)
  expect(qr.headers()['content-type']).toContain('image/svg+xml')
})

test('a step link is consumed once while preserving other URL fields and saved progress', async ({ page }) => {
  await page.goto(guide)
  await page.getByRole('heading', { name: 'Installation SideStore', exact: true }).waitFor()
  await page.evaluate(key => localStorage.setItem(key, JSON.stringify({
    version: 1, step: 'connect', computer: 'windows', confirmed: ['computer', 'connect'],
  })), storageKey)
  await page.goto(`${guide}?from=desktop&step=prepare&label=hello%20world#setup-step-heading`)
  await expect(page.locator('#setup-step-heading')).toHaveText('Préparer l’iPhone')
  await expect(page.locator('#setup-step-heading')).toBeFocused()
  await expect.poll(() => new URL(page.url()).searchParams.has('step')).toBe(false)
  const url = new URL(page.url())
  expect(url.searchParams.get('from')).toBe('desktop')
  expect(url.searchParams.get('label')).toBe('hello world')
  expect(url.hash).toBe('#setup-step-heading')
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('value', '2')
  expect(await page.evaluate(key => JSON.parse(localStorage.getItem(key)!), storageKey)).toEqual({
    version: 1, step: 'prepare', computer: 'windows', confirmed: ['computer', 'connect'],
  })

  await page.getByRole('button', { name: 'C’est fait, continuer', exact: true }).click()
  await expect(page.locator('#setup-step-heading')).toHaveText('Activer SideStore')
  await page.reload()
  await expect(page.locator('#setup-step-heading')).toHaveText('Activer SideStore')
  expect(await page.evaluate(key => JSON.parse(localStorage.getItem(key)!), storageKey)).toEqual({
    version: 1, step: 'activate', computer: 'windows', confirmed: ['computer', 'connect', 'prepare'],
  })
  expect(new URL(page.url()).searchParams.get('from')).toBe('desktop')
})

test('an unsupported step parameter cannot replace the saved step or confirmations', async ({ page }) => {
  await page.goto(guide)
  await page.getByRole('button', { name: 'C’est fait, continuer', exact: true }).click()
  await expect(page.locator('#setup-step-heading')).toHaveText('Brancher l’iPhone')
  await page.goto(`${guide}?step=unknown&from=message`)
  await expect(page.locator('#setup-step-heading')).toHaveText('Brancher l’iPhone')
  await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('value', '1')
  await expect.poll(() => new URL(page.url()).searchParams.has('step')).toBe(false)
  expect(new URL(page.url()).searchParams.get('from')).toBe('message')
})

test.describe('handoff already opened on iPhone', () => {
  test.use({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1' })

  test('shows the on-device checkpoint rather than asking the iPhone to scan itself', async ({ page }) => {
    await page.goto(`${guide}?step=prepare#setup-step-heading`)
    await expect(page.locator('#setup-step-heading')).toHaveText('Préparer l’iPhone')
    await expect(page.getByText('Vous avez ouvert le guide sur votre iPhone. Suivez les réglages ci-dessous, puis revenez ici pour continuer.', { exact: true })).toBeVisible()
    await expect(page.getByRole('img', { name: /QR code/ })).toHaveCount(0)
    await expect(page.getByRole('heading', { name: 'Ouvrez maintenant ce site sur votre iPhone' })).toHaveCount(0)
    await expect(page.getByRole('link', { name: 'Obtenir LocalDevVPN', exact: true })).toBeVisible()
    await expect(page.getByRole('progressbar', { name: 'Étapes confirmées' })).toHaveAttribute('value', '0')
  })
})

test.describe('handoff viewed on Android', () => {
  test.use({ userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36' })

  test('retains the QR to continue on a separate iPhone', async ({ page }) => {
    await page.goto(`${guide}?step=prepare#setup-step-heading`)
    await expect(page.getByRole('region', { name: 'Ouvrez maintenant ce site sur votre iPhone' })).toBeVisible()
    await expect(page.getByRole('img', { name: 'QR code pour ouvrir l’étape Préparer l’iPhone sur votre iPhone' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Ouvrir cette étape sur l’iPhone', exact: true })).toHaveAttribute('href', iphoneStepURL)
    await expect(page.getByText('Vous avez ouvert le guide sur votre iPhone.', { exact: false })).toHaveCount(0)
  })
})
