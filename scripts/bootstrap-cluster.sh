#!/usr/bin/env bash
#
# bootstrap-cluster.sh — chains together the `terraform apply` steps from
# runbook.md §1 (k3s -> bootstrap -> dev -> staging) so you don't have to
# cd into each terraform/environments/<env> directory and run init/apply
# by hand, one at a time.
#
# What this script deliberately does NOT automate: generating real secrets.
# Backing up the Sealed Secrets private key and creating
# secrets/{dev,staging}/backend-secrets.sealed.yaml need a human typing
# real passwords (runbook.md §1 steps 3-4) — nothing here can safely do
# that for you, so the script pauses and asks you to confirm it's done
# before continuing on to dev/staging.
#
# Every stage still runs exactly the `terraform init`/`apply` commands
# documented in runbook.md §1 — this is a convenience wrapper around that
# same process, not a different one.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

AUTO_APPROVE=false
SKIP_K3S=false
SKIP_SECRETS_CHECK=false
SYNC_STAGING=false
PLAN_ONLY=false

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap-cluster.sh [options]

Options:
  -y, --yes              Auto-approve every `terraform apply` (skips the
                          interactive "Enter a value: yes" prompt). Without
                          this, each stage still pauses for you to review
                          the plan and confirm, same as running terraform
                          by hand.
  --skip-k3s              Skip installing k3s — use this when the cluster
                          runs on a separate machine (see
                          bootstrap/k3s-install.md) and ~/.kube/config
                          already points at it.
  --skip-secrets-check    Skip the Sealed Secrets key-backup confirmation
                          AND the secrets/{dev,staging}/*.sealed.yaml
                          auto-generation from .env.local. Only pass this
                          if you're managing secrets entirely by hand
                          (secrets/dev/README.md) instead.
  --sync-staging          Also run the one-time manual staging sync at the
                          end (runbook.md §1 step 8). Off by default —
                          staging's manual sync is a deliberate gate, not
                          something to wave through silently.
  --plan-only             Run `terraform plan` instead of `apply` at every
                          stage — preview what would happen, change
                          nothing.
  -h, --help              Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) AUTO_APPROVE=true ;;
    --skip-k3s) SKIP_K3S=true ;;
    --skip-secrets-check) SKIP_SECRETS_CHECK=true ;;
    --sync-staging) SYNC_STAGING=true ;;
    --plan-only) PLAN_ONLY=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

# --- helpers -----------------------------------------------------------

banner() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: '$1' is required but not installed — see runbook.md §0." >&2
    exit 1
  }
}

confirm() {
  # Always interactive, regardless of --yes: this gates a decision about
  # real secrets existing, which is a different kind of check than "did
  # you review this terraform plan."
  local reply
  read -r -p "$1 [y/N] " reply
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

run_terraform() {
  # $1 = environment name under terraform/environments/
  local dir="$REPO_ROOT/terraform/environments/$1"
  banner "terraform: $1"
  cd "$dir"

  if [ -f terraform.tfvars.example ] && [ ! -f terraform.tfvars ]; then
    cp terraform.tfvars.example terraform.tfvars
  fi

  terraform init -input=false

  if [ "$PLAN_ONLY" = true ]; then
    terraform plan
    return 0
  fi

  if [ "$AUTO_APPROVE" = true ]; then
    terraform apply -auto-approve
  else
    terraform apply
  fi
}

wait_for_pods() {
  # $1 = namespace
  banner "waiting for pods in $1 to be Ready"
  # --field-selector excludes pods that already ran to completion (e.g. Argo
  # CD's argocd-redis-secret-init one-shot Job) — a Succeeded pod's Ready
  # condition is permanently False (its container already exited), so
  # `--all` with no filter waits forever for something that will never
  # become Ready, timing out even once every real long-running pod is
  # already healthy. Confirmed in practice on this exact chart.
  kubectl wait --for=condition=Ready pod --all -n "$1" \
    --field-selector=status.phase!=Succeeded --timeout=300s
}

# --- preflight -----------------------------------------------------------

banner "checking required tools"
require_cmd terraform
require_cmd kubectl
require_cmd helm
require_cmd kubeseal
terraform version | head -1
kubectl version --client | head -1

# --- stage 1: k3s ----------------------------------------------------------

if [ "$SKIP_K3S" = true ]; then
  banner "skipping k3s install (--skip-k3s) — checking for an existing cluster instead"
  kubectl get nodes >/dev/null || {
    echo "ERROR: --skip-k3s was passed but kubectl can't reach a cluster." >&2
    echo "Set up ~/.kube/config per bootstrap/k3s-install.md first." >&2
    exit 1
  }
else
  run_terraform k3s
  if [ "$PLAN_ONLY" != true ]; then
    banner "waiting for the node to be Ready"
    # `kubectl wait --all` only waits for objects that already exist to
    # reach the condition — if the Node object doesn't exist yet (API
    # server still starting, or the k3s-install.sh provisioner exited
    # before kubelet finished registering the node), it fails immediately
    # with "No resources found" or "connection refused" instead of
    # retrying. Poll for the node to actually show up first, then do the
    # real Ready wait.
    for i in $(seq 1 60); do
      if kubectl get nodes --no-headers 2>/dev/null | grep -q .; then
        break
      fi
      sleep 2
    done
    kubectl wait --for=condition=Ready node --all --timeout=180s
  fi
fi

# --- stage 2: bootstrap (Argo CD + Sealed Secrets) -------------------------

run_terraform bootstrap
if [ "$PLAN_ONLY" != true ]; then
  wait_for_pods argocd
  wait_for_pods sealed-secrets
fi

# --- secrets: key backup reminder + auto-generate from .env.local ----------

if [ "$PLAN_ONLY" != true ] && [ "$SKIP_SECRETS_CHECK" != true ]; then
  banner "Sealed Secrets key backup"
  cat <<'EOF'
Back up the Sealed Secrets private key now if you haven't already —
runbook.md §1 step 3. This is the one secrets-related step that genuinely
can't be automated: the key is generated in-cluster, on the controller's
first run, with nothing in .env.local to read it from.
EOF
  confirm "Have you backed up the Sealed Secrets key?" || {
    echo "Stopping here." >&2
    echo "Re-run with --skip-secrets-check once it's done, or just" >&2
    echo "re-run this script again later — the earlier stages are no-ops" >&2
    echo "if nothing has changed." >&2
    exit 1
  }

  # secrets/<env>/backend-secrets.sealed.yaml — generated from
  # <ENV>_POSTGRES_PASSWORD/<ENV>_JWT_SECRET in .env.local (see that file's
  # comment and scripts/generate-secrets.sh), instead of pausing here to
  # ask whether you did this by hand. Existing files are left alone, so a
  # secret you've deliberately hand-rotated or committed already won't get
  # silently overwritten by whatever's currently in .env.local.
  for env_for_secrets in dev staging; do
    sealed_file="$REPO_ROOT/secrets/$env_for_secrets/backend-secrets.sealed.yaml"
    if [ -f "$sealed_file" ]; then
      banner "secrets/$env_for_secrets/backend-secrets.sealed.yaml already exists — leaving it alone"
    else
      banner "generating secrets/$env_for_secrets/backend-secrets.sealed.yaml from .env.local"
      "$REPO_ROOT/scripts/generate-secrets.sh" "$env_for_secrets"
    fi
  done
fi

# --- stage 3 & 4: dev + staging Applications --------------------------------

run_terraform dev
run_terraform staging

if [ "$PLAN_ONLY" = true ]; then
  banner "plan-only run finished — nothing was changed"
  exit 0
fi

banner "Argo CD Applications"
kubectl get applications -n argocd

if [ "$SYNC_STAGING" = true ]; then
  banner "triggering the one-time manual staging sync"
  kubectl patch application stock-hpp-staging -n argocd --type merge \
    -p '{"operation":{"sync":{}}}'
else
  cat <<EOF

Staging registered but not synced (by design — see runbook.md §3).
Sync it when you're ready:
  kubectl patch application stock-hpp-staging -n argocd --type merge -p '{"operation":{"sync":{}}}'
EOF
fi

banner "done — see runbook.md §1 step 9 to verify the app is actually up"
