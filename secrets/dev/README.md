# secrets/dev/

Holds `backend-secrets.sealed.yaml` — a `SealedSecret` CR, safe to commit
because its contents are ciphertext only the in-cluster Sealed Secrets
controller can decrypt. Not managed by Terraform or templated by the Helm
chart (see `../../gitops-plan.md`'s tool-selection table for why); this
directory is applied by Argo CD as the second source in `dev`'s multi-source
Application (see `../../terraform/modules/argocd-application`).

## Generating it (Phase 0, after the Sealed Secrets controller is running)

**Preferred:** set `DEV_POSTGRES_PASSWORD` and `DEV_JWT_SECRET` in
`.env.local` (already done — see that file's comment for how they were
generated), then run:

```bash
./scripts/generate-secrets.sh dev
```

That's `secrets/dev/generate-secrets.sh`'s whole job — it's the same
`kubectl create secret ... | kubeseal ...` command below, reading the real
values from `.env.local` instead of you typing them in by hand.

**By hand**, if you'd rather not keep real values in `.env.local`:

```bash
kubectl create secret generic stock-hpp-backend-secrets \
  --namespace stock-hpp-dev \
  --from-literal=POSTGRES_USER=stock_hpp_user \
  --from-literal=POSTGRES_PASSWORD='<real-dev-password>' \
  --from-literal=POSTGRES_DB=stock_hpp_db \
  --from-literal=DATABASE_URL='postgresql+psycopg2://stock_hpp_user:<real-dev-password>@stock-hpp-postgres:5432/stock_hpp_db' \
  --from-literal=JWT_SECRET='<real-dev-jwt-secret>' \
  --dry-run=client -o yaml > /tmp/backend-secrets.yaml

kubeseal --format yaml \
  --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
  < /tmp/backend-secrets.yaml > backend-secrets.sealed.yaml
rm /tmp/backend-secrets.yaml   # never commit the plaintext version
```

`--controller-name`/`--controller-namespace` matter: `kubeseal`'s own
default assumes a controller named `sealed-secrets-controller` in
`kube-system`, but `terraform/modules/sealed-secrets` installs it as the
Helm release `sealed-secrets` in the `sealed-secrets` namespace — without
these flags `kubeseal` fails with "services sealed-secrets-controller not
found" even though the controller is running fine.

`POSTGRES_PASSWORD` and the password embedded in `DATABASE_URL` must match
— both are read by different pods (`postgres-statefulset.yaml` and
`backend-deployment.yaml`/`backend-migrate-job.yaml`) from this same Secret.
