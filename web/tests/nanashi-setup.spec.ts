import { expect, test } from '@playwright/test'
import { INSTALLER_RELEASE } from '../src/lib/installerRelease'

const route = '/installation-nanashi'
const repository = 'https://github.com/mkinvest57/nanashi'
const download = `${repository}/releases/download/v12.1.1/Nanashi-ios-v12.1.1.ipa`
const catalogue = { schemaVersion: 1, repository, latest: {
  version: '12.1.1', releaseURL: `${repository}/releases/tag/v12.1.1`, publishedAt: '2026-11-12T00:00:00Z',
  ios: { version: '12.1.1', build: '446', size: 23767873, sha256: 'a'.repeat(64), downloadURL: download, bundleIdentifier: 'com.rayanmakhlouf.noopdev.noop', minOSVersion: '16.0' },
} }
const iphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 Version/27.0 Mobile/15E148 Safari/604.1'

test.beforeEach(async ({ page }) => {
  await page.route('https://firestore.googleapis.com/**', r => r.fulfill({ status: 503, body: '{}' }))
  await page.route('**/releases.json', r => r.fulfill({ json: catalogue }))
  // Never invoke an installed app during website regression tests.
  await page.addInitScript(() => document.addEventListener('click', e => {
    const link = e.target instanceof Element ? e.target.closest('a') : null
    if (link?.protocol === 'altstore-classic:') e.preventDefault()
  }, true))
})

test('the first-time path offers the published package for the selected computer', async ({ page }) => {
  test.skip(!INSTALLER_RELEASE, 'Native downloads remain disabled until a tested release is published.')
  await page.goto('/#installer')
  await page.getByRole('button', { name: 'Première installation', exact: true }).click()
  await expect(page.locator('#ouvrir-sur-telephone')).toHaveCount(0)
  await page.getByRole('link', { name: 'Ouvrir l’installation Nanashi', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`${route}$`))
  await page.getByRole('button', { name: 'Mac', exact: true }).click()
  await expect(page.getByRole('link', { name: 'Télécharger Nanashi pour Mac', exact: true })).toHaveAttribute('href', INSTALLER_RELEASE!.mac.url)
  await page.getByRole('button', { name: 'Windows', exact: true }).click()
  await expect(page.getByRole('link', { name: 'Télécharger Nanashi pour Windows', exact: true })).toHaveAttribute('href', INSTALLER_RELEASE!.windows.url)
  await expect(page.getByRole('link', { name: 'Télécharger Nanashi pour Mac', exact: true })).toHaveCount(0)
  await expect(page.getByText(/version de prévisualisation/)).toBeVisible()
})

test('returning to the computer stage keeps keyboard focus on its heading', async ({ page }) => {
  await page.goto(`${route}?step=iphone`)
  await expect(page.locator('#installation-etape')).toBeFocused()
  await page.getByRole('button', { name: 'Retour', exact: true }).click()
  await expect(page.locator('#installation-etape')).toHaveText('Un installateur, pour commencer')
  await expect(page.locator('#installation-etape')).toBeFocused()
})

test('desktop handoff retains a scannable phone link and never launches an iOS scheme', async ({ page }) => {
  await page.goto(`${route}?step=iphone#installation-etape`)
  await expect(page.locator('#installation-etape')).toHaveText('Autoriser AltStore')
  await expect(page.getByRole('navigation', { name: 'Terminer l’installation Nanashi' }).getByRole('button', { name: 'Autoriser AltStore', exact: true })).toHaveAttribute('aria-current', 'step')
  await expect(page.getByText('Étape 2 sur 5', { exact: true })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Ouvrez ce site sur votre iPhone pour continuer' })).toBeVisible()
  await expect(page.locator('img[src="/nanashi-iphone-qr.svg"]')).toBeVisible()
  await expect(page.getByRole('link', { name: 'Ouvrir cette étape sur l’iPhone', exact: true })).toHaveAttribute('href', 'https://nanashi-mk.vercel.app/installation-nanashi?step=iphone#installation-etape')
  await page.getByRole('navigation', { name: 'Terminer l’installation Nanashi' }).getByRole('button', { name: 'Installer Nanashi', exact: true }).click()
  await expect(page.locator('a[href^="altstore-classic:"]')).toHaveCount(0)
})

test('the five-stage guide remains reachable at 320px with large text and no credential fields', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 640 })
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto(route)
  await page.evaluate(() => { document.documentElement.style.fontSize = '150%' })
  const stages = [
    ['Ordinateur', 'Un installateur, pour commencer'],
    ['Autoriser', 'Autoriser AltStore'],
    ['Connexion', 'Activer la connexion locale'],
    ['Nanashi', 'Installer Nanashi'],
    ['Renouveler', 'Garder Nanashi disponible'],
  ]
  const navigation = page.getByRole('navigation', { name: 'Terminer l’installation Nanashi' })
  await expect(navigation.getByRole('button')).toHaveCount(5)
  for (const [, title] of stages) {
    const action = navigation.getByRole('button', { name: title, exact: true })
    await action.click()
    await expect(page.locator('#installation-etape')).toHaveText(title)
    await expect(action).toHaveAttribute('aria-current', 'step')
    const bounds = await action.boundingBox()
    expect(bounds?.width).toBeGreaterThanOrEqual(44)
    expect(bounds?.height).toBeGreaterThanOrEqual(44)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await expect(page.locator('input[type="password"], input[type="email"]')).toHaveCount(0)
    await expect(page.locator('a[href^="altstore-classic:"], a[href^="altstore:"], a[href^="sidestore:"], a[href^="shortcuts:"]')).toHaveCount(0)
  }
  await page.getByRole('button', { name: 'J’ai vérifié le renouvellement', exact: true }).click()
  await expect(page.getByRole('status')).toContainText('Vous avez confirmé la fin du parcours.')
})

test('blocked browser storage preserves in-page navigation without claiming saved progress', async ({ page }) => {
  await page.addInitScript(() => Object.defineProperty(window, 'localStorage', {
    configurable: true,
    get() { throw new DOMException('Blocked', 'SecurityError') },
  }))
  await page.goto(route)
  await expect(page.locator('#installation-etape')).toHaveText('Un installateur, pour commencer')
  for (let index = 0; index < 4; index++) await page.getByRole('button', { name: 'C’est fait, continuer', exact: true }).click()
  await expect(page.locator('#installation-etape')).toHaveText('Garder Nanashi disponible')
  await page.getByRole('button', { name: 'J’ai vérifié le renouvellement', exact: true }).click()
  await expect(page.getByRole('status')).toContainText('Vous avez confirmé')
  await page.reload()
  await expect(page.locator('#installation-etape')).toHaveText('Un installateur, pour commencer')
})

test.describe('iPhone handoff', () => {
  test.use({ userAgent: iphone })
  test('opens the verified IPA in Classic and asks for a real renewal check', async ({ page }) => {
    await page.goto(`${route}?step=nanashi`)
    const action = page.getByRole('link', { name: 'Installer Nanashi avec AltStore' })
    await expect(action).toHaveAttribute('href', `altstore-classic://install?url=${encodeURIComponent(download)}`)
    await action.click()
    await expect(page.getByRole('status')).toContainText('confirmez l’installation')
    await expect(page.locator('a[href^="sidestore:"]')).toHaveCount(0)
    await page.getByRole('button', { name: 'C’est fait, continuer' }).click()
    await expect(page.locator('#installation-etape')).toHaveText('Garder Nanashi disponible')
    await expect(page.getByText('Vous avez confirmé la fin du parcours.')).toHaveCount(0)
    await page.getByRole('button', { name: 'J’ai vérifié le renouvellement' }).click()
    await expect(page.getByRole('status')).toContainText('Vous avez confirmé')
  })

  test('returning from another app preserves the stage after the QR parameter is consumed', async ({ page }) => {
    await page.goto(`${route}?from=desktop&step=iphone#installation-etape`)
    await expect(page.locator('#installation-etape')).toHaveText('Autoriser AltStore')
    await expect(page.getByRole('navigation', { name: 'Terminer l’installation Nanashi' }).getByRole('button', { name: 'Autoriser AltStore', exact: true })).toHaveAttribute('aria-current', 'step')
    await page.getByRole('button', { name: 'C’est fait, continuer' }).click()
    await page.reload()
    await expect(page.locator('#installation-etape')).toHaveText('Activer la connexion locale')
    await expect(page).not.toHaveURL(/step=/)
    expect(new URL(page.url()).searchParams.get('from')).toBe('desktop')
    expect(new URL(page.url()).hash).toBe('#installation-etape')
    await expect(page.locator('img[src="/nanashi-iphone-qr.svg"]')).toHaveCount(0)
  })

  test('an unpublished app never becomes an install action', async ({ page }) => {
    await page.route('**/releases.json', r => r.fulfill({ json: { schemaVersion: 1, repository, latest: null } }))
    await page.goto(`${route}?step=nanashi`)
    await expect(page.getByText('Aucune version iPhone n’est publiée', { exact: false })).toBeVisible()
    await expect(page.locator('a[href^="altstore-classic:"]')).toHaveCount(0)
  })
})

test.describe('Android viewer', () => {
  test.use({ userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36' })
  test('retains the iPhone handoff instead of exposing an incompatible install protocol', async ({ page }) => {
    await page.goto(`${route}?step=nanashi`)
    await expect(page.locator('#installation-etape')).toHaveText('Installer Nanashi')
    await expect(page.locator('img[src="/nanashi-iphone-qr.svg"]')).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Ouvrez ce site sur votre iPhone pour continuer' })).toBeVisible()
    await expect(page.locator('a[href^="altstore-classic:"], a[href^="altstore:"], a[href^="sidestore:"], a[href^="shortcuts:"]')).toHaveCount(0)
    await expect(page.locator('input[type="password"], input[type="email"]')).toHaveCount(0)
  })
})
