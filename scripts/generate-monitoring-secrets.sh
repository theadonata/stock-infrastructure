#!/usr/bin/env bash
#
# generate-monitoring-secrets.sh — builds the two SealedSecrets the
# monitoring stack needs (Grafana admin login, Alertmanager's Discord
# webhook config) from real values in .env.local, instead of typing the
# kubeseal commands by hand each time.
#
# Unlike scripts/generate-secrets.sh, the output lands directly in
# charts/monitoring/templates/ (not a secrets/<env>/ directory) — the
# monitoring stack is a single-source Argo CD Application (see
# docs/adr/0003-observability-stack.md), so its SealedSecrets are part of
# the chart itself, not a second source.
#
# Requires:
#   - .env.local with GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD, and
#     DISCORD_WEBHOOK_URL set.
#   - kubeseal able to reach the cluster's Sealed Secrets controller, i.e.
#     terraform/environments/bootstrap must already be applied.
#
# The plaintext secret never touches disk — kubectl renders it to stdout
# (--dry-run=client, nothing sent to the cluster) and pipes straight into
# kubeseal; only the encrypted result is written to a file.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_LOCAL="$REPO_ROOT/.env.local"
OUT_DIR="$REPO_ROOT/charts/monitoring/templates"
NAMESPACE="monitoring"

usage() {
  cat <<'EOF'
Usage: ./scripts/generate-monitoring-secrets.sh

Reads GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD, and DISCORD_WEBHOOK_URL
from .env.local and writes
charts/monitoring/templates/{grafana-admin,alertmanager-config}-secret.sealed.yaml.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ ! -f "$ENV_LOCAL" ]; then
  echo "ERROR: $ENV_LOCAL not found." >&2
  exit 1
fi

# Load .env.local into the environment (only for this script's process).
set -a
# shellcheck disable=SC1090
source "$ENV_LOCAL"
set +a

if [ -z "${GRAFANA_ADMIN_USER:-}" ] || [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ] || [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "ERROR: GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD, and/or DISCORD_WEBHOOK_URL are missing or empty in $ENV_LOCAL" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "Generating $OUT_DIR/grafana-admin-secret.sealed.yaml for namespace $NAMESPACE..."

# userKey/passwordKey match kube-prometheus-stack's grafana.admin defaults
# (admin-user/admin-password) — see charts/monitoring/values.yaml.
kubectl create secret generic monitoring-grafana-admin \
  --namespace "$NAMESPACE" \
  --from-literal=admin-user="$GRAFANA_ADMIN_USER" \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
    --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
  > "$OUT_DIR/grafana-admin-secret.sealed.yaml"

echo "Generating $OUT_DIR/alertmanager-config-secret.sealed.yaml for namespace $NAMESPACE..."

# Key must be exactly "alertmanager.yaml" — that's what
# alertmanager.alertmanagerSpec.configSecret (values.yaml) expects the
# Prometheus Operator's Alertmanager CRD to find at that key. Built as a
# variable and fed to kubectl via /dev/stdin (not a temp file) so the
# webhook URL never touches disk in plaintext, same invariant as the
# grafana-admin secret above.
alertmanager_config="global:
  resolve_timeout: 5m
route:
  group_by: ['namespace', 'alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: discord
receivers:
  - name: discord
    discord_configs:
      - webhook_url: '$DISCORD_WEBHOOK_URL'
"

printf '%s' "$alertmanager_config" \
  | kubectl create secret generic monitoring-alertmanager-config \
    --namespace "$NAMESPACE" \
    --from-file=alertmanager.yaml=/dev/stdin \
    --dry-run=client -o yaml \
  | kubeseal --format yaml \
    --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
  > "$OUT_DIR/alertmanager-config-secret.sealed.yaml"

# Argo CD reads sync-wave from the SealedSecret's own metadata (the object
# it actually applies), not spec.template.metadata — kubeseal has no flag
# for the former, so set it as a post-processing step, same as
# scripts/generate-secrets.sh. Plain sync-wave (not a PreSync hook) is
# sufficient here since this Application is single-source — see
# docs/adr/0003-observability-stack.md and
# terraform/modules/argocd-application/main.tf's comment on why.
for f in grafana-admin-secret.sealed.yaml alertmanager-config-secret.sealed.yaml; do
  yq eval -i '.metadata.annotations."argocd.argoproj.io/sync-wave" = "-1"' "$OUT_DIR/$f"
done

echo "Wrote $OUT_DIR/{grafana-admin,alertmanager-config}-secret.sealed.yaml — safe to commit (ciphertext only)."
