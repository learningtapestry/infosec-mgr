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
pid /var/run/nginx.pid;

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
    echo "0 0,12 * * * root certbot renew --quiet && cp /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem $APP_DIR/ssl/nginx.crt && cp /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem $APP_DIR/ssl/nginx.key && docker compose -f $APP_DIR/repo/docker-compose.yml restart nginx" > /etc/cron.d/certbot-renew
  else
    echo "SSL certificate acquisition failed, starting without SSL"
    docker compose start nginx
  fi
else
  echo "No domain provided, skipping SSL setup"
fi

# Create backup script
echo "Creating backup script..."
cat > $APP_DIR/backup.sh << 'BACKUPEOF'
#!/bin/bash
# DefectDojo database backup script

set -e

BACKUP_DIR="/opt/defectdojo/backups"
S3_BUCKET="S3_BUCKET_PLACEHOLDER"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="defectdojo-backup-$DATE.sql.gz"

mkdir -p $BACKUP_DIR

# Dump database
docker compose -f /opt/defectdojo/repo/docker-compose.yml exec -T postgres pg_dump -U defectdojo defectdojo | gzip > $BACKUP_DIR/$BACKUP_FILE

# Upload to S3
aws s3 cp $BACKUP_DIR/$BACKUP_FILE s3://$S3_BUCKET/backups/$BACKUP_FILE

# Keep only last 7 local backups
ls -t $BACKUP_DIR/defectdojo-backup-*.sql.gz | tail -n +8 | xargs -r rm

echo "Backup completed: $BACKUP_FILE"
BACKUPEOF

sed -i "s/S3_BUCKET_PLACEHOLDER/$S3_BUCKET/g" $APP_DIR/backup.sh
chmod +x $APP_DIR/backup.sh

# Setup daily backup cron (3 AM)
echo "0 3 * * * root $APP_DIR/backup.sh >> /var/log/defectdojo-backup.log 2>&1" > /etc/cron.d/defectdojo-backup

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
