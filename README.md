# SpectreHub Action

[![ANCC](https://img.shields.io/badge/ANCC-compliant-brightgreen)](https://ancc.dev)

GitHub Action that runs [SpectreHub](https://github.com/ppiankov/spectrehub) infrastructure audits in CI/CD pipelines.

## What This Is

Composite GitHub Action that installs SpectreHub and spectre tool binaries, discovers configured infrastructure targets, runs audits, and reports results as PR comments.

## What This Is NOT

- Not a hosted service — runs on your GitHub Actions runners
- Not a replacement for individual spectre tools — orchestrates them
- Not a monitoring solution — runs on-demand in CI

## Quick Start

```yaml
- name: SpectreHub Audit
  uses: ppiankov/spectrehub-action@v1
  with:
    threshold: 50
```

## Usage

### Basic

```yaml
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: SpectreHub Audit
        uses: ppiankov/spectrehub-action@v1
        with:
          threshold: 50
```

### With specific tools

```yaml
      - name: SpectreHub Audit
        uses: ppiankov/spectrehub-action@v1
        with:
          tools: 'vaultspectre,pgspectre'
          threshold: 25
          format: json
```

### With outputs

```yaml
      - name: SpectreHub Audit
        id: audit
        uses: ppiankov/spectrehub-action@v1

      - name: Check results
        run: |
          echo "Issues: ${{ steps.audit.outputs.total-issues }}"
          echo "Health: ${{ steps.audit.outputs.health-level }}"
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `tools` | Comma-separated tools to install, or `auto` for all | `auto` |
| `spectrehub-version` | SpectreHub version (e.g. `v0.2.0` or `latest`) | `latest` |
| `threshold` | Fail if issues exceed this number (0 = disabled) | `0` |
| `format` | Output format: `text`, `json`, or `both` | `text` |
| `comment` | Post results as PR comment | `true` |
| `license-key` | License key for paid tier | `` |

## Outputs

| Output | Description |
|--------|-------------|
| `total-issues` | Total issues found |
| `health-score` | Health score (0-100) |
| `health-level` | Level: excellent, good, warning, critical, severe |
| `tools-run` | Number of tools executed |
| `report-json` | Path to JSON report file |

## Free vs Paid

| Feature | Free | Paid |
|---------|------|------|
| Infrastructure targets | Up to 3 | Unlimited |
| PR comment | Summary table | Summary + trends |
| Trend tracking | No | Yes (via API) |
| Policy-as-code | No | Yes |

Set `SPECTREHUB_LICENSE_KEY` as a repository secret to unlock paid features.

## Prerequisites

Configure infrastructure credentials as repository secrets:

- **Vault**: `VAULT_ADDR`, `VAULT_TOKEN`
- **AWS S3**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
- **PostgreSQL**: `PGSPECTRE_DB_URL` or `DATABASE_URL`
- **MongoDB**: `MONGODB_URI`
- **Kafka**: requires config file (`.kafkaspectre.yaml`)
- **ClickHouse**: requires config file (`.clickspectre.yaml`)

## License

MIT
