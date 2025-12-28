#!/bin/bash
# DefectDojo Configuration via API
# This script configures DefectDojo using the REST API for GitOps-style management.
# Run this after DefectDojo is up and fixtures are loaded.

set -e

# Configuration - override these with environment variables
DOJO_URL="${DOJO_URL:-http://localhost:8080}"
DOJO_ADMIN_USER="${DD_ADMIN_USER:-admin}"
DOJO_ADMIN_PASSWORD="${DD_ADMIN_PASSWORD:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Wait for DefectDojo to be ready
wait_for_dojo() {
    log_info "Waiting for DefectDojo to be ready..."
    for i in {1..60}; do
        if curl -s "${DOJO_URL}/login" > /dev/null 2>&1; then
            log_info "DefectDojo is ready!"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    log_error "DefectDojo did not become ready in time"
    return 1
}

# Get API token
get_api_token() {
    if [ -z "$DOJO_ADMIN_PASSWORD" ]; then
        log_error "DD_ADMIN_PASSWORD environment variable not set"
        log_info "Get the password from: docker compose logs initializer | grep 'Admin password'"
        exit 1
    fi

    log_info "Obtaining API token..."

    # Get CSRF token from login page
    CSRF_TOKEN=$(curl -s -c /tmp/cookies.txt "${DOJO_URL}/login" | grep -oP 'csrfmiddlewaretoken" value="\K[^"]+' | head -1)

    # Login to get session
    curl -s -b /tmp/cookies.txt -c /tmp/cookies.txt \
        -d "csrfmiddlewaretoken=${CSRF_TOKEN}&username=${DOJO_ADMIN_USER}&password=${DOJO_ADMIN_PASSWORD}" \
        -H "Referer: ${DOJO_URL}/login" \
        "${DOJO_URL}/login" > /dev/null

    # Get API key page
    API_KEY=$(curl -s -b /tmp/cookies.txt "${DOJO_URL}/api/key-v2" | grep -oP 'Your current API key is <b>\K[^<]+' || echo "")

    if [ -z "$API_KEY" ]; then
        log_warn "Could not extract API key automatically. You may need to get it manually from ${DOJO_URL}/api/key-v2"
        return 1
    fi

    echo "$API_KEY"
}

# Generic API call function
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    curl -s -X "$method" \
        -H "Authorization: Token ${API_TOKEN}" \
        -H "Content-Type: application/json" \
        ${data:+-d "$data"} \
        "${DOJO_URL}/api/v2/${endpoint}"
}

# Create or update a product via API
create_product() {
    local name="$1"
    local description="$2"
    local prod_type_id="$3"

    log_info "Creating product: $name"
    api_call POST "products/" "{
        \"name\": \"${name}\",
        \"description\": \"${description}\",
        \"prod_type\": ${prod_type_id}
    }"
}

# Import a scan result
import_scan() {
    local product_name="$1"
    local scan_type="$2"
    local scan_file="$3"

    log_info "Importing scan: $scan_type for $product_name"

    curl -s -X POST \
        -H "Authorization: Token ${API_TOKEN}" \
        -F "scan_type=${scan_type}" \
        -F "product_name=${product_name}" \
        -F "engagement_name=CI/CD Scan" \
        -F "auto_create_context=true" \
        -F "file=@${scan_file}" \
        "${DOJO_URL}/api/v2/import-scan/"
}

# List available scan types
list_scan_types() {
    log_info "Available scan types:"
    api_call GET "test-types/?limit=200" | jq -r '.results[].name' | sort
}

# Example: Configure system settings
configure_system_settings() {
    log_info "Configuring system settings..."
    api_call PATCH "system-settings/1/" '{
        "enable_deduplication": true,
        "delete_duplicates": false,
        "max_dupes": 10
    }'
}

# Main script
main() {
    wait_for_dojo

    # Get API token
    API_TOKEN=$(get_api_token)
    if [ -z "$API_TOKEN" ]; then
        log_error "Failed to get API token"
        exit 1
    fi

    log_info "API Token obtained successfully"
    echo ""
    echo "=========================================="
    echo "API Token: $API_TOKEN"
    echo "=========================================="
    echo ""
    echo "Save this token for CI/CD integrations!"
    echo ""

    # Example operations (uncomment as needed):
    # list_scan_types
    # configure_system_settings
    # create_product "My New Product" "Created via API" 100
    # import_scan "Example Web App" "Trivy Scan" "./scan-results.json"

    log_info "Setup complete!"
    log_info "DefectDojo is available at: ${DOJO_URL}"
    log_info "API documentation: ${DOJO_URL}/api/v2/oa3/swagger-ui/"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
