import { test, expect } from '@playwright/test'
import { INSTALLER_RELEASE } from '../src/lib/installerRelease'

const repository = 'https://github.com/mkinvest57/nanashi'
const artifact = { version: '12.1.1', build: 446, size: 23767873, sha256: 'a'.repeat(64), downloadURL: `${repository}/releases/download/v12.1.1/Nanashi.ipa` }
const catalogue = { schemaVersion: 1, repository, updatedAt: '2026-11-12T00:00:00Z', latest: {
  version: '12.1.1', releaseURL: `${repository}/releases/tag/v12.1.1`, publishedAt: '2026-11-12T00:00:00Z',
  ios: { ...artifact, bundleIdentifier: 'com.rayanmakhlouf.noopdev.noop', minOSVersion: '16.0' },
  android: { ...artifact, build: 559, applicationId: 'com.rayanmakhlouf.nanashi', minSDK: 26, downloadURL: `${repository}/releases/download/v12.1.1/Nanashi.apk` },
}, sideStore: { sourceURL: 'https://nanashi.example/altstore-source.json' } }
const iosUserAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Version/26.0 Mobile/15E148 Safari/604.1'
const androidUserAgent = 'Mozilla/5.0 (Linux; Android 16; Pixel 10) AppleWebKit/537.36 Chrome/140.0.0.0 Mobile Safari/537.36'

test.beforeEach(async ({ page }) => {
  // Isolate release states from the real optional mirror. Never launch a native installer in tests.
  await page.route('https://firestore.googleapis.com/**', route => route.fulfill({ status: 503, body: '{}' }))
  await page.addInitScript(() => {
    document.addEventListener('click', event => {
      const target = event.target instanceof Element ? event.target.closest('a') : null
      if (target && ['sidestore:', 'altstore-classic:'].includes(target.protocol)) event.preventDefault()
    }, true)
  })
})

test('unpublished versions never offer an install or a download', async ({ page }) => {
  await page.route('**/releases.json', route => route.fulfill({ json: { schemaVersion: 1, repository, latest: null } }))
  await page.goto('/#installer')
  await expect(page.getByText('Publication en préparation')).toBeVisible()
  await expect(page.locator('#installer a.install-primary')).toHaveCount(0)
  await expect(page.locator('a[href^="sidestore:"]')).toHaveCount(0)
  await page.getByRole('tab', { name: 'Android', exact: true }).click()
  await expect(page.getByRole('link', { name: 'Télécharger Nanashi', exact: true })).toHaveCount(0)
})

test('computer hands off to the phone instead of launching an iOS protocol', async ({ page }) => {
  await page.route('**/releases.json', route => route.fulfill({ json: catalogue }))
  await page.goto('/#installer')
  await expect(page.getByRole('link', { name: 'Continuer sur mon téléphone' })).toHaveAttribute('href', '#ouvrir-sur-telephone')
  await expect(page.getByRole('img', { name: 'Ouvrir cette page sur votre téléphone' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Copier le lien pour mon téléphone' })).toBeVisible()
  await page.getByText('Autres options et aide', { exact: true }).click()
  await expect(page.locator('a[href^="sidestore:"]')).toHaveCount(0)
})

test('platform tabs stay keyboard accessible and technical options are tucked away', async ({ page }) => {
  await page.route('**/releases.json', route => route.fulfill({ json: catalogue }))
  await page.goto('/#installer')
  await expect(page.getByRole('link', { name: 'Télécharger le fichier IPA' })).not.toBeVisible()
  await page.getByRole('tab', { name: 'iPhone', exact: true }).focus()
  await page.keyboard.press('ArrowRight')
  await expect(page.getByRole('tab', { name: 'Android', exact: true })).toBeFocused()
  await expect(page.getByRole('tab', { name: 'Android', exact: true })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('link', { name: 'Télécharger Nanashi', exact: true })).toHaveAttribute('href', catalogue.latest.android.downloadURL)
  await expect(page.getByText('Android 8 ou version ultérieure', { exact: true })).toBeVisible()
  await page.getByText('Autres options et aide', { exact: true }).click()
  await page.getByText('Vérifier ce téléchargement', { exact: true }).click()
  await expect(page.getByText(artifact.sha256, { exact: true })).toBeVisible()
})

test('failed catalogue can be retried without reloading', async ({ page }) => {
  let fail = true
  await page.route('**/releases.json', route => route.fulfill(fail ? { status: 503, body: '{}' } : { json: catalogue }))
  await page.goto('/#installer')
  await expect(page.getByText('Le catalogue est momentanément inaccessible.')).toBeVisible()
  await expect(page.locator('#installer a.install-primary')).toHaveCount(0)
  fail = false
  await page.getByRole('button', { name: 'Réessayer' }).click()
  await expect(page.locator('#installer a.install-primary')).toBeVisible()
})

test('small text-scaled viewport keeps installation and footer reachable', async ({ page }) => {
  await page.route('**/releases.json', route => route.fulfill({ json: catalogue }))
  await page.setViewportSize({ width: 320, height: 600 })
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/#installer')
  await page.evaluate(() => { document.documentElement.style.fontSize = '150%' })
  await page.getByRole('tab', { name: 'Android', exact: true }).click()
  await page.getByText('Autres options et aide', { exact: true }).click()
  await page.getByText('Vérifier ce téléchargement', { exact: true }).click()
  await page.getByRole('link', { name: 'Le code sur GitHub' }).scrollIntoViewIfNeeded()
  await expect(page.getByRole('link', { name: 'Le code sur GitHub' })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
})

test.describe('on an iPhone', () => {
  test.use({ userAgent: iosUserAgent })

  test('AltStore selection uses Classic for both installation and the source', async ({ page }) => {
    await page.route('**/releases.json', route => route.fulfill({ json: catalogue }))
    await page.goto('/#installer')
    await page.getByRole('button', { name: 'J’ai déjà AltStore', exact: true }).click()
    const action = page.getByRole('link', { name: 'Installer / mettre à jour Nanashi' })
    await expect(action).toHaveAttribute('href', `altstore-classic://install?url=${encodeURIComponent(artifact.downloadURL)}`)
    await action.click()
    await expect(page.getByRole('status').filter({ hasText: 'Dans AltStore' })).toBeVisible()
    await page.getByText('Autres options et aide', { exact: true }).click()
    await expect(page.getByRole('link', { name: 'Ajouter la source à AltStore' })).toHaveAttribute('href', `altstore-classic://source?url=${encodeURIComponent(catalogue.sideStore.sourceURL)}`)
    await expect(page.locator('a[href^="sidestore:"]')).toHaveCount(0)
    await page.getByRole('button', { name: 'J’ai déjà SideStore', exact: true }).click()
    await expect(action).toHaveAttribute('href', `sidestore://install?url=${encodeURIComponent(artifact.downloadURL)}`)
    await expect(page.locator('a[href^="altstore-classic:"]')).toHaveCount(0)
  })

  test('existing SideStore needs one direct action, without adding a source first', async ({ page }) => {
    await page.route('**/releases.json', route => route.fulfill({ json: { ...catalogue, sideStore: undefined } }))
    await page.goto('/#installer')
    await expect(page.getByRole('tab', { name: 'iPhone', exact: true })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByRole('button', { name: 'J’ai déjà SideStore' })).toHaveAttribute('aria-pressed', 'true')
    await expect(page.getByRole('img', { name: 'Ouvrir cette page sur votre téléphone' })).toHaveCount(0)
    const action = page.getByRole('link', { name: 'Installer / mettre à jour Nanashi', exact: true })
    await expect(action).toHaveAttribute('href', `sidestore://install?url=${encodeURIComponent(artifact.downloadURL)}`)
    await expect(page.locator('#installer .install-primary:visible')).toHaveCount(1)
    await action.click()
    await expect(page.getByRole('status').filter({ hasText: 'Dans SideStore' })).toBeVisible()
    await expect(page.getByText(/Keep App Extensions \(Register App ID for Each Extension\)/)).toBeVisible()
    await page.getByRole('button', { name: 'SideStore ne s’ouvre pas ?' }).click()
    await expect(page.getByText(/ouvrez cette page dans Safari/)).toBeVisible()
    await expect(page.getByText(/installation réussie|Nanashi est installée/i)).toHaveCount(0)
    await expect(page).toHaveURL(/#installer$/)
  })

  test('first setup stays on Nanashi and lets the user return to the short path', async ({ page }) => {
    await page.route('**/releases.json', route => route.fulfill({ json: catalogue }))
    await page.goto('/#installer')
    await page.getByRole('button', { name: 'Première installation', exact: true }).click()
    const setupLabel = INSTALLER_RELEASE ? 'Ouvrir l’installation Nanashi' : 'Configurer SideStore pas à pas'
    await expect(page.getByRole('link', { name: setupLabel })).toHaveAttribute('href', INSTALLER_RELEASE ? '/installation-nanashi' : '/installation-sidestore')
    if (INSTALLER_RELEASE) await expect(page.getByRole('link', { name: 'Conserver le parcours SideStore existant' })).toHaveAttribute('href', '/installation-sidestore')
    const action = page.getByRole('link', { name: 'Installer / mettre à jour Nanashi', exact: true })
    await expect(action).not.toBeVisible()
    await page.getByRole('button', { name: 'J’ai déjà SideStore' }).click()
    await expect(action).toBeVisible()
    await expect(page.getByRole('link', { name: setupLabel })).toHaveCount(0)
    await expect(page.locator('a[href*="docs.sidestore.io"]')).toHaveCount(0)
  })
})

test.describe('on Android', () => {
  test.use({ userAgent: androidUserAgent })

  test('automatically offers the Android file and never an iOS protocol', async ({ page }) => {
    await page.route('**/releases.json', route => route.fulfill({ json: catalogue }))
    await page.goto('/#installer')
    await expect(page.getByRole('tab', { name: 'Android', exact: true })).toHaveAttribute('aria-selected', 'true')
    await expect(page.getByRole('link', { name: 'Télécharger Nanashi', exact: true })).toHaveAttribute('href', catalogue.latest.android.downloadURL)
    await expect(page.getByRole('img', { name: 'Ouvrir cette page sur votre téléphone' })).toHaveCount(0)
    await page.getByRole('tab', { name: 'iPhone', exact: true }).click()
    await page.getByText('Autres options et aide', { exact: true }).click()
    await expect(page.locator('a[href^="sidestore:"]')).toHaveCount(0)
    await expect(page.locator('a[href="#ouvrir-sur-telephone"]')).toHaveCount(0)
  })
})
