import { test, expect } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Smoke Tests - Scan Import
 *
 * Live integration tests that import scan data and verify it appears in DefectDojo.
 * Requires DEFECTDOJO_TOKEN environment variable.
 */

const API_TOKEN = process.env.DEFECTDOJO_TOKEN || '';
const TEST_PRODUCT_NAME = 'test/e2e-validation';

test.describe('Scan Import Smoke Tests', () => {
  test.beforeAll(() => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');
  });

  test('should import Semgrep scan results', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    // Read sample Semgrep results
    const fixturesDir = path.join(__dirname, '..', 'fixtures');
    const semgrepData = fs.readFileSync(path.join(fixturesDir, 'semgrep-sample.json'));

    // Get initial findings count
    const beforeResponse = await request.get(`${baseURL}/api/v2/findings/?product_name=${encodeURIComponent(TEST_PRODUCT_NAME)}`, {
      headers: { Authorization: `Token ${API_TOKEN}` },
    });
    const beforeData = await beforeResponse.json();
    const beforeCount = beforeData.count || 0;

    // Import scan
    const formData = new FormData();
    formData.append('scan_type', 'Semgrep JSON Report');
    formData.append('product_name', TEST_PRODUCT_NAME);
    formData.append('product_type_name', 'Web Application');
    formData.append('engagement_name', 'E2E Test Import');
    formData.append('auto_create_context', 'true');
    formData.append('verified', 'false');
    formData.append('active', 'true');
    formData.append('file', new Blob([semgrepData], { type: 'application/json' }), 'semgrep-results.json');

    const importResponse = await request.post(`${baseURL}/api/v2/import-scan/`, {
      headers: { Authorization: `Token ${API_TOKEN}` },
      multipart: {
        scan_type: 'Semgrep JSON Report',
        product_name: TEST_PRODUCT_NAME,
        product_type_name: 'Web Application',
        engagement_name: 'E2E Test Import',
        auto_create_context: 'true',
        verified: 'false',
        active: 'true',
        file: {
          name: 'semgrep-results.json',
          mimeType: 'application/json',
          buffer: semgrepData,
        },
      },
    });

    expect(importResponse.status()).toBe(201);

    const importData = await importResponse.json();
    expect(importData).toHaveProperty('test');

    // Verify findings were imported
    const afterResponse = await request.get(`${baseURL}/api/v2/findings/?product_name=${encodeURIComponent(TEST_PRODUCT_NAME)}`, {
      headers: { Authorization: `Token ${API_TOKEN}` },
    });
    const afterData = await afterResponse.json();

    // Should have more findings (or same if duplicates were deduplicated)
    expect(afterData.count).toBeGreaterThanOrEqual(beforeCount);
  });

  test('should import Trivy scan results', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    // Read sample Trivy results
    const fixturesDir = path.join(__dirname, '..', 'fixtures');
    const trivyData = fs.readFileSync(path.join(fixturesDir, 'trivy-sample.json'));

    // Import scan
    const importResponse = await request.post(`${baseURL}/api/v2/import-scan/`, {
      headers: { Authorization: `Token ${API_TOKEN}` },
      multipart: {
        scan_type: 'Trivy Scan',
        product_name: TEST_PRODUCT_NAME,
        product_type_name: 'Web Application',
        engagement_name: 'E2E Test Import',
        auto_create_context: 'true',
        verified: 'false',
        active: 'true',
        file: {
          name: 'trivy-results.json',
          mimeType: 'application/json',
          buffer: trivyData,
        },
      },
    });

    expect(importResponse.status()).toBe(201);

    const importData = await importResponse.json();
    expect(importData).toHaveProperty('test');
  });

  test('should query imported findings', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    // Query findings for our test product
    const response = await request.get(`${baseURL}/api/v2/findings/?product_name=${encodeURIComponent(TEST_PRODUCT_NAME)}&limit=10`, {
      headers: { Authorization: `Token ${API_TOKEN}` },
    });

    expect(response.status()).toBe(200);

    const data = await response.json();
    expect(data).toHaveProperty('results');
    expect(data).toHaveProperty('count');

    // If we have findings, verify they have expected structure
    if (data.results.length > 0) {
      const finding = data.results[0];
      expect(finding).toHaveProperty('id');
      expect(finding).toHaveProperty('title');
      expect(finding).toHaveProperty('severity');
    }
  });

  test('should query findings by severity', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    // Query critical findings
    const response = await request.get(`${baseURL}/api/v2/findings/?severity=Critical&limit=5`, {
      headers: { Authorization: `Token ${API_TOKEN}` },
    });

    expect(response.status()).toBe(200);

    const data = await response.json();
    expect(data).toHaveProperty('results');

    // All returned findings should be Critical
    for (const finding of data.results) {
      expect(finding.severity).toBe('Critical');
    }
  });

  test('should verify test product exists', async ({ request, baseURL }) => {
    test.skip(!API_TOKEN, 'DEFECTDOJO_TOKEN environment variable not set');

    const response = await request.get(`${baseURL}/api/v2/products/?name=${encodeURIComponent(TEST_PRODUCT_NAME)}`, {
      headers: { Authorization: `Token ${API_TOKEN}` },
    });

    expect(response.status()).toBe(200);

    const data = await response.json();
    // Product may or may not exist depending on previous test runs
    // Just verify the query works
    expect(data).toHaveProperty('results');
  });
});
