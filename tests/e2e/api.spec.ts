import { test, expect } from '@playwright/test';

/**
 * E2E Tests for DefectDojo API
 *
 * These tests verify the API endpoints are accessible and working.
 * Requires DEFECTDOJO_TOKEN environment variable for authenticated tests.
 */

const API_TOKEN = process.env.DEFECTDOJO_TOKEN || '';

test.describe('API Endpoints', () => {
  test('should return API root', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/api/v2/`);

    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toHaveProperty('products');
    expect(data).toHaveProperty('engagements');
    expect(data).toHaveProperty('findings');
  });

  test('should obtain API token with credentials', async ({ request, baseURL }) => {
    const username = process.env.ADMIN_USERNAME || 'admin';
    const password = process.env.ADMIN_PASSWORD || '';

    test.skip(!password, 'ADMIN_PASSWORD environment variable not set');

    const response = await request.post(`${baseURL}/api/v2/api-token-auth/`, {
      data: {
        username,
        password,
      },
    });

    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toHaveProperty('token');
    expect(data.token).toBeTruthy();
  });

  test('should reject unauthenticated requests to protected endpoints', async ({ request, baseURL }) => {
    const response = await request.get(`${baseURL}/api/v2/products/`);

    expect(response.status()).toBe(401);
  });

  test('should access products with valid token', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/products/`, {
      headers: {
        Authorization: `Token ${API_TOKEN}`,
      },
    });

    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toHaveProperty('results');
    expect(Array.isArray(data.results)).toBe(true);
  });

  test('should access findings with valid token', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/findings/`, {
      headers: {
        Authorization: `Token ${API_TOKEN}`,
      },
    });

    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toHaveProperty('results');
    expect(data).toHaveProperty('count');
  });

  test('should access product types with valid token', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/product_types/`, {
      headers: {
        Authorization: `Token ${API_TOKEN}`,
      },
    });

    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toHaveProperty('results');
    expect(Array.isArray(data.results)).toBe(true);
  });

  test('should access users endpoint with valid token', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/users/`, {
      headers: {
        Authorization: `Token ${API_TOKEN}`,
      },
    });

    expect(response.status()).toBe(200);
    const data = await response.json();
    expect(data).toHaveProperty('results');
  });
});
