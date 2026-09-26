# BikeMart Data Warehouse — Databricks + CI/CD

[![CI - validate and test (dev)](https://github.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/actions/workflows/ci.yml/badge.svg)](https://github.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/actions/workflows/ci.yml)
[![CD - deploy and run (prod)](https://github.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/actions/workflows/cd.yml/badge.svg)](https://github.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/actions/workflows/cd.yml)

> Replace `YOUR_GITHUB_USERNAME/YOUR_REPO_NAME` in both badge URLs above with
> your actual `owner/repo` once this is pushed to GitHub — a badge is just an
> image URL GitHub generates per workflow file, so it starts working the
> moment the workflow has run at least once (it shows "no status" before
> that). No extra setup, secret, or config is needed beyond pushing the repo.

A medallion-architecture (Bronze → Silver → Gold) data warehouse for a bike
retailer, built on Databricks Free Edition and deployed with Databricks
Asset Bundles + GitHub Actions.

This is a Databricks/Delta port of an earlier MySQL version of the same
project (same source data, same cleaning rules, same snowflake schema) —
built to show the same data modeling work running on a modern lakehouse
stack with CI/CD, rather than a hand-run SQL script.

## Architecture

```
Raw CSVs (Unity Catalog Volume)
        │
        ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│    bronze     │ ──▶ │    silver     │ ──▶ │     gold      │
│  raw, as-is   │     │  cleaned,     │     │  snowflake    │
│  ingestion    │     │  standardized │     │  schema       │
└───────────────┘     └───────────────┘     └───────────────┘
                                                     │
                                                     ▼
                                          04_validate.sql
                                    (fails the job on any
                                     referential-integrity
                                     or key-uniqueness break)
```

Gold is a snowflake schema: `dim_customers` and `dim_products` each
normalize one level further into their own outrigger dimensions,
`dim_countries` and `dim_categories`, rather than flattening
country/category directly into the core dimensions. `fact_sales` sits at
the center, referencing both core dimensions.

## Repo layout

```
databricks.yml              # Asset Bundle root config (dev/prod targets)
resources/
  jobs.yml                  # the 4-task job: bronze → silver → gold → validate
src/
  bronze/01_bronze.sql       # raw ingestion from a Unity Catalog Volume
  silver/02_silver.sql       # cleaning & standardization
  gold/03_gold.sql           # snowflake schema build
  validation/04_validate.sql # automated data-quality gate
.github/workflows/
  ci.yml                    # PR: validate bundle, deploy + run against "dev"
  cd.yml                    # push to main: deploy + run against "prod"
```

## What's been tested vs. what hasn't

Being upfront about this, since it matters for a portfolio piece:

- **The SQL transformation logic (Silver and Gold)** was validated locally
  with PySpark against the real 6 source CSVs before being ported here —
  row counts, deduplication behavior, cleaned values, surrogate key
  uniqueness, and referential integrity all matched the previously-tested
  MySQL version exactly (down to identical revenue figures in sample
  queries). The `raise_error()` data-quality gate in `04_validate.sql` was
  also tested directly, in both the pass case and a deliberately-injected
  failure case.
- **Bronze ingestion (`read_files()` from a Volume) and the Databricks
  Asset Bundle / GitHub Actions configuration have not been run against a
  live Databricks workspace** — there's no Databricks connectivity
  available in the environment this was built in. The bundle and workflow
  YAML follow Databricks' current official documentation and examples as
  closely as possible, but you should run `databricks bundle validate`
  yourself before your first real deploy, and treat the first pipeline run
  as the actual integration test.

## One-time setup

1. **Create a Databricks Free Edition account** at
   [databricks.com](https://www.databricks.com) if you don't have one.
2. **Upload the 6 source CSVs** to a Unity Catalog Volume at
   `/Volumes/bikemart/bronze/raw_files/` (Catalog Explorer → create the
   `bikemart` catalog and `bronze` schema if needed → Volumes → create
   `raw_files` → Upload). `01_bronze.sql` also creates the catalog/schema/
   volume itself if they don't exist, but the volume needs to exist before
   you upload into it.
3. **Note your serverless SQL warehouse ID** (Compute → SQL Warehouses →
   click your warehouse → the ID is in the URL / on the details page).
4. **Generate a personal access token**: User Settings → Developer →
   Access tokens → Generate new token.
5. **Configure the GitHub repo**:
   - Variable `DATABRICKS_HOST` = your workspace URL
   - Secret `DATABRICKS_TOKEN` = the PAT from step 4
   - Secret `DATABRICKS_WAREHOUSE_ID` = the warehouse ID from step 3
6. **Push to a `main` branch** (or open a PR against it) to trigger the
   workflows, or run locally first:
   ```bash
   pip install databricks-cli  # or: curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
   databricks configure --token
   databricks bundle validate --target dev
   databricks bundle deploy --target dev
   databricks bundle run bikemart_medallion_pipeline --target dev
   ```

## CI/CD flow

- **Pull request → `main`**: `ci.yml` validates the bundle, then deploys
  and runs the full pipeline against the `dev` target. A broken
  transformation or a referential-integrity failure in `04_validate.sql`
  fails the check directly on the PR.
- **Merge to `main`**: `cd.yml` deploys and runs the same pipeline against
  the `prod` target.

Since Free Edition provides a single workspace, `dev` and `prod` here are
two Asset Bundle *targets* against that one workspace (different job
names/paths) rather than two physically separate environments — the point
is demonstrating the promotion pattern, which is exactly what carries over
unchanged if you later move to a paid workspace with truly separate
dev/prod workspaces.

## Design notes carried over from the MySQL version

- Surrogate keys generated via `ROW_NUMBER()`, never source natural keys.
- A source-of-truth hierarchy for customer gender: CRM is master, ERP is
  the fallback, `'n/a'` if both are missing.
- `dim_products` filtered to active/current records only, avoiding SCD
  duplicates.
- Reserved "Unknown" member rows (`key = 0`) in both outrigger dimensions,
  distinct from `'n/a'` (a legitimate cleaned value) — catches a genuine
  gap in the source data: 7 active products with no matching category in
  the ERP category reference table.
