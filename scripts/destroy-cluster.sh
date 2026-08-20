#!/usr/bin/env bash
#
# destroy-cluster.sh — tears down what scripts/bootstrap-cluster.sh builds,
# in reverse order: staging -> dev -> bootstrap -> k3s. Mirrors that
# script's flags/shape.
#
# WARNING: this is genuinely destructive, not just "undo my terraform
# changes." Destroying staging/dev deletes their Argo CD Applications,
# which carry the `resources-finalizer.argocd.argoproj.io` finalizer (see
# terraform/modules/argocd-application) — Argo CD cascade-deletes
# everything it manages for that Application as part of honoring that
# finalizer, including the in-cluster Postgres StatefulSet and its PVC.
# There is no backup mechanism for that data (see runbook.md §8). Once
# it's gone, it's gone.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AUTO_APPROVE=false
KEEP_K3S=false
PLAN_ONLY=false

usage() {
  cat <<'EOF'
Usage: ./scripts/destroy-cluster.sh [options]

Tears down what scripts/bootstrap-cluster.sh builds, in reverse order:
staging -> dev -> bootstrap -> k3s.

Options:
  -y, --yes         Auto-approve every `terraform destroy` AND skip the
                     "type DESTROY to confirm" prompt. Use with real care —
                     see the warning at the top of this script.
  --keep-k3s         Destroy staging/dev/bootstrap only — leave k3s (and
                     the cluster itself) running. Useful for wiping the
                     app layer to re-run bootstrap-cluster.sh without
                     reinstalling k3s and waiting through image pulls
                     again.
  --plan-only        Run `terraform plan -destroy` instead of `destroy` at
                     every stage — preview what would be removed, change
                     nothing.
  -h, --help          Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) AUTO_APPROVE=true ;;
    --keep-k3s) KEEP_K3S=true ;;
    --plan-only) PLAN_ONLY=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

banner() {
  printf '\n\033[1;31m==> %s\033[0m\n' "$1"
}

run_destroy() {
  # $1 = environment name under terraform/environments/
  local dir="$REPO_ROOT/terraform/environments/$1"
  banner "terraform destroy: $1"
  cd "$dir"

  terraform init -input=false

  if [ "$PLAN_ONLY" = true ]; then
    terraform plan -destroy
    return 0
  fi

  if [ "$AUTO_APPROVE" = true ]; then
    terraform destroy -auto-approve
  else
    terraform destroy
  fi
}

if [ "$PLAN_ONLY" != true ] && [ "$AUTO_APPROVE" != true ]; then
  banner "this will destroy real, running infrastructure"
  cat <<'EOF'
About to tear down, in this order: staging -> dev -> bootstrap -> k3s.

Destroying staging/dev deletes their Argo CD Applications, which carry a
finalizer that makes Argo CD cascade-delete everything it manages for them
FIRST — including the in-cluster Postgres StatefulSet and its PVC. There is
no backup for that data (see runbook.md §8). Once it's gone, it's gone.
EOF
  read -r -p "Type DESTROY (all caps) to continue: " reply
  if [ "$reply" != "DESTROY" ]; then
    echo "Aborted — no changes made." >&2
    exit 1
  fi
fi

run_destroy staging
run_destroy dev
run_destroy bootstrap

if [ "$KEEP_K3S" = true ]; then
  banner "done — staging/dev/bootstrap destroyed, k3s left running (--keep-k3s)"
  exit 0
fi

run_destroy k3s

if [ "$PLAN_ONLY" != true ]; then
  # k3s's own destroy provisioner uninstalls the cluster, but nothing
  # automatically removes the now-stale kubeconfig pointing at it — same
  # cleanup documented by hand in runbook.md §1's rebuild note.
  kubeconfig_path=$(printf '%s' "~/.kube/config" | sed "s|^~|$HOME|")
  if [ -f "$kubeconfig_path" ]; then
    rm -f "$kubeconfig_path"
    banner "removed stale $kubeconfig_path"
  fi
fi

banner "done — everything destroyed"
