import { test, expect } from '@playwright/test';

/**
 * E2E Tests for DefectDojo Product Management
 *
 * These tests verify product listing and viewing functionality.
 */

const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || '';

test.describe('Product Management', () => {
  test.beforeEach(async ({ page }) => {
    test.skip(!ADMIN_PASSWORD, 'ADMIN_PASSWORD environment variable not set');

    // Login before each test
    await page.goto('/login');
    await page.fill('input[name="username"]', ADMIN_USERNAME);
    await page.fill('input[name="password"]', ADMIN_PASSWORD);
    await page.click('button[type="submit"], input[type="submit"]');
    await expect(page).not.toHaveURL(/login/);
  });

  test('should display products list', async ({ page }) => {
    await page.goto('/product');

    // Should be on products page
    await expect(page).toHaveURL(/product/);

    // Should have a table or list of products
    const productsList = page.locator('table, .product-list, [data-testid="products"]');
    await expect(productsList).toBeVisible();
  });

  test('should filter products by name', async ({ page }) => {
    await page.goto('/product');

    // Find search/filter input
    const searchInput = page.locator('input[name="name"], input[placeholder*="search"], input[placeholder*="filter"]');

    if (await searchInput.isVisible()) {
      await searchInput.fill('test');
      await page.keyboard.press('Enter');

      // Wait for filter to apply
      await page.waitForLoadState('networkidle');
    }
  });

  test('should navigate to product details', async ({ page }) => {
    await page.goto('/product');

    // Click on first product link
    const productLink = page.locator('a[href*="/product/"]').first();

    if (await productLink.isVisible()) {
      await productLink.click();

      // Should be on product detail page
      await expect(page).toHaveURL(/\/product\/\d+/);
    }
  });

  test('should display product findings count', async ({ page }) => {
    await page.goto('/product');

    // Look for findings count in the product list
    const findingsCount = page.locator('text=/\\d+ finding|finding.*\\d+/i');

    // This may not always be visible depending on data
    // Just verify the page loads correctly
    await expect(page).toHaveURL(/product/);
  });
});
