# infosec-mgr

Central security infrastructure for learningtapestry - vulnerability management and reusable scan workflows.

## What This Repo Provides

1. **DefectDojo** - Self-hosted vulnerability aggregation and management
2. **Reusable GitHub Workflows** - Centralized scan configs that all org repos can use

## Quick Start

### For Project Repos (Use Our Scan Workflows)

Add this to any repo to get security scanning with zero configuration:

```yaml
# .github/workflows/security.yml
name: Security
on: [push, pull_request]

jobs:
  scan:
    uses: learningtapestry/infosec-mgr/.github/workflows/semgrep.yml@main
    secrets: inherit
```

That's it. Results flow to DefectDojo automatically.

### For DefectDojo (Local Development)

```bash
git clone https://github.com/learningtapestry/infosec-mgr.git
cd infosec-mgr
docker compose up -d

# Get admin password
docker compose logs initializer | grep "Admin password"
```

- **Web UI**: http://localhost:8080
- **API Docs**: http://localhost:8080/api/v2/oa3/swagger-ui/

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  learningtapestry/infosec-mgr (this repo)                          │
│                                                                     │
│  ┌─────────────────────────┐  ┌─────────────────────────────────┐  │
│  │  Reusable Workflows     │  │  DefectDojo                     │  │
│  │  .github/workflows/     │  │  (Aggregation & Management)     │  │
│  │  ├── semgrep.yml       │  │                                 │  │
│  │  ├── trivy.yml         │  │  - Collects all scan results    │  │
│  │  └── full-scan.yml     │  │  - Deduplicates findings        │  │
│  └────────────┬────────────┘  │  - Tracks remediation           │  │
│               │               │  - Generates reports            │  │
│               │               └─────────────────────────────────┘  │
└───────────────┼─────────────────────────────────────────────────────┘
                │
    ┌───────────┴───────────┐
    │  Other repos call:    │
    │  uses: learningtapestry/infosec-mgr/.github/workflows/...     │
    └───────────────────────┘
                │
    ┌───────────┼───────────┬───────────────────┐
    ▼           ▼           ▼                   ▼
┌───────┐  ┌───────┐  ┌───────────┐  ┌─────────────────┐
│ app-1 │  │ app-2 │  │ frontend  │  │ other-projects  │
│       │  │       │  │           │  │                 │
│ 6 lines of YAML │  │ 6 lines   │  │ 6 lines         │
└───────┘  └───────┘  └───────────┘  └─────────────────┘
```

## Available Reusable Workflows

| Workflow | Purpose | Use Case |
|----------|---------|----------|
| `semgrep.yml` | Static analysis (SAST) | Find code vulnerabilities |
| `trivy.yml` | Container & dependency scanning | Find vulnerable packages |
| `full-security-scan.yml` | All scans combined | Comprehensive security check |

### Key Behaviors

- **Non-blocking**: Scans run independently from your CI/CD pipeline - they won't fail your builds
- **Deduplication**: Uses DefectDojo's reimport API - only NEW findings are reported, existing issues aren't duplicated
- **Auto-creates context**: Products and engagements are created automatically if they don't exist
- **Dogfooding**: This repo scans itself using these same workflows (see `.github/workflows/self-scan.yml`)

### Using in Your Repo

**Minimal (just Semgrep):**
```yaml
name: Security
on: [push]
jobs:
  scan:
    uses: learningtapestry/infosec-mgr/.github/workflows/semgrep.yml@main
    secrets: inherit
```

**Full scan (all tools):**
```yaml
name: Security
on: [push]
jobs:
  scan:
    uses: learningtapestry/infosec-mgr/.github/workflows/full-security-scan.yml@main
    secrets: inherit
```

**With custom product name:**
```yaml
name: Security
on: [push]
jobs:
  scan:
    uses: learningtapestry/infosec-mgr/.github/workflows/semgrep.yml@main
    with:
      product_name: "My Custom Product Name"
    secrets: inherit
```

## Organization Setup (One-Time)

Set these secrets at the org level (Settings → Secrets → Actions):

| Secret | Value |
|--------|-------|
| `DEFECTDOJO_URL` | URL of your DefectDojo instance |
| `DEFECTDOJO_TOKEN` | API token from DefectDojo |

## Project Structure

```
infosec-mgr/
├── .github/
│   └── workflows/
│       ├── semgrep.yml              # Reusable: SAST scanning
│       ├── trivy.yml                # Reusable: Container scanning
│       ├── full-security-scan.yml   # Reusable: All scans
│       └── self-scan.yml            # Dogfood: scan this repo
│
├── docker/
│   └── extra_fixtures/              # DefectDojo products/config
│       ├── extra_001_product_types.json
│       └── extra_002_products.json
│
├── scripts/
│   ├── setup-via-api.sh             # API setup helper
│   └── import-scan.sh               # Manual import script
│
├── docker-compose.yml               # DefectDojo deployment
├── CLAUDE.md                        # AI assistant instructions
└── README.md                        # This file
```

## DefectDojo Config-as-Code

All DefectDojo configuration is managed through files:

| Configuration | Location |
|---------------|----------|
| Product Types | `docker/extra_fixtures/extra_001_product_types.json` |
| Products | `docker/extra_fixtures/extra_002_products.json` |
| Settings | `docker-compose.override.yml` (DD_* env vars) |

### Adding a New Product

1. Edit `docker/extra_fixtures/extra_002_products.json`
2. Rebuild: `docker compose build uwsgi && docker compose up -d`
3. Load: `docker compose exec uwsgi python manage.py loaddata extra_002_products`

## Commands Reference

```bash
# DefectDojo
docker compose up -d                    # Start
docker compose down                     # Stop
docker compose logs -f uwsgi            # View logs

# After fixture changes
docker compose build uwsgi && docker compose up -d
docker compose exec uwsgi python manage.py loaddata extra_002_products
```

## Production Deployment

For production:
1. Change `DD_SECRET_KEY` and `DD_CREDENTIAL_AES_256_KEY`
2. Use external PostgreSQL (RDS, CloudSQL)
3. Enable HTTPS
4. Set `DD_ALLOWED_HOSTS` properly

## License

Based on [DefectDojo](https://github.com/DefectDojo/django-DefectDojo), licensed under BSD-3-Clause.
