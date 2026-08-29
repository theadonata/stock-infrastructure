# secrets/staging/

This works just like `../dev/README.md` — head over there for the full
explanation. To generate staging's secret, run:

```bash
./scripts/generate-secrets.sh staging
```

This reads `STAGING_POSTGRES_PASSWORD`/`STAGING_JWT_SECRET` from
`.env.local`. Make sure these are staging's own real values — never reuse
dev's!

Prefer doing it by hand? Follow the manual steps in `../dev/README.md`,
just swap in `--namespace stock-hpp-staging` and staging's own values.
