# secrets/staging/

Same shape as `../dev/README.md` — generate with:

```bash
./scripts/generate-secrets.sh staging
```

which reads `STAGING_POSTGRES_PASSWORD`/`STAGING_JWT_SECRET` from
`.env.local` (staging's own real values — never reuse dev's). To do it by
hand instead, follow `../dev/README.md`'s manual steps with
`--namespace stock-hpp-staging` and staging's own values.
