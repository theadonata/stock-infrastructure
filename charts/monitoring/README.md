# charts/monitoring/

Umbrella chart for the shared homelab observability stack (Prometheus,
Grafana, Loki, Alloy, Alertmanager) — see
`../../docs/adr/0003-observability-stack.md` for the full design. Synced by
Argo CD as a **single-source** Application
(`../../terraform/environments/monitoring/`), unlike `../stock-hpp`'s
chart-plus-secrets-directory setup — see that ADR for why.

## Secrets

`templates/grafana-admin-secret.sealed.yaml` and
`templates/alertmanager-config-secret.sealed.yaml` are `SealedSecret` CRs,
safe to commit because their contents are ciphertext only the in-cluster
Sealed Secrets controller can decrypt. Unlike `../../secrets/dev/` and
`../../secrets/staging/`, these live inside the chart itself rather than a
separate Argo CD source — see the ADR's "single-source" reasoning.

### Generating them (after the Sealed Secrets controller is running)

**Preferred:** set `GRAFANA_ADMIN_PASSWORD` and `DISCORD_WEBHOOK_URL` in
`.env.local` (see that file's comment — `DISCORD_WEBHOOK_URL` needs a real
webhook URL from the target Discord channel's Integrations settings, there
is no default), then run:

```bash
./scripts/generate-monitoring-secrets.sh
```

**By hand**, if you'd rather not keep real values in `.env.local`:

```bash
# Grafana admin login
kubectl create secret generic monitoring-grafana-admin \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<real-admin-password>' \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
    --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
  > templates/grafana-admin-secret.sealed.yaml

# Alertmanager's full config, including the Discord receiver — the key
# must be exactly "alertmanager.yaml", the name
# alertmanager.alertmanagerSpec.configSecret in values.yaml expects. Piped
# through /dev/stdin, not a temp file, so the real webhook URL never
# touches disk in plaintext (same as scripts/generate-monitoring-secrets.sh).
cat <<'EOF' | kubectl create secret generic monitoring-alertmanager-config \
  --namespace monitoring \
  --from-file=alertmanager.yaml=/dev/stdin \
  --dry-run=client -o yaml \
  | kubeseal --format yaml \
    --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
  > templates/alertmanager-config-secret.sealed.yaml
global:
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
      - webhook_url: '<real-discord-webhook-url>'
EOF
```

`--controller-name`/`--controller-namespace` matter — see
`../../secrets/dev/README.md` for why (same controller, same flags, same
reason).

Both files get `argocd.argoproj.io/sync-wave: "-1"` so they sync before the
rest of the stack — plain sync-wave, not a PreSync hook, is sufficient
here since this Application is single-source (see the ADR).
