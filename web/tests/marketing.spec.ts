import { expect, test } from '@playwright/test'

test('feature explorer follows keyboard focus and keeps demonstrations explicit', async ({ page }) => {
  await page.goto('/#experience')
  const tabs = page.getByRole('tablist', { name: 'Explorer les fonctions de Nanashi' })
  const first = tabs.getByRole('tab').first()
  await first.focus()
  await page.keyboard.press('ArrowDown')
  await expect(tabs.getByRole('tab').nth(1)).toBeFocused()
  await expect(tabs.getByRole('tab').nth(1)).toHaveAttribute('aria-selected', 'true')
  await expect(page.getByRole('tabpanel', { name: /Sommeil & historique/ })).toBeVisible()
  await expect(page.getByRole('img', { name: /Écran Sommeil.*démonstration/ })).toBeVisible()
  await page.keyboard.press('End')
  await expect(page.getByRole('tabpanel', { name: /Coach personnel/ })).toContainText('clé API personnelle')
  await page.keyboard.press('Home')
  await expect(first).toHaveAttribute('aria-selected', 'true')
})

test('compatibility and privacy links reveal their actual explanatory content', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Sans abonnement WHOOP.')
  await page.getByRole('link', { name: 'Voir les formats et limites' }).click()
  await expect(page.locator('#compatibility-details')).toHaveAttribute('open', '')
  await expect(page.locator('#compatibility-details')).toContainText('cela ne signifie pas que tous les bracelets Xiaomi')
  await page.getByRole('link', { name: 'Comprendre la confidentialité' }).click()
  await expect(page.locator('#confidentialite')).toHaveAttribute('open', '')
  await expect(page.locator('#confidentialite')).toContainText('ne reçoit pas vos mesures de santé')
})
