# secrets/dev/

This folder holds `backend-secrets.sealed.yaml`, a `SealedSecret` resource.
It's safe to commit to git — the contents are ciphertext, and only the
Sealed Secrets controller running in the cluster can decrypt them.

It's not managed by Terraform or templated by the Helm chart (see the
tool-selection section of `../../docs/adr/0002-gitops-deployment-architecture.md`
if you're curious why). Instead, Argo CD applies this whole directory as the
second source in `dev`'s multi-source Application — check out
`../../terraform/modules/argocd-application` for how that's wired up.

## Generating it

You'll do this once the Sealed Secrets controller is up and running
(Phase 0).

**The easy way:** make sure `DEV_POSTGRES_PASSWORD` and `DEV_JWT_SECRET` are
set in `.env.local` (they already are — see that file's comment for how they
were generated), then run:

```bash
./scripts/generate-secrets.sh dev
```

That script doesn't do anything fancy — it's just the same
`kubectl create secret ... | kubeseal ...` command shown below, pulling the
real values from `.env.local` so you don't have to type them in by hand.

**Prefer to do it by hand?** No problem — maybe you'd rather not keep real
values sitting in `.env.local`. Here's the manual version:

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

Don't skip the `--controller-name`/`--controller-namespace` flags — `kubeseal`
assumes by default that the controller is named `sealed-secrets-controller`
and lives in `kube-system`, but `terraform/modules/sealed-secrets` actually
installs it as the Helm release `sealed-secrets` in the `sealed-secrets`
namespace. Without these flags, `kubeseal` will complain that
"services sealed-secrets-controller not found" — even though the controller
is running just fine.

One more thing to watch for: `POSTGRES_PASSWORD` and the password embedded in
`DATABASE_URL` need to match each other. They're read from this same Secret
by different pods (`postgres-statefulset.yaml` and
`backend-deployment.yaml`/`backend-migrate-job.yaml`), so if they drift apart
things will break in confusing ways.
