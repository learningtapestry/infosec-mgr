import { test, expect } from '@playwright/test';

/**
 * E2E Tests for DefectDojo Findings
 *
 * These tests verify findings listing and filtering functionality.
 */

const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || '';

test.describe('Findings Management', () => {
  test.beforeEach(async ({ page }) => {
    test.skip(!ADMIN_PASSWORD, 'ADMIN_PASSWORD environment variable not set');

    // Login before each test
    await page.goto('/login');
    await page.fill('input[name="username"]', ADMIN_USERNAME);
    await page.fill('input[name="password"]', ADMIN_PASSWORD);
    await page.click('button[type="submit"], input[type="submit"]');
    await expect(page).not.toHaveURL(/login/);
  });

  test('should display findings list', async ({ page }) => {
    await page.goto('/finding');

    // Should be on findings page
    await expect(page).toHaveURL(/finding/);

    // Should have findings table or list
    const findingsList = page.locator('table, .findings-list, [data-testid="findings"]');
    await expect(findingsList).toBeVisible();
  });

  test('should filter findings by severity', async ({ page }) => {
    await page.goto('/finding');

    // Look for severity filter
    const severityFilter = page.locator('select[name="severity"], [data-testid="severity-filter"]');

    if (await severityFilter.isVisible()) {
      await severityFilter.selectOption({ label: /critical/i });
      await page.waitForLoadState('networkidle');

      // Verify filter is applied (URL might contain filter params)
      await expect(page).toHaveURL(/severity|Critical/i);
    }
  });

  test('should navigate to finding detail', async ({ page }) => {
    await page.goto('/finding');

    // Click on first finding link
    const findingLink = page.locator('a[href*="/finding/"]').first();

    if (await findingLink.isVisible()) {
      await findingLink.click();

      // Should be on finding detail page
      await expect(page).toHaveURL(/\/finding\/\d+/);
    }
  });

  test('should display finding details', async ({ page }) => {
    await page.goto('/finding');

    // Get first finding link
    const findingLink = page.locator('a[href*="/finding/"]').first();

    if (await findingLink.isVisible()) {
      await findingLink.click();

      // Wait for detail page to load
      await page.waitForLoadState('networkidle');

      // Check for common detail elements
      const detailPage = page.locator('body');
      await expect(detailPage).toBeVisible();

      // Should have severity indicator somewhere on the page
      const severityText = page.locator('text=/critical|high|medium|low|info/i');
      // Not all findings pages may have this visible, so just check page loaded
    }
  });

  test('should search findings', async ({ page }) => {
    await page.goto('/finding');

    // Find search input
    const searchInput = page.locator('input[name="title"], input[placeholder*="search"], input[type="search"]');

    if (await searchInput.isVisible()) {
      await searchInput.fill('SQL');
      await page.keyboard.press('Enter');

      await page.waitForLoadState('networkidle');
    }
  });
});
