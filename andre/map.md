# Project Map — Open-Source Data Platform (Lakehouse on Kubernetes)

GitOps data platform: local `kind` cluster → AWS EKS (`data-platform-eks`, us-east-2), managed by ArgoCD.

```
Airbyte → s3://bronze (raw Parquet)
             ↓
Airflow → Trino (hive_bronze) → dbt → s3://warehouse (Iceberg: staging / silver / gold)
             ↓
         API (FastAPI + DuckDB, reads gold)      Metabase (via Trino)
Cross-cutting: Prometheus/Grafana (observability), OpenMetadata (catalog + lineage)
```

---

## Top level

| Path | What it is |
|---|---|
| `CLAUDE.md` | Project rules, closed architecture decisions, spec status |
| `README.md` | Setup/usage guide (incl. AIStor `MINIO_LICENSE` handling) |
| `Makefile` | Entry point for all ops (see [Makefile targets](#makefile-targets)) |
| `specs/` | Formal specs (Specify) + `.plan.md` (Plan) for SPEC-001…017 |
| `.claude/commands/` | Slash commands: `plan-spec`, `implement-spec`, `validate-spec` |
| `.github/workflows/` | CI/CD (GitHub Actions) |
| `infra/` | Terraform (AWS) + kind cluster config |
| `bootstrap/` | One-time cluster bootstrap (ArgoCD, namespaces, ECR auth, AIStor operator) |
| `apps/` | ArgoCD `Application` manifests per environment |
| `charts/` | Our own manifests / Helm values / Kustomize overlays per component |
| `code/` | First-party code (dbt, Airflow DAGs, API, Metabase image) |
| `scripts/` | Helper shell scripts used by Makefile / CI |
| `docs/runbooks/` | Manual setup runbooks |

---

## Infrastructure — `infra/`

| Path | Contents |
|---|---|
| `infra/clusters/local/kind-config.yaml` | Local kind cluster definition |
| `infra/terraform/envs/shared/` | Shared state: ECR repos (`ecr.tf`) |
| `infra/terraform/envs/eks/` | EKS environment (`main.tf`, `variables.tf`, `terraform.tfvars`, `backend.tf`, `outputs.tf`) |
| `infra/terraform/modules/vpc/` | VPC module |
| `infra/terraform/modules/eks/` | EKS cluster + node group (4× t3.large, K8s 1.32) |
| `infra/terraform/modules/iam-irsa/` | IAM roles for service accounts |
| `infra/terraform/modules/ecr/` | ECR repository module (one repo per service) |

## Bootstrap — `bootstrap/`

| Path | Contents |
|---|---|
| `bootstrap/namespaces.yaml` | Namespaces (`data-platform`, `ingestion`, `query-engine`, `observability`, `governance`, …) |
| `bootstrap/argocd/install-values-{local,eks}.yaml` | ArgoCD Helm values per env |
| `bootstrap/ecr-auth/local-ecr-secret.sh` | ECR pull secret for kind |
| `bootstrap/minio-aistor-operator/` | AIStor operator values + `ensure-license-secret.sh` (license from env, never committed) |

---

## GitOps — `apps/`

App-of-apps pattern: `apps/{local,eks}/app-of-apps.yaml` points at its own folder; each `*-app.yaml` is one ArgoCD Application.

| Component | Namespace | Source (EKS) | Our config lives in |
|---|---|---|---|
| Airbyte | `ingestion` | Helm `airbyte` 1.7.8 | `charts/airbyte-{local,eks}/` (prereqs) + inline values |
| Airflow (v3, KubernetesExecutor) | `ingestion` | Helm `airflow` 1.22.0 | **inline values** in `apps/*/airflow-app.yaml` |
| Trino 480 | `query-engine` | Helm `trino` 0.31.0 | **inline values + catalogs** (`iceberg`, `hive_bronze`, `postgres_source`) in `apps/*/trino-app.yaml` |
| Hive Metastore | `data-platform` | Git | `charts/hive-metastore/manifests/` (local), `charts/hive-metastore-eks/` (EKS) |
| MinIO / AIStor ObjectStore | `data-platform` | Helm `aistor-objectstore` 1.1.0 | inline values; buckets via `charts/minio-{local,eks}-setup/` |
| Postgres (one per component) + Iceberg JDBC catalog init | various | Git | `charts/postgres-{local,eks}/` |
| API service | `data-platform` | Git | `code/api-service/k8s/` (local), `code/api-service/k8s-eks/` (EKS) |
| Metabase | `data-platform` | Git | `charts/metabase/`, `charts/metabase-eks/` |
| kube-prometheus-stack | `observability` | Helm 65.1.0 + Git | `charts/observability/values-{local,eks}.yaml` |
| ServiceMonitors + dashboards | `observability` | Git | `charts/observability/servicemonitors/` |
| OpenMetadata (+ deps, OpenSearch) | `governance` | Helm 1.5.4 / OpenSearch 2.21.0 + Git | `charts/openmetadata/`, `charts/openmetadata-secrets/` |
| NFS server + provisioner (EKS only) | `data-platform` | Git + Helm | `charts/nfs-server/` |
| metrics-server (EKS only) | `kube-system` | Helm 3.14.0 | inline |

> ⚠️ Every Git-sourced Application (and `README.md`, `SPEC-015` plan) still uses `repoURL: https://github.com/cicerojmm/treinamentoDataHandsLakehouseOpenSourceAWS`. The git `origin` was removed on 2026-10-05, so these must be updated to the new repo URL before ArgoCD can sync from it. Find them with: `grep -rl cicerojmm apps README.md specs`.

---

## Component configs — `charts/`

| Path | Purpose |
|---|---|
| `airbyte-local/`, `airbyte-eks/` | Kustomize prereqs for Airbyte (secrets, storage config) |
| `hive-metastore/manifests/` | Local HMS: configmap, deployment, service, schema-init job |
| `hive-metastore-eks/` | EKS HMS (separate so the endpoint points to EKS MinIO) |
| `metabase/`, `metabase-eks/` | Metabase deployment + its dedicated Postgres |
| `minio-local-setup/`, `minio-eks-setup/` | Bucket creation jobs (`bronze`, `warehouse`, `silver`, `gold`, `airbyte-storage`); EKS also has an OpenMetadata policy (`openmetadata-bronze.json`) |
| `postgres-local/`, `postgres-eks/` | Dedicated Postgres per component (Airflow, Airbyte, HMS, OpenMetadata…), `iceberg-catalog-init-job.yaml`, sample source DB + `sample-data/` SQL (MovieLens on EKS, e-commerce locally) |
| `nfs-server/` | In-cluster NFS server (EKS RWX storage) |
| `observability/` | Prometheus/Grafana values + ServiceMonitors (Airflow via statsd-exporter, MinIO, Trino) + `dashboards/airflow.json` |
| `openmetadata/` | OpenMetadata + OpenSearch values, local Postgres |
| `openmetadata-secrets/` | Airflow credentials for OpenMetadata ingestion |

---

## First-party code — `code/`

### `code/dbt-project/` (dbt-trino, MovieLens)
| Path | Contents |
|---|---|
| `dbt_project.yml`, `packages.yml` | Project config |
| `profiles/profiles.yml` | Trino connection |
| `macros/generate_schema_name.sql` | Schema naming override |
| `models/sources.yml` | Bronze sources (`hive_bronze`) |
| `models/staging/` | `stg_movies`, `stg_ratings`, `stg_tags`, `stg_links` (views) |
| `models/silver/` | `silver_movies`, `silver_ratings`, `silver_tags`, `silver_links` |
| `models/gold/` | `gold_movie_analytics`, `gold_genre_analytics`, `gold_user_behavior`, `gold_temporal_trends`, `gold_movie_recommendations`, `gold_external_links` |
| `Dockerfile` | dbt image (packaged together with the DAGs) |

### `code/airflow-dags/`
| Path | Contents |
|---|---|
| `dags/dbt_movielens_dag.py` | Main DAG: creates external tables in `hive_bronze`, runs dbt via Cosmos |
| `dags/example_healthcheck_dag.py`, `dags/hello_world_dag.py` | Smoke-test DAGs |
| `Dockerfile`, `build.sh`, `requirements.txt` | DAGs baked into the Airflow image (no git-sync) |

### `code/api-service/` (FastAPI + DuckDB, `X-API-Key` auth)
| Path | Contents |
|---|---|
| `app/main.py` | App entry point |
| `app/routers/movies.py` | Endpoints over gold tables |
| `app/db.py`, `app/config.py`, `app/auth.py` | DuckDB/Iceberg access, settings, API key check |
| `tests/test_api.py` | pytest suite (CI gate) |
| `k8s/`, `k8s-eks/` | Kubernetes manifests (local / EKS overlay with image SHA) |

### `code/metabase/`
Custom Metabase image (`Dockerfile`, `build.sh`), e.g. with the Trino driver.

> Note: `spark-jobs` exists as an ECR repo per the architecture decisions, but there is no `code/spark-jobs/` directory yet.

---

## CI/CD — `.github/workflows/`

| Workflow | Trigger | Does |
|---|---|---|
| `_build-push-bump.yml` | reusable (`workflow_call`) | Build → push to ECR (Git SHA tag) → bump the SHA in manifests |
| `airflow-dags.yml` | push to `code/airflow-dags/**` or `code/dbt-project/**` | Airflow + dbt image |
| `api-service.yml` | push to `code/api-service/**` (excluding `k8s-eks/`) | Tests + API image |
| `metabase.yml` | push to `code/metabase/**` | Metabase image |
| `infra-bootstrap.yml` | manual | Terraform → images → ArgoCD on EKS (end-to-end) |

---

## Makefile targets

| Env | Targets |
|---|---|
| Local | `bootstrap-local`, `destroy-local`, `run-local`, `argocd-password`, `argocd-ui` |
| EKS | `check-prereqs-eks`, `plan-eks`, `terraform-apply-eks`, `images-eks`, `deploy-argocd-eks`, `bootstrap-eks` (all-in-one), `wait-eks`, `verify-eks`, `urls-eks`, `argocd-password-eks`, `argocd-ui-eks`, `destroy-eks` |

## Scripts — `scripts/`

| Script | Purpose |
|---|---|
| `ec2-bootstrap.sh` | Prepare an EC2 host to run the local (kind) setup |
| `run-local.sh` | Bring up the local platform |
| `ensure-images-eks.sh` | Make sure the referenced SHA images exist in ECR |
| `wait-argocd-healthy.sh` | Wait until all Applications are Synced/Healthy |
| `verify-minio-buckets.sh` | Check the expected buckets exist |
| `teardown-argocd-apps.sh` | Delete Applications cleanly before destroy (frees ELBs/PVCs) |

## Runbooks — `docs/runbooks/`

`airbyte-eks-setup.md`, `cicd-setup.md`, `metabase-trino-setup.md`, `openmetadata-connectors-setup.md`.

---

## Specs — `specs/`

| Spec | Topic |
|---|---|
| 001 | Local bootstrap + ArgoCD |
| 002 | ECR |
| 003 | MinIO / AIStor |
| 004 | Hive Metastore |
| 005 | Airflow |
| 006 | Airbyte |
| 007 | Trino |
| 008 | dbt |
| 009 | Main DAG |
| 010 | API |
| 011 | Metabase |
| 012 | Observability |
| 013 | OpenMetadata |
| 014 | Terraform EKS |
| 015 | EKS overlays |
| 016 | CI/CD (images) |
| 017 | CI/CD (infra/Terraform) |

All 17 specs are implemented. Plans (`.plan.md`) exist for 009–017. `TEMPLATE-spec.md`, mentioned in `CLAUDE.md`, is not in the folder.
