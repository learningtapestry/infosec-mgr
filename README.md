# infosec-mgr

Central security scanning infrastructure for Learning Tapestry. Provides vulnerability management via DefectDojo and reusable GitHub Actions workflows for automated security scanning.

## Table of Contents

- [DefectDojo Access](#defectdojo-access)
- [Developer Guide: Adding Security Scanning](#developer-guide-adding-security-scanning)
- [Understanding Scan Results](#understanding-scan-results)
- [Available Workflows](#available-workflows)
- [Architecture](#architecture)
- [Admin Guide](#admin-guide)

---

## DefectDojo Access

**Production URL:** https://infosec-scanning.learningtapestry.com

### Logging In

1. Go to https://infosec-scanning.learningtapestry.com
2. Username: `admin`
3. Password: In Bitwarden 

### Getting an API Token

1. Log in to DefectDojo
2. Click your username (top right) → API v2 Key
3. Or go directly to: https://infosec-scanning.learningtapestry.com/api/key-v2

---

## Developer Guide: Adding Security Scanning

### Quick Start (5 minutes)

Add this file to any repo to enable automatic security scanning:

```yaml
# .github/workflows/security.yml
name: Security Scan

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  semgrep:
    name: Semgrep SAST
    uses: learningtapestry/infosec-mgr/.github/workflows/semgrep.yml@main
    secrets: inherit
```

**That's it.** On every push and PR, Semgrep will:
1. Scan your code for security vulnerabilities
2. Upload findings to DefectDojo
3. Deduplicate results (no spam from repeated scans)

### What Gets Scanned?

Semgrep automatically detects your language and applies relevant rules:
- **JavaScript/TypeScript**: XSS, injection, insecure dependencies
- **Python**: SQL injection, command injection, hardcoded secrets
- **Ruby**: Mass assignment, command injection, SQL injection
- **Go**: Race conditions, injection vulnerabilities
- **Java**: OWASP Top 10 vulnerabilities
- And many more...

### Workflow Behavior

| Behavior | Description |
|----------|-------------|
| **Non-blocking** | Scans run independently - they won't fail your builds or block merges |
| **Deduplicated** | Same finding won't be reported twice; only NEW issues appear |
| **Auto-creates product** | Your repo is automatically added to DefectDojo if it doesn't exist |
| **PR scanning** | Scans run on PRs so you can see issues before merging |

### Adding ScoutSuite (AWS Cloud Security)

To scan your AWS infrastructure for security misconfigurations:

```yaml
# .github/workflows/security.yml
name: Security Scan

on:
  push:
    branches: [main, master]
  schedule:
    # Weekly scan recommended for cloud infrastructure
    - cron: '0 9 * * 1'

jobs:
  scoutsuite:
    name: AWS Cloud Security
    uses: learningtapestry/infosec-mgr/.github/workflows/scoutsuite.yml@main
    secrets:
      DEFECTDOJO_URL: ${{ secrets.DEFECTDOJO_URL }}
      DEFECTDOJO_TOKEN: ${{ secrets.DEFECTDOJO_TOKEN }}
      SCOUTSUITE_AWS_ACCESS_KEY_ID: ${{ secrets.SCOUTSUITE_AWS_ACCESS_KEY_ID }}
      SCOUTSUITE_AWS_SECRET_ACCESS_KEY: ${{ secrets.SCOUTSUITE_AWS_SECRET_ACCESS_KEY }}
```

**Required Setup:**
1. Create a dedicated IAM user with `SecurityAudit` and `ViewOnlyAccess` policies (do NOT reuse Terraform/deployment credentials)
2. Add `SCOUTSUITE_AWS_ACCESS_KEY_ID` and `SCOUTSUITE_AWS_SECRET_ACCESS_KEY` as **repository-level** secrets

ScoutSuite checks for:
- Overly permissive IAM policies
- Public S3 buckets
- Unencrypted resources (EBS, RDS, S3)
- Security group misconfigurations
- CloudTrail/logging gaps
- And 100+ other AWS security best practices

### Adding Trivy (Dependency Scanning)

To also scan for vulnerable dependencies:

```yaml
# .github/workflows/security.yml
name: Security Scan

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  semgrep:
    name: SAST
    uses: learningtapestry/infosec-mgr/.github/workflows/semgrep.yml@main
    secrets: inherit

  trivy:
    name: Dependencies
    uses: learningtapestry/infosec-mgr/.github/workflows/trivy.yml@main
    with:
      scan_type: 'fs'
    secrets: inherit
```

### Full Security Scan (Everything)

For comprehensive scanning with both tools:

```yaml
# .github/workflows/security.yml
name: Security Scan

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  security:
    uses: learningtapestry/infosec-mgr/.github/workflows/full-security-scan.yml@main
    secrets: inherit
```

### Custom Product Name

By default, your repo name becomes the product name in DefectDojo. To customize:

```yaml
jobs:
  semgrep:
    uses: learningtapestry/infosec-mgr/.github/workflows/semgrep.yml@main
    with:
      product_name: "My Custom Product Name"
    secrets: inherit
```

---

## Understanding Scan Results

### Viewing Your Findings

1. Go to https://infosec-scanning.learningtapestry.com
2. Click **Findings** in the left sidebar
3. Filter by your product name (your repo name)

### Finding Severity Levels

| Severity | Action Required |
|----------|----------------|
| **Critical** | Fix immediately - active exploitation risk |
| **High** | Fix before next release |
| **Medium** | Fix when convenient |
| **Low** | Consider fixing, low risk |
| **Info** | Informational only |

### Managing Findings

**Mark as False Positive:**
1. Open the finding
2. Click **Close Finding**
3. Select "False Positive" as the reason
4. Add a note explaining why

**Mark as Risk Accepted:**
1. Open the finding
2. Click **Accept Risk**
3. Add justification and expiration date

**Track Remediation:**
1. Open the finding
2. Add notes about your fix
3. Link to PR/commit if applicable
4. Finding auto-closes when scanner no longer detects it

---

## Available Workflows

| Workflow | Purpose | When to Use |
|----------|---------|-------------|
| `semgrep.yml` | Static code analysis (SAST) | Every repo - finds code vulnerabilities |
| `trivy.yml` | Dependency & container scanning | Repos with dependencies or containers |
| `scoutsuite.yml` | AWS cloud security scanning | Repos that deploy AWS infrastructure |
| `full-security-scan.yml` | All scans combined | Comprehensive security check |

### Workflow Parameters

**semgrep.yml:**
```yaml
with:
  product_name: 'optional-custom-name'      # Default: repo name
  product_type_name: 'Web Application'      # DefectDojo product type
  semgrep_config: 'auto'                    # Semgrep ruleset (auto recommended)
```

**trivy.yml:**
```yaml
with:
  product_name: 'optional-custom-name'
  scan_type: 'fs'                           # 'fs' (filesystem), 'image', or 'repo'
  image_ref: 'myimage:tag'                  # Required if scan_type is 'image'
```

**scoutsuite.yml:**
```yaml
with:
  product_name: 'optional-custom-name'
  product_type_name: 'Web Application'      # Must match existing product type
  aws_region: 'us-east-1'                   # AWS region to scan
secrets:
  SCOUTSUITE_AWS_ACCESS_KEY_ID: ${{ secrets.SCOUTSUITE_AWS_ACCESS_KEY_ID }}
  SCOUTSUITE_AWS_SECRET_ACCESS_KEY: ${{ secrets.SCOUTSUITE_AWS_SECRET_ACCESS_KEY }}
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GitHub Organization                                  │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   app-1     │  │   app-2     │  │  frontend   │  │   api       │        │
│  │             │  │             │  │             │  │             │        │
│  │ security.yml│  │ security.yml│  │ security.yml│  │ security.yml│        │
│  │ (6 lines)   │  │ (6 lines)   │  │ (6 lines)   │  │ (6 lines)   │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │               │
│         └────────────────┴────────────────┴────────────────┘               │
│                                   │                                         │
│                          uses: learningtapestry/                            │
│                          infosec-mgr/.github/workflows/semgrep.yml@main     │
│                                   │                                         │
│         ┌─────────────────────────┴─────────────────────────┐              │
│         │           infosec-mgr (this repo)                 │              │
│         │  .github/workflows/                               │              │
│         │  ├── semgrep.yml     (reusable)                  │              │
│         │  ├── trivy.yml       (reusable)                  │              │
│         │  ├── full-security-scan.yml                      │              │
│         │  └── self-scan.yml   (dogfood)                   │              │
│         └───────────────────────────────────────────────────┘              │
│                                   │                                         │
│              Org Secrets: DEFECTDOJO_URL, DEFECTDOJO_TOKEN                 │
│                                   │                                         │
└───────────────────────────────────┼─────────────────────────────────────────┘
                                    │ HTTPS API
                                    ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│  AWS Account (866795125297)                                                   │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐    │
│  │  EC2 (t3.medium) - 54.86.136.184                                     │    │
│  │  infosec-scanning.learningtapestry.com                               │    │
│  │                                                                       │    │
│  │  ┌────────────────────────────────────────────────────────────────┐  │    │
│  │  │  Docker Compose Stack                                          │  │    │
│  │  │  ├── nginx       (ports 80, 443)                               │  │    │
│  │  │  ├── uwsgi       (DefectDojo application)                      │  │    │
│  │  │  ├── postgres    (database)                                    │  │    │
│  │  │  ├── valkey      (cache/queue)                                 │  │    │
│  │  │  ├── celerybeat  (scheduled tasks)                             │  │    │
│  │  │  └── celeryworker (async processing)                           │  │    │
│  │  └────────────────────────────────────────────────────────────────┘  │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                               │
│  ┌─────────────────┐                                                         │
│  │  S3 Bucket      │  Daily pg_dump backups                                  │
│  │  (backups)      │  90-day retention                                       │
│  └─────────────────┘                                                         │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## Admin Guide

### Infrastructure

| Component | Details |
|-----------|---------|
| **EC2 Instance** | t3.medium, Amazon Linux 2023 |
| **Elastic IP** | 54.86.136.184 |
| **Domain** | infosec-scanning.learningtapestry.com |
| **SSL** | Let's Encrypt (auto-renews) |
| **Database** | PostgreSQL (Docker volume) |
| **Backups** | Daily to S3, 90-day retention |

### SSH Access

```bash
ssh -i ~/.ssh/infosec-key.pem ec2-user@54.86.136.184
```

### Common Operations

```bash
# View logs
cd /opt/defectdojo/repo && docker compose logs -f

# Restart DefectDojo
cd /opt/defectdojo/repo && docker compose restart

# Manual backup
sudo /opt/defectdojo/backup.sh

# Check backup status
ls -la /opt/defectdojo/backups/

# View backup in S3
aws s3 ls s3://infosec-mgr-backups-866795125297/backups/

# Update DefectDojo
cd /opt/defectdojo/repo && git pull && docker compose pull && docker compose up -d
```

### Deployment Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `deploy-infra.yml` | Manual (workflow_dispatch) | Create/update AWS infrastructure via Terraform |
| `deploy-app.yml` | Push to main | Deploy application updates to EC2 |
| `destroy-infra.yml` | Manual | Tear down infrastructure (keeps EIP & S3) |

### GitHub Secrets Required

**Organization Level:**
| Secret | Purpose |
|--------|---------|
| `DEFECTDOJO_URL` | https://infosec-scanning.learningtapestry.com |
| `DEFECTDOJO_TOKEN` | API token for scan uploads |

> **Initial Setup:** After deploying DefectDojo, you must copy the API token and URL to GitHub organization secrets. Get the token from DefectDojo: click your username (top right) → API v2 Key, or visit `/api/key-v2`. Then add both `DEFECTDOJO_URL` and `DEFECTDOJO_TOKEN` as organization-level secrets in GitHub (Settings → Secrets and variables → Actions → Organization secrets).

**Repository Level (for this repo's deployments):**
| Secret | Purpose |
|--------|---------|
| `AWS_ACCESS_KEY_ID` | Terraform deployments |
| `AWS_SECRET_ACCESS_KEY` | Terraform deployments |
| `EC2_SSH_PRIVATE_KEY` | App deployments |
| `EC2_ELASTIC_IP` | App deployment target |
| `EIP_ALLOCATION_ID` | Terraform EIP management |
| `SCOUTSUITE_AWS_ACCESS_KEY_ID` | ScoutSuite cloud scanning (read-only) |
| `SCOUTSUITE_AWS_SECRET_ACCESS_KEY` | ScoutSuite cloud scanning (read-only) |

**Repository Level (for repos using ScoutSuite workflow):**
| Secret | Purpose |
|--------|---------|
| `SCOUTSUITE_AWS_ACCESS_KEY_ID` | Dedicated read-only IAM user for ScoutSuite |
| `SCOUTSUITE_AWS_SECRET_ACCESS_KEY` | Dedicated read-only IAM user for ScoutSuite |

> **Security Note:** Create a separate IAM user for ScoutSuite with only `SecurityAudit` and `ViewOnlyAccess` policies. Do NOT reuse Terraform or deployment credentials - ScoutSuite should have read-only access to audit your infrastructure without being able to modify it or access sensitive data.

### Cost

| Resource | Monthly Cost |
|----------|-------------|
| EC2 t3.medium | ~$30 |
| EBS 30GB | ~$3 |
| S3 backups | ~$1 |
| **Total** | **~$35/month** |

### Local Development

```bash
git clone https://github.com/learningtapestry/infosec-mgr.git
cd infosec-mgr
docker compose up -d

# Get admin password
docker compose logs initializer | grep "Admin password"

# Access locally
open http://localhost:8080
```

---

## Project Structure

```
infosec-mgr/
├── .github/
│   └── workflows/
│       ├── semgrep.yml              # Reusable: SAST scanning
│       ├── trivy.yml                # Reusable: dependency scanning
│       ├── scoutsuite.yml           # Reusable: AWS cloud security scanning
│       ├── full-security-scan.yml   # Reusable: all scans
│       ├── self-scan.yml            # Dogfood: scan this repo
│       ├── deploy-infra.yml         # Terraform deployment
│       ├── deploy-app.yml           # Application deployment
│       └── destroy-infra.yml        # Infrastructure teardown
│
├── terraform/                        # AWS infrastructure as code
│   ├── main.tf
│   ├── variables.tf
│   ├── ec2.tf
│   ├── vpc.tf
│   ├── s3.tf                        # Backup bucket + lifecycle
│   ├── alerts.tf                    # SNS topic for backup alerts
│   ├── iam.tf                       # IAM roles and policies
│   └── user-data.sh                 # EC2 bootstrap script
│
├── scripts/
│   ├── backup.sh                    # Database backup script
│   └── backup-verify.sh             # Backup restore verification
│
├── docker/
│   ├── extra_settings/
│   │   └── local_settings.py        # DefectDojo config-as-code
│   └── extra_fixtures/
│       ├── extra_001_product_types.json
│       └── extra_002_products.json
│
├── tests/                           # Playwright E2E tests
│
├── docker-compose.yml               # DefectDojo deployment
├── CLAUDE.md                        # AI assistant instructions
└── README.md                        # This file
```

---

## Slack Notifications

DefectDojo supports Slack notifications for security findings. **Notifications are OPT-IN by default** - no alerts are sent unless explicitly configured.

### Setup (Admin - One Time)

1. **Create a Slack App:**
   - Go to https://api.slack.com/apps
   - Click "Create New App" → "From scratch"
   - Name it "DefectDojo" and select your workspace

2. **Enable Incoming Webhooks:**
   - In your app settings, go to "Incoming Webhooks"
   - Toggle "Activate Incoming Webhooks" to On
   - Click "Add New Webhook to Workspace"
   - Select the channel for security notifications
   - Copy the webhook URL

3. **Configure DefectDojo:**
   - Log in as admin
   - Go to ⚙️ **System Settings** (gear icon, top right)
   - Paste the webhook URL in "Slack Webhook URL"
   - Save

### Enabling Notifications (Per Product)

Users must opt-in to receive notifications:

1. Navigate to the Product you want notifications for
2. Click **Notifications** tab
3. Check "Slack" for the events you want alerts on
4. Save

### Available Notification Events

| Event | Description |
|-------|-------------|
| Product added | New product created |
| Engagement added | New engagement started |
| Test added | New test created |
| Scan added | New scan uploaded |
| SLA breach | Finding exceeds SLA threshold |
| Risk acceptance expiration | Accepted risk is expiring |

---

## Backup System

Automated daily backups with restore verification.

### Schedule

| Job | Time (UTC) | Purpose |
|-----|------------|---------|
| `backup.sh` | 3:00 AM | Create backup, upload to S3 |
| `backup-verify.sh` | 5:00 AM | Download, restore to test DB, validate |

### Retention

| Tier | Location | Retention |
|------|----------|-----------|
| Daily | `s3://infosec-mgr-backups-*/backups/daily/` | 30 days |
| Monthly | `s3://infosec-mgr-backups-*/backups/monthly/` | 6 months |

### Alerts

Backup failures trigger SNS alerts to `admins@learningtapestry.com`. Confirm the SNS subscription when you receive the AWS confirmation email.

### Manual Operations

```bash
# Trigger manual backup
sudo /opt/defectdojo/backup.sh

# Run backup verification
sudo /opt/defectdojo/backup-verify.sh

# View backup logs
tail -f /var/log/defectdojo-backup.log
tail -f /var/log/defectdojo-backup-verify.log
```

---

## Troubleshooting

### Scans aren't uploading to DefectDojo

1. Check that org secrets `DEFECTDOJO_URL` and `DEFECTDOJO_TOKEN` are set
2. Verify the token hasn't expired (regenerate at `/api/key-v2`)
3. Check the workflow logs for API errors

### Can't log in to DefectDojo

1. Try resetting password via Django admin:
   ```bash
   ssh -i ~/.ssh/infosec-key.pem ec2-user@54.86.136.184
   cd /opt/defectdojo/repo
   docker compose exec uwsgi python manage.py changepassword admin
   ```

### DefectDojo is slow or unresponsive

1. Check container health:
   ```bash
   docker compose ps
   docker compose logs uwsgi
   ```
2. Restart services:
   ```bash
   docker compose restart
   ```

---

## Contributing

1. Workflow changes affect ALL repos using them - test thoroughly
2. This repo dogfoods itself - check `self-scan.yml` passes
3. Update this README when adding new features

## License

Based on [DefectDojo](https://github.com/DefectDojo/django-DefectDojo), licensed under BSD-3-Clause.
