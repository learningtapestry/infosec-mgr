# CLAUDE.md - AI Assistant Instructions for infosec-mgr

This repository is the central security infrastructure for the learningtapestry organization. It contains:
1. **DefectDojo** - Vulnerability aggregation and management
2. **Reusable GitHub Workflows** - Centralized scan configurations that all repos can use

## Project Overview

Security vulnerability management system for a ~20 person software engineering company managing 15-20 projects. All configuration is managed through files, not the UI.

## Critical: Config-as-Code Principles

**MANDATORY: All configuration must be managed through files, not the UI.**

When asked to configure anything, you MUST create/modify files rather than provide UI instructions.

## Repository Structure

```
infosec-mgr/
├── .github/
│   └── workflows/
│       ├── semgrep.yml              # Reusable: Semgrep SAST scanning
│       ├── trivy.yml                # Reusable: Container/dependency scanning
│       ├── full-security-scan.yml   # Reusable: All scans combined
│       └── self-scan.yml            # Scans THIS repo (dogfooding)
│
├── docker/
│   └── extra_fixtures/              # DefectDojo config-as-code
│       ├── extra_001_product_types.json
│       └── extra_002_products.json
│
├── scripts/
│   ├── setup-via-api.sh             # Initial API setup
│   └── import-scan.sh               # Manual scan import
│
├── scans/                           # Local scan result storage
├── docker-compose.yml               # DefectDojo deployment
├── CLAUDE.md                        # This file
└── README.md                        # Project documentation
```

## Reusable Workflows

### How Other Repos Use Our Workflows

Any repo in the org can use our centralized scan workflows with minimal config:

```yaml
# In any repo: .github/workflows/security.yml
name: Security
on: [push, pull_request]
jobs:
  scan:
    uses: learningtapestry/infosec-mgr/.github/workflows/semgrep.yml@main
    secrets: inherit
```

### When Modifying Workflows

1. Changes affect ALL repos using the workflow
2. Test changes thoroughly before merging to main
3. Consider versioning with tags for breaking changes
4. Update this CLAUDE.md if adding new workflows

### Available Workflows

| Workflow | Purpose | Called With |
|----------|---------|-------------|
| `semgrep.yml` | Static analysis (SAST) | `uses: learningtapestry/infosec-mgr/.github/workflows/semgrep.yml@main` |
| `trivy.yml` | Container/filesystem scanning | `uses: learningtapestry/infosec-mgr/.github/workflows/trivy.yml@main` |
| `full-security-scan.yml` | All scans combined | `uses: learningtapestry/infosec-mgr/.github/workflows/full-security-scan.yml@main` |

## DefectDojo Configuration

### Configuration File Locations

| What | Where | Format |
|------|-------|--------|
| Product Types | `docker/extra_fixtures/extra_001_product_types.json` | Django fixture JSON |
| Products | `docker/extra_fixtures/extra_002_products.json` | Django fixture JSON |
| New fixtures | `docker/extra_fixtures/extra_NNN_*.json` | Numbered, sorted order |
| Environment config | `docker-compose.override.yml` | DD_* environment variables |

### Adding New Products

1. Edit `docker/extra_fixtures/extra_002_products.json`
2. Add new product entry with unique pk (use 1000+ range)
3. Rebuild: `docker compose build uwsgi`
4. Restart: `docker compose up -d`
5. Load fixtures: `docker compose exec uwsgi python manage.py loaddata extra_002_products`

Example:
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

## Running DefectDojo Locally

```bash
docker compose up -d              # Start
docker compose logs -f            # View logs
docker compose down               # Stop
```

## API Access

- **Swagger UI**: http://localhost:8080/api/v2/oa3/swagger-ui/
- **Get API Token**: http://localhost:8080/api/key-v2

## Do NOT Use the UI For

- Creating products or product types (use fixtures)
- Importing scans (use API/workflows)
- System configuration (use environment variables)

The UI is acceptable for:
- Viewing and triaging findings
- Adding comments/notes to findings
- Manual verification of vulnerabilities
- Generating reports

## Organization Secrets Required

These must be set at the org level for workflows to function:

| Secret | Purpose |
|--------|---------|
| `DEFECTDOJO_URL` | URL of DefectDojo instance |
| `DEFECTDOJO_TOKEN` | API token for authentication |

## Production Deployment

1. Change `DD_SECRET_KEY` and `DD_CREDENTIAL_AES_256_KEY`
2. Set `DD_DEBUG=False`
3. Configure external PostgreSQL
4. Set proper `DD_ALLOWED_HOSTS`
5. Enable HTTPS
