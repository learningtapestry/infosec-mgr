import { test, expect } from '@playwright/test';

/**
 * E2E Tests for DefectDojo Login Flow
 *
 * These tests verify the login functionality works correctly.
 * Requires ADMIN_USERNAME and ADMIN_PASSWORD environment variables.
 */

const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || '';

test.describe('Login Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Clear any existing session
    await page.context().clearCookies();
  });

  test('should display login page', async ({ page }) => {
    await page.goto('/login');

    // Check login form elements are present
    await expect(page.locator('input[name="username"]')).toBeVisible();
    await expect(page.locator('input[name="password"]')).toBeVisible();
    await expect(page.locator('button[type="submit"], input[type="submit"]')).toBeVisible();
  });

  test('should reject invalid credentials', async ({ page }) => {
    await page.goto('/login');

    await page.fill('input[name="username"]', 'invalid_user');
    await page.fill('input[name="password"]', 'invalid_password');
    await page.click('button[type="submit"], input[type="submit"]');

    // Should show error or stay on login page
    await expect(page).toHaveURL(/login/);
  });

  test('should login with valid credentials', async ({ page }) => {
    test.skip(!ADMIN_PASSWORD, 'ADMIN_PASSWORD environment variable not set');

    await page.goto('/login');

    await page.fill('input[name="username"]', ADMIN_USERNAME);
    await page.fill('input[name="password"]', ADMIN_PASSWORD);
    await page.click('button[type="submit"], input[type="submit"]');

    // Should redirect away from login page
    await expect(page).not.toHaveURL(/login/);

    // Should have session cookie
    const cookies = await page.context().cookies();
    const sessionCookie = cookies.find(c => c.name.includes('session') || c.name.includes('csrf'));
    expect(sessionCookie).toBeDefined();
  });

  test('should maintain session after login', async ({ page }) => {
    test.skip(!ADMIN_PASSWORD, 'ADMIN_PASSWORD environment variable not set');

    // Login
    await page.goto('/login');
    await page.fill('input[name="username"]', ADMIN_USERNAME);
    await page.fill('input[name="password"]', ADMIN_PASSWORD);
    await page.click('button[type="submit"], input[type="submit"]');

    // Navigate to a protected page
    await page.goto('/product');

    // Should not be redirected to login
    await expect(page).not.toHaveURL(/login/);
  });

  test('should be able to logout', async ({ page }) => {
    test.skip(!ADMIN_PASSWORD, 'ADMIN_PASSWORD environment variable not set');

    // Login first
    await page.goto('/login');
    await page.fill('input[name="username"]', ADMIN_USERNAME);
    await page.fill('input[name="password"]', ADMIN_PASSWORD);
    await page.click('button[type="submit"], input[type="submit"]');

    // Wait for redirect
    await expect(page).not.toHaveURL(/login/);

    // Find and click logout
    await page.click('text=Logout');

    // Should be redirected to login
    await expect(page).toHaveURL(/login/);
  });
});
