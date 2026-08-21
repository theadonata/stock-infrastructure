#!/usr/bin/env bash
#
# generate-secrets.sh — builds secrets/<env>/backend-secrets.sealed.yaml
# from real password/JWT values in .env.local, instead of typing the
# kubeseal command from secrets/<env>/README.md by hand each time.
#
# Requires:
#   - .env.local with <ENV>_POSTGRES_PASSWORD and <ENV>_JWT_SECRET set
#     (ENV is DEV or STAGING, matching the argument below).
#   - kubeseal able to reach the cluster's Sealed Secrets controller, i.e.
#     terraform/environments/bootstrap must already be applied.
#
# The plaintext secret never touches disk — kubectl renders it to stdout
# (--dry-run=client, nothing sent to the cluster) and pipes straight into
# kubeseal; only the encrypted result is written to a file.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_LOCAL="$REPO_ROOT/.env.local"

usage() {
  cat <<'EOF'
Usage: ./scripts/generate-secrets.sh <dev|staging>

Reads <ENV>_POSTGRES_PASSWORD and <ENV>_JWT_SECRET from .env.local and
writes secrets/<env>/backend-secrets.sealed.yaml.
EOF
}

if [ $# -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
  exit 0
fi

env_name="$1"
case "$env_name" in
  dev|staging) ;;
  *)
    echo "ERROR: environment must be 'dev' or 'staging', got '$env_name'" >&2
    exit 1
    ;;
esac

if [ ! -f "$ENV_LOCAL" ]; then
  echo "ERROR: $ENV_LOCAL not found." >&2
  exit 1
fi

# Load .env.local into the environment (only for this script's process) so
# the vars below can be read with bash's indirect-expansion syntax.
set -a
# shellcheck disable=SC1090
source "$ENV_LOCAL"
set +a

var_prefix=$(printf '%s' "$env_name" | tr '[:lower:]' '[:upper:]')
postgres_password_var="${var_prefix}_POSTGRES_PASSWORD"
jwt_secret_var="${var_prefix}_JWT_SECRET"

postgres_password="${!postgres_password_var:-}"
jwt_secret="${!jwt_secret_var:-}"

if [ -z "$postgres_password" ] || [ -z "$jwt_secret" ]; then
  echo "ERROR: $postgres_password_var and/or $jwt_secret_var are missing or empty in $ENV_LOCAL" >&2
  exit 1
fi

namespace="stock-hpp-$env_name"
out_dir="$REPO_ROOT/secrets/$env_name"
mkdir -p "$out_dir"

echo "Generating $out_dir/backend-secrets.sealed.yaml for namespace $namespace..."

# --controller-name/--controller-namespace: kubeseal's own default
# ("sealed-secrets-controller" in "kube-system") assumes the chart's
# stock Helm release name — terraform/modules/sealed-secrets installs it
# as the "sealed-secrets" release in the "sealed-secrets" namespace, so
# the actual Service is named "sealed-secrets", not the default. Without
# these flags kubeseal fails with "services sealed-secrets-controller not
# found" even though the controller is running fine.
kubectl create secret generic stock-hpp-backend-secrets \
  --namespace "$namespace" \
  --from-literal=POSTGRES_USER=stock_hpp_user \
  --from-literal=POSTGRES_PASSWORD="$postgres_password" \
  --from-literal=POSTGRES_DB=stock_hpp_db \
  --from-literal=DATABASE_URL="postgresql+psycopg2://stock_hpp_user:${postgres_password}@stock-hpp-postgres:5432/stock_hpp_db" \
  --from-literal=JWT_SECRET="$jwt_secret" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
    --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
  > "$out_dir/backend-secrets.sealed.yaml"

# Argo CD reads its sync-wave from the SealedSecret resource's own metadata
# (the object Argo CD actually applies and orders), not the
# `spec.template.metadata` kubeseal writes for the Secret it unseals into
# later -- kubeseal has no flag for the former, so set it as a
# post-processing step here rather than by hand-editing the output file,
# or the next run of this script silently drops it again. Both the
# migrate Job and the Postgres StatefulSet (env: POSTGRES_USER/PASSWORD/DB)
# read from the Secret this SealedSecret decrypts to, so it must exist
# before either -- one wave earlier than postgres-*.yaml's "-1".
#
# Deliberately sync-wave only, NOT argocd.argoproj.io/hook: PreSync --
# observed live that marking this hook-typed made Argo CD treat it as
# ephemeral (excluded from tracked/managed resources) rather than a
# persistent one, and it got deleted within milliseconds of every
# selfHeal reconciliation, over and over, taking the whole backend down
# each time. Plain sync-wave still orders it ahead of postgres-*.yaml
# without that hook lifecycle.
#
# Prune=false: this Application syncs from two sources (the Helm chart and
# this raw secrets/<env> directory) with prune+selfHeal on. If the
# directory source ever renders zero resources for one sync cycle (a
# transient git/repo-server hiccup, a race during a burst of rapid
# commits), Argo CD could otherwise read that as "this SealedSecret is no
# longer desired" and delete it. Reapplying this SealedSecret from git is
# always safe (it's ciphertext, idempotent), so exempt it from pruning
# rather than let one bad render wipe out a resource nothing else can
# survive without.
yq eval -i '
  .metadata.annotations."argocd.argoproj.io/sync-wave" = "-2" |
  .metadata.annotations."argocd.argoproj.io/sync-options" = "Prune=false"
' "$out_dir/backend-secrets.sealed.yaml"

echo "Wrote $out_dir/backend-secrets.sealed.yaml — safe to commit (ciphertext only)."
