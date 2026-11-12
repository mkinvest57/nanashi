import { test, expect } from '@playwright/test'

const repository = 'https://github.com/mkinvest57/nanashi'
const artifact = { version: '12.1.0', build: 446, size: 12345678, sha256: 'a'.repeat(64), downloadURL: `${repository}/releases/download/nanashi-446/Nanashi.ipa` }
const catalogue = { schemaVersion: 1, repository, updatedAt: '2026-11-12T00:00:00Z', latest: {
  version: '12.1.0', releaseURL: `${repository}/releases/tag/nanashi-446`, publishedAt: '2026-11-12T00:00:00Z',
  ios: { ...artifact, bundleIdentifier: 'com.rayanmakhlouf.noopdev.noop', minOSVersion: '16.0' },
  android: { ...artifact, applicationId: 'com.rayanmakhlouf.nanashi', minSDK: 26, downloadURL: `${repository}/releases/download/nanashi-446/Nanashi.apk` },
}, sideStore: { sourceURL: 'https://nanashi.example/altstore-source.json' } }

test('public empty state has no misleading download and the page fits the viewport', async ({ page }, testInfo) => {
  await page.route('**/releases.json', route => route.fulfill({ json: { schemaVersion: 1, repository, latest: null } }))
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Votre rythme. Vos règles.' })).toBeVisible()
  await page.getByRole('link', { name: 'Installer Nanashi', exact: true }).click()
  await expect(page.getByText('Publication en préparation')).toBeVisible()
  await expect(page.getByRole('link', { name: /Télécharger l’/ })).toHaveCount(0)
  await page.getByRole('tab', { name: 'Android', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Nanashi pour Android' })).toBeVisible()
  await page.getByText('Quels bracelets puis-je connecter ?').click()
  await expect(page.getByText(/WHOOP 4.0 et 5.0\/MG/)).toBeVisible()
  await page.getByRole('link', { name: 'Confidentialité', exact: true }).click()
  await expect(page.getByText(/Ce site lit un catalogue public de versions/)).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: `test-results/${testInfo.project.name}-full.png`, fullPage: true })
})

test('published files and SideStore source are actionable and verifiable', async ({ page }) => {
  await page.route('**/releases.json', route => route.fulfill({ json: catalogue }))
  await page.goto('/#installer')
  const source = page.getByRole('link', { name: 'Ajouter à SideStore' })
  await expect(source).toHaveAttribute('href', 'sidestore://source?url=https%3A%2F%2Fnanashi.example%2Faltstore-source.json')
  await expect(page.getByRole('link', { name: 'Télécharger l’IPA' })).toHaveAttribute('href', artifact.downloadURL)
  await page.getByText('Vérifier ce téléchargement').click()
  await expect(page.getByText(artifact.sha256)).toBeVisible()
  await page.getByRole('tab', { name: 'iPhone', exact: true }).focus()
  await page.keyboard.press('ArrowRight')
  await expect(page.getByRole('tab', { name: 'Android', exact: true })).toBeFocused()
  await expect(page.getByRole('tab', { name: 'Android', exact: true })).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('link', { name: 'Télécharger l’APK' })).toHaveAttribute('href', catalogue.latest.android.downloadURL)
  await expect(source).toHaveCount(0)
})

test('failed catalogue can be retried without reloading the page', async ({ page }) => {
  let fail = true
  await page.route('**/releases.json', route => route.fulfill(fail ? { status: 503, body: '{}' } : { json: catalogue }))
  await page.goto('/#installer')
  await expect(page.getByText('Le catalogue est momentanément inaccessible.')).toBeVisible()
  fail = false
  await page.getByRole('button', { name: 'Réessayer' }).click()
  await expect(page.getByRole('link', { name: 'Télécharger l’IPA' })).toBeVisible()
})

test('small text-scaled viewport keeps installation and footer reachable', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 600 })
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await page.goto('/')
  await page.evaluate(() => { document.documentElement.style.fontSize = '150%' })
  await page.getByRole('tab', { name: 'Android', exact: true }).click()
  await page.getByRole('link', { name: 'Le code sur GitHub' }).scrollIntoViewIfNeeded()
  await expect(page.getByRole('link', { name: 'Le code sur GitHub' })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
})
