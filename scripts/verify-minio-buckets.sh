#!/bin/bash
# Confere se os buckets definidos em charts/minio-eks-setup/kustomization.yaml
# existem no MinIO do EKS. Uso: verify-minio-buckets.sh [timeout_s]
#
# Usa aws s3 (nao mc): mc pode nem existir dentro da imagem
# quay.io/minio/aistor/minio (linhagem diferente da antiga
# quay.io/minio/minio que costumava embutir o cliente), e credenciais
# fixas antigas (minio/minio123) nao existem mais desde a migracao pro
# aistor-objectstore-operator. Roda um pod efemero com amazon/aws-cli,
# mesma imagem ja usada pelo Job real de criacao dos buckets.
set -euo pipefail

TIMEOUT_SECONDS="${1:-300}"
KUBECTL="kubectl"
if [ -n "${KUBE_CONTEXT:-}" ]; then KUBECTL="kubectl --context=${KUBE_CONTEXT}"; fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected=$(grep -oP '(?<=- buckets=).*' "$ROOT_DIR/charts/minio-eks-setup/kustomization.yaml")
if [ -z "$expected" ]; then
  echo "ERRO: lista de buckets nao encontrada em charts/minio-eks-setup/kustomization.yaml" >&2
  exit 1
fi

ACCESS_KEY=$($KUBECTL get secret minio-eks-env-configuration -n data-platform -o jsonpath='{.data.config\.env}' \
  | base64 -d | grep MINIO_ROOT_USER | cut -d'"' -f2)
SECRET_KEY=$($KUBECTL get secret minio-eks-env-configuration -n data-platform -o jsonpath='{.data.config\.env}' \
  | base64 -d | grep MINIO_ROOT_PASSWORD | cut -d'"' -f2)

elapsed=0
while true; do
  $KUBECTL delete pod verify-minio-buckets -n data-platform --ignore-not-found --grace-period=0 >/dev/null 2>&1 || true
  existing=$($KUBECTL run verify-minio-buckets -n data-platform --restart=Never --rm -i --quiet \
    --image=amazon/aws-cli:latest \
    --overrides="{\"spec\":{\"containers\":[{\"name\":\"verify-minio-buckets\",\"image\":\"amazon/aws-cli:latest\",\"command\":[\"aws\",\"--endpoint-url\",\"http://minio-eks-hl.data-platform.svc.cluster.local:9000\",\"s3\",\"ls\"],\"env\":[{\"name\":\"AWS_ACCESS_KEY_ID\",\"value\":\"${ACCESS_KEY}\"},{\"name\":\"AWS_SECRET_ACCESS_KEY\",\"value\":\"${SECRET_KEY}\"},{\"name\":\"AWS_DEFAULT_REGION\",\"value\":\"us-east-1\"}]}]}}" \
    2>/dev/null | awk '{print $NF}' || true)
  missing=""
  for b in $expected; do
    echo "$existing" | grep -qx "$b" || missing="$missing $b"
  done
  if [ -z "$missing" ]; then
    echo "Buckets do MinIO OK: $expected"
    exit 0
  fi
  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    echo "ERRO: buckets ausentes no MinIO:$missing" >&2
    echo "O Job minio-create-buckets (Application minio-eks-setup) nao rodou ou falhou." >&2
    echo "Verifique: $KUBECTL get application minio-eks-setup -n argocd -o jsonpath='{.status.operationState}'" >&2
    exit 1
  fi
  echo "[${elapsed}s] aguardando buckets:$missing"
  sleep 10
  elapsed=$((elapsed + 10))
done
