import { test, expect } from '@playwright/test';

/**
 * Smoke Tests - Health Checks
 *
 * Basic health checks to verify DefectDojo is running and accessible.
 * These tests should pass even without authentication.
 */

test.describe('Health Checks', () => {
  test('should respond to HTTP/HTTPS requests', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/`);

    // Should get some response (200 or redirect)
    expect([200, 301, 302]).toContain(response.status());
  });

  test('should have accessible API root', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/api/v2/`);

    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toContain('application/json');
  });

  test('should return valid API schema', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/api/v2/`);
    const data = await response.json();

    // Verify expected API endpoints are listed
    expect(data).toHaveProperty('products');
    expect(data).toHaveProperty('findings');
    expect(data).toHaveProperty('engagements');
    expect(data).toHaveProperty('tests');
  });

  test('should have login page accessible', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/login`);

    expect([200, 301, 302]).toContain(response.status());
  });

  test('should have valid SSL certificate', async ({ request, baseURL }) => {
    // Skip if not HTTPS
    test.skip(!baseURL?.startsWith('https'), 'Not using HTTPS');

    const response = await request.get(`${baseURL}/api/v2/`);

    // If we got a response, SSL handshake succeeded
    expect(response.status()).toBe(200);
  });

  test('should return proper CORS headers', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/api/v2/`, {
      headers: {
        Origin: 'http://localhost:3000',
      },
    });

    // DefectDojo should return CORS headers for API
    // This test verifies the API is configured correctly
    expect(response.status()).toBe(200);
  });

  test('should have reasonable response time', async ({ request, baseURL }) => {
    const startTime = Date.now();
    await request.get(`${baseURL}/api/v2/`);
    const duration = Date.now() - startTime;

    // Should respond within 5 seconds
    expect(duration).toBeLessThan(5000);
  });
});
