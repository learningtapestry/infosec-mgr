#!/bin/bash
# DefectDojo EC2 Bootstrap Script
# This script runs on first boot to set up the DefectDojo environment
# Note: $${var} syntax is used to escape bash variables from Terraform interpolation

set -e

# Log all output
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting DefectDojo bootstrap at $(date)"

# Variables from Terraform template
GITHUB_REPO="${github_repo}"
DOMAIN_NAME="${domain_name}"
ADMIN_PASSWORD="${admin_password}"
S3_BUCKET="${s3_bucket}"
SNS_TOPIC_ARN="${sns_topic_arn}"

# Create application directory
APP_DIR="/opt/defectdojo"
mkdir -p $APP_DIR
cd $APP_DIR

# Update system
echo "Updating system packages..."
dnf update -y

# Install Docker
echo "Installing Docker..."
dnf install -y docker git

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install Docker Compose v2
echo "Installing Docker Compose..."
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Clone repository
echo "Cloning repository..."
git clone $GITHUB_REPO $APP_DIR/repo
cd $APP_DIR/repo

# Fix repo ownership for ec2-user deploys
chown -R ec2-user:ec2-user $APP_DIR/repo

# Generate secrets if not provided
DD_SECRET_KEY=$(openssl rand -base64 32)
DD_CREDENTIAL_AES_256_KEY=$(openssl rand -hex 16)

# Create production docker-compose override
echo "Creating production configuration..."
cat > docker-compose.override.yml << EOF
services:
  uwsgi:
    environment:
      DD_SECRET_KEY: "$DD_SECRET_KEY"
      DD_CREDENTIAL_AES_256_KEY: "$DD_CREDENTIAL_AES_256_KEY"
      DD_DEBUG: "False"
      DD_ALLOWED_HOSTS: "*"
EOF

# Add admin password if provided
if [ -n "$ADMIN_PASSWORD" ]; then
  cat >> docker-compose.override.yml << EOF
      DD_ADMIN_PASSWORD: "$ADMIN_PASSWORD"
EOF
fi

# Start DefectDojo
echo "Starting DefectDojo stack..."
docker compose up -d

# Wait for DefectDojo to be ready
echo "Waiting for DefectDojo to initialize (this may take 5-10 minutes)..."
for i in {1..60}; do
  if curl -s http://localhost:8080/api/v2/ > /dev/null 2>&1; then
    echo "DefectDojo is ready!"
    break
  fi
  echo "Waiting for DefectDojo... ($i/60)"
  sleep 10
done

# Setup SSL if domain is provided
if [ -n "$DOMAIN_NAME" ]; then
  echo "Setting up SSL for $DOMAIN_NAME..."

  # Install certbot
  dnf install -y certbot

  # Stop nginx temporarily to get certificate
  docker compose stop nginx

  # Get certificate (standalone mode)
  certbot certonly --standalone -d $DOMAIN_NAME --non-interactive --agree-tos --email admin@$DOMAIN_NAME || true

  # If certificate obtained, configure SSL
  if [ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]; then
    mkdir -p $APP_DIR/ssl
    cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem $APP_DIR/ssl/nginx.crt
    cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem $APP_DIR/ssl/nginx.key
    chmod 644 $APP_DIR/ssl/nginx.key

    # Create nginx config with SSL
    mkdir -p $APP_DIR/nginx
    cat > $APP_DIR/nginx/nginx.conf << 'NGINXEOF'
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 800m;

    upstream uwsgi {
        server uwsgi:3031;
    }

    # HTTP to HTTPS redirect
    server {
        listen 8080;
        server_name DOMAIN_PLACEHOLDER;
        return 301 https://$host$request_uri;
    }

    # HTTPS server
    server {
        listen 8443 ssl;
        server_name DOMAIN_PLACEHOLDER;

        ssl_certificate /etc/nginx/ssl/nginx.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
        ssl_prefer_server_ciphers off;

        location /static/ {
            alias /usr/share/nginx/html/static/;
        }

        location / {
            include /etc/nginx/wsgi_params;
            uwsgi_pass uwsgi;
            uwsgi_read_timeout 1800;
        }
    }
}
NGINXEOF

    # Replace domain placeholder
    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN_NAME/g" $APP_DIR/nginx/nginx.conf

    # Update docker-compose override with SSL config
    cat >> docker-compose.override.yml << EOF

  nginx:
    ports:
      - "80:8080"
      - "443:8443"
    volumes:
      - $APP_DIR/ssl:/etc/nginx/ssl:ro
      - $APP_DIR/nginx/nginx.conf:/opt/nginx-custom.conf:ro
    entrypoint: ["/bin/sh", "-c", "cp /opt/nginx-custom.conf /etc/nginx/nginx.conf && /entrypoint-nginx.sh"]
EOF

    # Restart with SSL config
    docker compose up -d

    # Setup certificate renewal cron
    mkdir -p /etc/cron.d
    echo "0 0,12 * * * root certbot renew --quiet && cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem $APP_DIR/ssl/nginx.crt && cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem $APP_DIR/ssl/nginx.key && docker compose -f $APP_DIR/repo/docker-compose.yml restart nginx" > /etc/cron.d/certbot-renew
  else
    echo "SSL certificate acquisition failed, starting without SSL"
    docker compose start nginx
  fi
else
  echo "No domain provided, skipping SSL setup"
fi

# Create backup script with tiered retention
# Daily backups go to backups/daily/ (30-day S3 lifecycle)
# Monthly backups go to backups/monthly/ (180-day S3 lifecycle)
echo "Creating backup script..."
cat > $APP_DIR/backup.sh << 'BACKUPEOF'
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
S3_BUCKET="S3_BUCKET_PLACEHOLDER"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
DAY_OF_MONTH=$(date +%d)
YEAR_MONTH=$(date +%Y-%m)
BACKUP_FILE="defectdojo-backup-$DATE.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting backup..."

# Dump database with compression
docker compose -f /opt/defectdojo/repo/docker-compose.yml exec -T postgres \
    pg_dump -U defectdojo defectdojo | gzip > "$BACKUP_DIR/$BACKUP_FILE"

BACKUP_SIZE=$(stat -c%s "$BACKUP_DIR/$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_DIR/$BACKUP_FILE")
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
BACKUPEOF

sed -i "s/S3_BUCKET_PLACEHOLDER/$S3_BUCKET/g" $APP_DIR/backup.sh
chmod +x $APP_DIR/backup.sh

# Setup daily backup cron (3 AM)
mkdir -p /etc/cron.d
echo "0 3 * * * root $APP_DIR/backup.sh >> /var/log/defectdojo-backup.log 2>&1" > /etc/cron.d/defectdojo-backup

# Create backup verification script (restore test)
echo "Creating backup verification script..."
cat > $APP_DIR/backup-verify.sh << 'VERIFYEOF'
#!/bin/bash
# DefectDojo Backup Verification Script
# Validates backups by restoring to a test database

set -e

S3_BUCKET="S3_BUCKET_PLACEHOLDER"
SNS_TOPIC_ARN="SNS_TOPIC_PLACEHOLDER"
WORK_DIR="/tmp/backup-verify"
TEST_DB="defectdojo_backup_test"
COMPOSE_FILE="/opt/defectdojo/repo/docker-compose.yml"
MAX_AGE_HOURS=25

cleanup() {
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d postgres -c "DROP DATABASE IF EXISTS $TEST_DB;" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}

send_alert() {
    local message="$1"
    echo "[$(date)] ALERT: $message"
    if [ -n "$SNS_TOPIC_ARN" ]; then
        aws sns publish --topic-arn "$SNS_TOPIC_ARN" \
            --subject "DefectDojo Backup Verification FAILED" \
            --message "$message" --region us-east-1 || true
    fi
}

verify_backup() {
    mkdir -p "$WORK_DIR"

    # Find most recent backup
    LATEST=$(aws s3 ls "s3://$S3_BUCKET/backups/daily/" | sort | tail -1)
    if [ -z "$LATEST" ]; then
        send_alert "No backups found in S3"
        return 1
    fi

    BACKUP_FILE=$(echo "$LATEST" | awk '{print $4}')
    BACKUP_DATE=$(echo "$LATEST" | awk '{print $1}')
    BACKUP_TIME=$(echo "$LATEST" | awk '{print $2}')
    echo "[$(date)] Found backup: $BACKUP_FILE"

    # Check age
    BACKUP_EPOCH=$(date -d "$BACKUP_DATE $BACKUP_TIME" +%s)
    AGE_HOURS=$(( ($(date +%s) - BACKUP_EPOCH) / 3600 ))
    if [ "$AGE_HOURS" -gt "$MAX_AGE_HOURS" ]; then
        send_alert "Backup is $AGE_HOURS hours old (threshold: $MAX_AGE_HOURS)"
        return 1
    fi

    # Download
    if ! aws s3 cp "s3://$S3_BUCKET/backups/daily/$BACKUP_FILE" "$WORK_DIR/$BACKUP_FILE"; then
        send_alert "Failed to download backup: $BACKUP_FILE"
        return 1
    fi

    # Create test DB
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d postgres -c "DROP DATABASE IF EXISTS $TEST_DB;" || true
    docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d postgres -c "CREATE DATABASE $TEST_DB;"

    # Restore
    if ! gunzip -c "$WORK_DIR/$BACKUP_FILE" | docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d "$TEST_DB" > /dev/null 2>&1; then
        send_alert "Failed to restore backup: $BACKUP_FILE"
        return 1
    fi

    # Validate
    RESULT=$(docker compose -f "$COMPOSE_FILE" exec -T postgres \
        psql -U defectdojo -d "$TEST_DB" -t -A -c \
        "SELECT COUNT(*) FROM dojo_product_type;" 2>&1)
    if [ "$RESULT" -lt 1 ]; then
        send_alert "Validation failed: no product types in restored DB"
        return 1
    fi

    echo "[$(date)] Backup verification passed! ($RESULT product types found)"
    return 0
}

trap cleanup EXIT
echo "[$(date)] Starting backup verification..."
if verify_backup; then
    echo "[$(date)] SUCCESS"
else
    echo "[$(date)] FAILED"
    exit 1
fi
VERIFYEOF

sed -i "s/S3_BUCKET_PLACEHOLDER/$S3_BUCKET/g" $APP_DIR/backup-verify.sh
sed -i "s|SNS_TOPIC_PLACEHOLDER|$SNS_TOPIC_ARN|g" $APP_DIR/backup-verify.sh
chmod +x $APP_DIR/backup-verify.sh

# Setup backup verification cron (5 AM, after 3 AM backup)
echo "0 5 * * * root $APP_DIR/backup-verify.sh >> /var/log/defectdojo-backup-verify.log 2>&1" > /etc/cron.d/defectdojo-backup-verify

# Save important info
echo "Saving deployment info..."
DOMAIN_DISPLAY="None (use Elastic IP)"
if [ -n "$DOMAIN_NAME" ]; then
  DOMAIN_DISPLAY="$DOMAIN_NAME"
fi

cat > $APP_DIR/deployment-info.txt << EOF
DefectDojo Deployment Information
=================================
Deployed: $(date)
Repository: $GITHUB_REPO
Domain: $DOMAIN_DISPLAY
S3 Bucket: $S3_BUCKET

Secrets (stored in docker-compose.override.yml):
DD_SECRET_KEY: $DD_SECRET_KEY
DD_CREDENTIAL_AES_256_KEY: $DD_CREDENTIAL_AES_256_KEY

Admin Credentials:
Username: admin
Password: Check docker compose logs initializer | grep "Admin password"

Useful Commands:
- View logs: cd $APP_DIR/repo && docker compose logs -f
- Restart: cd $APP_DIR/repo && docker compose restart
- Stop: cd $APP_DIR/repo && docker compose down
- Start: cd $APP_DIR/repo && docker compose up -d
- Update: cd $APP_DIR/repo && git pull && docker compose pull && docker compose up -d
- Manual backup: $APP_DIR/backup.sh
EOF

chmod 600 $APP_DIR/deployment-info.txt

echo "DefectDojo bootstrap completed at $(date)"
if [ -n "$DOMAIN_NAME" ]; then
  echo "Access DefectDojo at: https://$DOMAIN_NAME"
else
  echo "Access DefectDojo at: http://<elastic-ip>:8080"
fi
