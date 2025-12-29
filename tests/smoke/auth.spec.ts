import { test, expect } from '@playwright/test';

/**
 * Smoke Tests - Authentication
 *
 * Verify authentication is working in production.
 * Requires DEFECTDOJO_TOKEN environment variable.
 */

const API_TOKEN = process.env.DEFECTDOJO_TOKEN || '';

test.describe('Authentication Smoke Tests', () => {
  test('should reject requests without token', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/api/v2/products/`);

    expect(response.status()).toBe(401);
  });

  test('should reject requests with invalid token', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/api/v2/products/`, {
      headers: {
        Authorization: 'Token invalid_token_12345',
      },
    });

    expect(response.status()).toBe(401);
  });

  test('should accept valid API token', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/products/`, {
      headers: {
        Authorization: `Token ${API_TOKEN}`,
      },
    });

    expect(response.status()).toBe(200);
  });

  test('should return user info with valid token', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/users/`, {
      headers: {
        Authorization: `Token ${API_TOKEN}`,
      },
    });

    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toHaveProperty('results');
    expect(data.results.length).toBeGreaterThan(0);
  });

  test('should access engagements with valid token', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/engagements/`, {
      headers: {
        Authorization: `Token ${API_TOKEN}`,
      },
    });

    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toHaveProperty('results');
  });

  test('should access tests endpoint with valid token', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/tests/`, {
      headers: {
        Authorization: `Token ${API_TOKEN}`,
      },
    });

    expect(response.status()).toBe(200);
  });
});
