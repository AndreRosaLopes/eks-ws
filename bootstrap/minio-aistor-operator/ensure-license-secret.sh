#!/bin/bash
# Garante que o Secret de licenca do AIStor (minio.license) existe no
# cluster, sem nunca commitar o JWT no Git.
#
# Prioridade:
#   1. Se a variavel MINIO_LICENSE estiver setada, cria/atualiza o Secret
#      a partir dela (fonte: env var local, ou secrets.MINIO_LICENSE no
#      GitHub Actions).
#   2. Senao, se o Secret ja existir no cluster, reaproveita.
#   3. Senao, falha com instrucoes de como obter a licenca.
#
# Uso: bash ensure-license-secret.sh <secret-name> <namespace>
#      KUBE_CONTEXT=<contexto> bash ensure-license-secret.sh <secret-name> <namespace>
set -euo pipefail

SECRET_NAME="$1"
NAMESPACE="$2"

KUBECTL="kubectl"
if [ -n "${KUBE_CONTEXT:-}" ]; then KUBECTL="kubectl --context=${KUBE_CONTEXT}"; fi

if [ -n "${MINIO_LICENSE:-}" ]; then
  echo "Criando/atualizando Secret '${SECRET_NAME}' a partir de \$MINIO_LICENSE..."
  $KUBECTL create secret generic "$SECRET_NAME" -n "$NAMESPACE" \
    --from-literal=minio.license="$MINIO_LICENSE" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
  exit 0
fi

if $KUBECTL get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "Secret '${SECRET_NAME}' ja existe no cluster, reaproveitando."
  exit 0
fi

echo "ERRO: Secret '${SECRET_NAME}' nao existe no namespace '${NAMESPACE}' e a" >&2
echo "variavel MINIO_LICENSE nao esta setada." >&2
echo "" >&2
echo "Pegue uma licenca AIStor Free (single-node, gratuita) em https://subnet.min.io e:" >&2
echo "  1. export MINIO_LICENSE='<jwt-da-licenca>' no seu ~/.bashrc ou ~/.zshrc" >&2
echo "     (roda este script de novo depois), ou" >&2
echo "  2. crie o Secret manualmente:" >&2
echo "     ${KUBECTL} create secret generic ${SECRET_NAME} -n ${NAMESPACE} \\" >&2
echo "       --from-literal=minio.license='<jwt-da-licenca>'" >&2
exit 1
