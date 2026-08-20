# Phase 0: k3s install (manual — separate-box case only)

Only applies when the cluster will run on a **separate** box from wherever
you run Terraform — a homelab machine you'd otherwise have to SSH into. If
Terraform runs on the same machine the cluster will live on, use
`../terraform/environments/k3s/` instead (`terraform apply` there installs
k3s via a scoped, passwordless-sudo `local-exec` provisioner — see
`../terraform/README.md` §0) and skip this file entirely.

There's no Terraform provider for "install a k8s distro on bare metal/a VPS
via SSH" that isn't itself a fragile `null_resource` + `remote-exec`
wrapper around the same shell command below, so for a separate box this
step stays manual. Either way, everything *inside* the cluster from here on
(Argo CD, Sealed Secrets, namespaces, Argo CD Applications) is Terraform's
job — see `../terraform/`.

## Steps

1. Install k3s (ships Traefik ingress, local-path storage, and ServiceLB
   built in — no extra installs needed for a homelab single-node box):

   ```bash
   curl -sfL https://get.k3s.io | sh -
   ```

2. Grab the kubeconfig k3s wrote and point your local `kubectl`/Terraform at
   it (k3s' default is root-only, so this also fixes permissions for your
   user):

   ```bash
   sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
   chmod 600 ~/.kube/config
   kubectl get nodes   # should show the node as Ready
   ```

   If Terraform will run from a *different* machine than the one k3s is on
   (the separate-box case this doc is for), `scp` that kubeconfig over to
   wherever `terraform/environments/bootstrap` etc. will actually run.

3. Confirm Traefik and local-path-provisioner came up (both ship with k3s
   by default — nothing to install):

   ```bash
   kubectl get pods -n kube-system
   ```

4. Continue with `../terraform/environments/bootstrap/` (Argo CD +
   Sealed Secrets install) — see `../terraform/README.md`.
