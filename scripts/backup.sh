#!/bin/bash
# DefectDojo database backup script with tiered retention
#
# Retention Policy:
# - Daily backups: kept for 30 days (S3 lifecycle on backups/daily/)
# - Monthly backups: kept for 6 months (S3 lifecycle on backups/monthly/)
#
# On the 1st of each month, the daily backup is also copied to monthly/

set -e

BACKUP_DIR="/opt/defectdojo/backups"
S3_BUCKET="${S3_BUCKET:-infosec-mgr-backups-866795125297}"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
DAY_OF_MONTH=$(date +%d)
YEAR_MONTH=$(date +%Y-%m)
BACKUP_FILE="defectdojo-backup-$DATE.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting backup..."

# Dump database with compression
docker compose -f /opt/defectdojo/repo/docker-compose.yml exec -T postgres \
    pg_dump -U defectdojo defectdojo | gzip > "$BACKUP_DIR/$BACKUP_FILE"

BACKUP_SIZE=$(stat -f%z "$BACKUP_DIR/$BACKUP_FILE" 2>/dev/null || stat -c%s "$BACKUP_DIR/$BACKUP_FILE")
echo "[$(date)] Local backup created: $BACKUP_FILE ($BACKUP_SIZE bytes)"

# Upload to S3 daily prefix
echo "[$(date)] Uploading to S3 daily prefix..."
aws s3 cp "$BACKUP_DIR/$BACKUP_FILE" "s3://$S3_BUCKET/backups/daily/$BACKUP_FILE"

# On the 1st of the month, also copy to monthly archive
if [ "$DAY_OF_MONTH" = "01" ]; then
    MONTHLY_FILE="defectdojo-monthly-$YEAR_MONTH.sql.gz"
    echo "[$(date)] First of month - creating monthly archive: $MONTHLY_FILE"
    aws s3 cp "$BACKUP_DIR/$BACKUP_FILE" "s3://$S3_BUCKET/backups/monthly/$MONTHLY_FILE"
fi

# Keep only last 7 local backups (local disk space management)
ls -t "$BACKUP_DIR"/defectdojo-backup-*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm

echo "[$(date)] Backup completed successfully: $BACKUP_FILE"

# Output verification info for logging
echo "[$(date)] Verification:"
echo "  - Local file: $BACKUP_DIR/$BACKUP_FILE"
echo "  - S3 daily: s3://$S3_BUCKET/backups/daily/$BACKUP_FILE"
if [ "$DAY_OF_MONTH" = "01" ]; then
    echo "  - S3 monthly: s3://$S3_BUCKET/backups/monthly/$MONTHLY_FILE"
fi
