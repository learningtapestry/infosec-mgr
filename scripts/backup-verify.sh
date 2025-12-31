#!/bin/bash
# DefectDojo Backup Verification Script
#
# This script validates backups by actually restoring them to a test database.
# It runs daily via cron (after the backup job) and alerts on any failure.
#
# What it checks:
# 1. Recent backup exists in S3 (< 25 hours old)
# 2. Backup can be downloaded
# 3. Backup can be restored to PostgreSQL
# 4. Restored data passes sanity checks (tables exist, row counts > 0)
#
# On failure: publishes alert to SNS topic

set -e

# Configuration
S3_BUCKET="${S3_BUCKET:-infosec-mgr-backups-866795125297}"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-}"
WORK_DIR="/tmp/backup-verify"
TEST_DB="defectdojo_backup_test"
COMPOSE_FILE="/opt/defectdojo/repo/docker-compose.yml"
MAX_AGE_HOURS=25

# Cleanup function - always runs
cleanup() {
    echo "[$(date)] Cleaning up..."

    # Drop test database if it exists
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d postgres -c "DROP DATABASE IF EXISTS $TEST_DB;" 2>/dev/null || true

    # Remove temp files
    rm -rf "$WORK_DIR"

    echo "[$(date)] Cleanup complete"
}

# Alert function - sends SNS notification on failure
send_alert() {
    local message="$1"
    local subject="DefectDojo Backup Verification FAILED"

    echo "[$(date)] ALERT: $message"

    if [ -n "$SNS_TOPIC_ARN" ]; then
        aws sns publish \
            --topic-arn "$SNS_TOPIC_ARN" \
            --subject "$subject" \
            --message "$message" \
            --region us-east-1 || echo "Failed to send SNS alert"
    else
        echo "[$(date)] WARNING: SNS_TOPIC_ARN not set, cannot send alert"
    fi
}

# Main verification function
verify_backup() {
    echo "[$(date)] Starting backup verification..."

    mkdir -p "$WORK_DIR"

    # Step 1: Find most recent backup in S3
    echo "[$(date)] Step 1: Checking for recent backup in S3..."

    LATEST_BACKUP=$(aws s3 ls "s3://$S3_BUCKET/backups/daily/" | sort | tail -1)

    if [ -z "$LATEST_BACKUP" ]; then
        send_alert "No backups found in s3://$S3_BUCKET/backups/daily/"
        return 1
    fi

    BACKUP_FILE=$(echo "$LATEST_BACKUP" | awk '{print $4}')
    BACKUP_DATE=$(echo "$LATEST_BACKUP" | awk '{print $1}')
    BACKUP_TIME=$(echo "$LATEST_BACKUP" | awk '{print $2}')
    BACKUP_SIZE=$(echo "$LATEST_BACKUP" | awk '{print $3}')

    echo "[$(date)] Found backup: $BACKUP_FILE ($BACKUP_SIZE bytes)"

    # Check backup age
    BACKUP_EPOCH=$(date -d "$BACKUP_DATE $BACKUP_TIME" +%s)
    NOW_EPOCH=$(date +%s)
    AGE_HOURS=$(( (NOW_EPOCH - BACKUP_EPOCH) / 3600 ))

    echo "[$(date)] Backup age: $AGE_HOURS hours"

    if [ "$AGE_HOURS" -gt "$MAX_AGE_HOURS" ]; then
        send_alert "Most recent backup is $AGE_HOURS hours old (threshold: $MAX_AGE_HOURS hours). Backup file: $BACKUP_FILE"
        return 1
    fi

    # Step 2: Download backup
    echo "[$(date)] Step 2: Downloading backup from S3..."

    if ! aws s3 cp "s3://$S3_BUCKET/backups/daily/$BACKUP_FILE" "$WORK_DIR/$BACKUP_FILE"; then
        send_alert "Failed to download backup from S3: $BACKUP_FILE"
        return 1
    fi

    # Check file size after download
    LOCAL_SIZE=$(stat -c%s "$WORK_DIR/$BACKUP_FILE")
    if [ "$LOCAL_SIZE" -lt 100000 ]; then
        send_alert "Downloaded backup is suspiciously small: $LOCAL_SIZE bytes. File: $BACKUP_FILE"
        return 1
    fi

    echo "[$(date)] Downloaded: $LOCAL_SIZE bytes"

    # Step 3: Create test database
    echo "[$(date)] Step 3: Creating test database..."

    # Drop if exists (in case previous run failed)
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d postgres -c "DROP DATABASE IF EXISTS $TEST_DB;" || true

    if ! docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d postgres -c "CREATE DATABASE $TEST_DB;"; then
        send_alert "Failed to create test database: $TEST_DB"
        return 1
    fi

    # Step 4: Restore backup to test database
    echo "[$(date)] Step 4: Restoring backup to test database..."

    if ! gunzip -c "$WORK_DIR/$BACKUP_FILE" | docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d "$TEST_DB" > /dev/null 2>&1; then
        send_alert "Failed to restore backup to test database. Backup file: $BACKUP_FILE"
        return 1
    fi

    echo "[$(date)] Restore completed"

    # Step 5: Validate restored data
    echo "[$(date)] Step 5: Validating restored data..."

    # Check critical tables exist and have data
    VALIDATION_QUERY="
    SELECT
        (SELECT COUNT(*) FROM dojo_product) as products,
        (SELECT COUNT(*) FROM dojo_product_type) as product_types,
        (SELECT COUNT(*) FROM auth_user) as users,
        (SELECT COUNT(*) FROM dojo_test) as tests;
    "

    RESULT=$(docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d "$TEST_DB" -t -A -F',' -c "$VALIDATION_QUERY" 2>&1)

    if [ $? -ne 0 ]; then
        send_alert "Failed to run validation queries on restored database. Error: $RESULT"
        return 1
    fi

    # Parse results (format: products,product_types,users,tests)
    IFS=',' read -r PRODUCTS PRODUCT_TYPES USERS TESTS <<< "$RESULT"

    echo "[$(date)] Validation results:"
    echo "  - Products: $PRODUCTS"
    echo "  - Product Types: $PRODUCT_TYPES"
    echo "  - Users: $USERS"
    echo "  - Tests: $TESTS"

    # Sanity checks
    if [ "$PRODUCT_TYPES" -lt 1 ]; then
        send_alert "Validation failed: No product types found in restored database"
        return 1
    fi

    if [ "$USERS" -lt 1 ]; then
        send_alert "Validation failed: No users found in restored database"
        return 1
    fi

    echo "[$(date)] All validation checks passed!"
    return 0
}

# Main execution
trap cleanup EXIT

echo "========================================"
echo "DefectDojo Backup Verification"
echo "========================================"
echo "[$(date)] Starting verification run"

if verify_backup; then
    echo "[$(date)] SUCCESS: Backup verification completed successfully"
    exit 0
else
    echo "[$(date)] FAILURE: Backup verification failed"
    exit 1
fi
