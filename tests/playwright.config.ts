import { defineConfig, devices } from '@playwright/test';

/**
 * DefectDojo E2E and Smoke Test Configuration
 *
 * Environment variables:
 * - BASE_URL: DefectDojo URL (default: http://localhost:8080)
 * - DEFECTDOJO_TOKEN: API token for authenticated requests
 * - ADMIN_USERNAME: Admin username (default: admin)
 * - ADMIN_PASSWORD: Admin password
 */

const baseURL = process.env.BASE_URL || 'http://localhost:8080';

export default defineConfig({
  testDir: '.',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { outputFolder: 'test-results/html' }],
    ['json', { outputFile: 'test-results/results.json' }],
    ['list']
  ],
  use: {
    baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    // E2E tests - full browser testing
    {
      name: 'e2e',
      testDir: './e2e',
      use: {
        ...devices['Desktop Chrome'],
      },
    },

    // Smoke tests - API and health checks
    {
      name: 'smoke',
      testDir: './smoke',
      use: {
        ...devices['Desktop Chrome'],
      },
    },
  ],

  // Global timeout
  timeout: 60000,
  expect: {
    timeout: 10000,
  },

  // Output folder for test artifacts
  outputDir: 'test-results/artifacts',
});
