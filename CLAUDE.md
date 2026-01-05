# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Central security scanning infrastructure for Learning Tapestry. This repo provides:
1. **DefectDojo** - Vulnerability aggregation and management (forked from upstream)
2. **Reusable GitHub Workflows** - Centralized security scan configurations used by all org repos
3. **AWS Infrastructure** - Terraform-managed EC2 deployment with automated backups

## Critical: Config-as-Code Principle

**MANDATORY: All configuration must be managed through files, not the UI.**

When asked to configure anything, you MUST create/modify files rather than provide UI instructions. The UI is only acceptable for viewing/triaging findings and generating reports.

## Git Workflow

**Code flows: local main → origin/main → PR to production → merge → deploy**

```
┌─────────────┐     push      ┌─────────────┐      PR       ┌──────────────┐     auto      ┌─────────────┐
│ local main  │ ───────────▶  │ origin/main │  ──────────▶  │  production  │  ──────────▶  │  EC2 server │
└─────────────┘               └─────────────┘               └──────────────┘               └─────────────┘
```

**RESTRICTIONS (ask user for permission before violating):**
- Do NOT push directly to the `production` branch
- Do NOT checkout or track `production` locally
- Do NOT use `git push --force` on any remote branch
- All production deployments MUST go through a PR from `main`

The `deploy-app.yml` workflow triggers on push to `production` branch only.

## Commands

### Local Development
```bash
docker compose up -d              # Start DefectDojo stack
docker compose logs -f            # View logs
docker compose down               # Stop stack
docker compose logs initializer | grep "Admin password"  # Get admin password
```

### Terraform (AWS Infrastructure)
```bash
cd terraform
terraform init
terraform plan                    # Preview changes
terraform apply                   # Apply changes
```

### Tests (Playwright)
```bash
cd tests
npm install
npx playwright test               # Run all tests
npx playwright test smoke/        # Run smoke tests only
npx playwright test e2e/login.spec.ts  # Run single test file
npx playwright test --headed      # Run with browser visible
```

### DefectDojo Fixtures
```bash
docker compose exec uwsgi python manage.py loaddata extra_001_product_types
docker compose exec uwsgi python manage.py loaddata extra_002_products
```

## Architecture

### Reusable Workflows (Used by Other Repos)
Other repos call these with `uses: learningtapestry/infosec-mgr/.github/workflows/<name>@main`:

| Workflow | Purpose |
|----------|---------|
| `semgrep.yml` | SAST scanning, uploads to DefectDojo |
| `trivy.yml` | Dependency/container scanning |
| `scoutsuite.yml` | AWS cloud security scanning |
| `full-security-scan.yml` | All scans combined |

**Changes to these workflows affect ALL repos using them.** Test thoroughly.

### Deployment Workflows (This Repo Only)
| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `deploy-infra.yml` | Manual | Terraform apply |
| `deploy-app.yml` | Push to production | SSH deploy + smoke tests |
| `destroy-infra.yml` | Manual | Terraform destroy |
| `self-scan.yml` | Push/PR/weekly | Dogfooding - scans this repo |

### AWS Infrastructure (terraform/)
- **EC2**: t3.medium running Docker Compose stack
- **S3**: Tiered backup storage (daily 30d, monthly 6mo retention)
- **SNS**: Backup failure alerts
- **VPC**: Isolated network with public subnet

### DefectDojo Stack (docker-compose.yml)
nginx → uwsgi (Django app) → postgres + valkey + celery workers

## Key File Locations

| Purpose | Location |
|---------|----------|
| Product types config | `docker/extra_fixtures/extra_001_product_types.json` |
| Products config | `docker/extra_fixtures/extra_002_products.json` |
| DefectDojo settings | `docker/extra_settings/local_settings.py` |
| EC2 bootstrap | `terraform/user-data.sh` |
| Backup scripts | `scripts/backup.sh`, `scripts/backup-verify.sh` |
| E2E tests | `tests/e2e/*.spec.ts` |
| Smoke tests | `tests/smoke/*.spec.ts` |

## Required Secrets

**Organization level** (for reusable workflows):
- `DEFECTDOJO_URL` - https://infosec-scanning.learningtapestry.com
- `DEFECTDOJO_TOKEN` - API token for scan uploads

**Repository level** (for deployments):
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` - Terraform
- `EC2_SSH_PRIVATE_KEY`, `EC2_ELASTIC_IP` - App deployment
- `EIP_ALLOCATION_ID` - Terraform EIP management

## Production Access

```bash
# SSH to production
ssh -i ~/.ssh/infosec-key.pem ec2-user@54.86.136.184

# On server
cd /opt/defectdojo/repo && docker compose logs -f
sudo /opt/defectdojo/backup.sh           # Manual backup
sudo /opt/defectdojo/backup-verify.sh    # Test backup restore
sudo /opt/defectdojo/restart.sh          # Manual restart
```

## Scheduled Maintenance

**Daily restart at 10:00 UTC (2am Pacific PST / 3am PDT)**

The Docker stack is restarted daily to ensure a clean state and prevent Docker networking issues (DNS resolution failures between containers).

| Time (UTC) | Task | Notes |
|------------|------|-------|
| 00:00, 12:00 | Certbot renewal | SSL certificate check |
| 03:00 | Database backup | Uploads to S3 |
| 05:00 | Backup verification | Restore test |
| **10:00** | **Stack restart** | **~60 sec downtime** |

**DO NOT schedule cron jobs between 10:00-10:02 UTC** - the stack is restarting during this window.

## Adding New Products

Edit `docker/extra_fixtures/extra_002_products.json` (use pk 1000+):
```json
{
  "fields": {
    "name": "my-new-project",
    "description": "Project description",
    "prod_type": 100,
    "business_criticality": "high"
  },
  "model": "dojo.product",
  "pk": 1003
}
```
Then rebuild and load: `docker compose build uwsgi && docker compose up -d`
