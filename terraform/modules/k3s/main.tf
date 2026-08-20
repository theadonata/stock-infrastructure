# Installs k3s on the same machine `terraform apply` runs from — only makes
# sense for the "operator machine IS the cluster" setup (see
# ../../README.md). There's no official k3s Terraform provider, and
# Terraform can't track an installed-on-the-host binary/systemd-service as
# a real managed resource (no diff, no drift detection) — so this is
# deliberately the only place in this repo that shells out via a
# local-exec provisioner instead of a proper provider resource. Everything
# downstream of this (Argo CD, Sealed Secrets, Applications) is real
# Terraform-managed state.
resource "null_resource" "k3s_install" {
  # Only re-runs the provisioner when the pinned version actually changes —
  # a plain `terraform apply` with no version bump is a no-op here, same as
  # every other resource in this repo.
  triggers = {
    k3s_version = var.k3s_version
  }

  provisioner "local-exec" {
    # The installer is written to a fixed path under $HOME (not /tmp — a
    # world-writable directory would let another local user race/replace
    # the script between write and sudo-exec) with the version baked
    # directly into its own content, then run as
    # `sudo /usr/bin/sh $HOME/.cache/k3s-install.sh` — a static path with
    # zero trailing arguments. That's deliberate: it lets the sudoers
    # NOPASSWD rule in terraform/README.md name this exact command, instead
    # of needing a wildcard covering the dynamic version string — sudo-rs
    # (what this machine ships) explicitly forbids wildcards inside
    # command-line arguments, only a trailing `*` is supported, so a rule
    # like `INSTALL_K3S_VERSION=* ...` isn't valid here.
    #
    # sudo -n fails fast with a clear message instead of hanging forever:
    # local-exec has no interactive TTY, so a real sudo password prompt
    # here would just sit there until Terraform's operation times out.
    command = <<-EOT
      set -e
      if command -v k3s >/dev/null 2>&1; then
        echo "k3s already installed, skipping (bump k3s_version to force a reinstall)"
        exit 0
      fi
      mkdir -p "$HOME/.cache"
      install_script="$HOME/.cache/k3s-install.sh"
      {
        echo '#!/usr/bin/sh'
        echo "export INSTALL_K3S_VERSION='${var.k3s_version}'"
        curl -sfL https://get.k3s.io
      } > "$install_script"
      chmod 700 "$install_script"
      if ! sudo -n /usr/bin/sh "$install_script"; then
        echo "ERROR: 'sudo /usr/bin/sh $install_script' failed or needed a password." >&2
        echo "local-exec has no interactive TTY for a sudo password prompt — see" >&2
        echo "terraform/README.md for the exact NOPASSWD sudoers rule this needs." >&2
        exit 1
      fi
      rm -f "$install_script"
    EOT
  }

  # k3s ships its own uninstaller specifically for this — makes `terraform
  # destroy` (or `terraform destroy -target=module.k3s`) actually reverse
  # what this resource did, instead of leaving an orphaned install behind.
  provisioner "local-exec" {
    when    = destroy
    command = "sudo -n /usr/local/bin/k3s-uninstall.sh || true"
  }
}

resource "null_resource" "kubeconfig" {
  # Re-runs whenever k3s_install is (re)created, and only then — not on
  # every apply.
  triggers = {
    k3s_install_id = null_resource.k3s_install.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      # Expand a leading ~ to $HOME ourselves — POSIX shells only do tilde
      # expansion on unquoted tokens, and this value arrives double-quoted.
      kubeconfig_path=$(printf '%s' "${var.kubeconfig_path}" | sed "s|^~|$HOME|")
      mkdir -p "$(dirname "$kubeconfig_path")"
      # k3s takes a moment after install to write its kubeconfig and bring
      # the API server up; poll instead of assuming it's instant.
      for i in $(seq 1 30); do
        [ -f /etc/rancher/k3s/k3s.yaml ] && break
        sleep 2
      done
      if ! sudo -n /usr/bin/cat /etc/rancher/k3s/k3s.yaml > "$kubeconfig_path"; then
        echo "ERROR: 'sudo /usr/bin/cat /etc/rancher/k3s/k3s.yaml' failed or needed a password." >&2
        echo "See terraform/README.md for the exact NOPASSWD sudoers rule this needs." >&2
        exit 1
      fi
      chmod 600 "$kubeconfig_path"
    EOT
  }
}
