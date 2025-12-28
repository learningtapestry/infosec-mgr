#!/bin/bash
# Import a security scan into DefectDojo
# Usage: ./import-scan.sh <product-name> <scan-type> <scan-file>
#
# Example:
#   ./import-scan.sh "My Web App" "Trivy Scan" ./trivy-results.json
#   ./import-scan.sh "My API" "SARIF" ./codeql-results.sarif
#
# Common scan types:
#   - "Trivy Scan" (container/filesystem scanning)
#   - "SARIF" (GitHub CodeQL, Semgrep, etc.)
#   - "Dependency Check Scan" (OWASP Dependency Check)
#   - "npm Audit Scan" (npm audit)
#   - "Snyk Scan" (Snyk)
#   - "Bandit Scan" (Python)
#   - "Brakeman Scan" (Ruby on Rails)
#   - "ESLint Scan" (JavaScript)
#   - "ZAP Scan" (OWASP ZAP)
#   - "Nessus Scan" (Tenable)
#
# See full list: curl -s -H "Authorization: Token $API_TOKEN" \
#   http://localhost:8080/api/v2/test-types/?limit=300 | jq '.results[].name'

set -e

DOJO_URL="${DOJO_URL:-http://localhost:8080}"
API_TOKEN="${DOJO_API_TOKEN:-}"

if [ -z "$API_TOKEN" ]; then
    echo "Error: DOJO_API_TOKEN environment variable not set"
    echo "Get your token from: ${DOJO_URL}/api/key-v2"
    exit 1
fi

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <product-name> <scan-type> <scan-file>"
    echo ""
    echo "Example:"
    echo "  $0 'My Web App' 'Trivy Scan' ./trivy-results.json"
    exit 1
fi

PRODUCT_NAME="$1"
SCAN_TYPE="$2"
SCAN_FILE="$3"

if [ ! -f "$SCAN_FILE" ]; then
    echo "Error: Scan file not found: $SCAN_FILE"
    exit 1
fi

echo "Importing scan..."
echo "  Product: $PRODUCT_NAME"
echo "  Type: $SCAN_TYPE"
echo "  File: $SCAN_FILE"

RESPONSE=$(curl -s -X POST \
    -H "Authorization: Token ${API_TOKEN}" \
    -F "scan_type=${SCAN_TYPE}" \
    -F "product_name=${PRODUCT_NAME}" \
    -F "engagement_name=CI/CD Scan" \
    -F "auto_create_context=true" \
    -F "file=@${SCAN_FILE}" \
    "${DOJO_URL}/api/v2/import-scan/")

# Check for errors
if echo "$RESPONSE" | jq -e '.test' > /dev/null 2>&1; then
    TEST_ID=$(echo "$RESPONSE" | jq -r '.test')
    FINDINGS_COUNT=$(echo "$RESPONSE" | jq -r '.findings_affected // 0')
    echo ""
    echo "Success!"
    echo "  Test ID: $TEST_ID"
    echo "  Findings: $FINDINGS_COUNT"
    echo "  View at: ${DOJO_URL}/test/${TEST_ID}"
else
    echo ""
    echo "Error importing scan:"
    echo "$RESPONSE" | jq .
    exit 1
fi
