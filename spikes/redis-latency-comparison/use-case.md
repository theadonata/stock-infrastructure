# Research spike: Redis-cached vs. uncached read latency

A **research spike** (a time-boxed learning exercise, not a "spike" in the
alerting sense used elsewhere in `CONTEXT.md` — see the disambiguation
there). Disposable: no ADR, no Terraform module, nothing Argo CD
reconciles. The point is the numbers and the explanation below, not a
long-lived deployment.

## Hypothesis

A cache-aside read path (check Redis first, fall back to Postgres on a
miss, populate Redis on the way out) should make repeated reads of the
same report noticeably faster than hitting Postgres every time, once the
cache is warm — at the cost of a slightly slower first read (the cold-miss
path does both the DB query *and* the cache write).

## Scenario

A report-style query — "total inventory movements for category X" — the
same shape as a real dashboard widget or API endpoint would run. The query
includes `pg_sleep(0.15)` alongside a real (if synthetic) aggregate over a
seeded `inventory_movements` table, as a documented, reproducible stand-in
for "a query known to be expensive in production" (see `cache_service.py`
for why).

Three conditions, each run against the same 5 categories, 20 iterations
per category:

- **no_cache** — every call hits Postgres directly
- **cache_cold** — the first call per category (cache miss: DB + populate)
- **cache_warm** — every call after the first (cache hit, no DB)

## Setup

Everything runs in an isolated `redis-spike` namespace on the homelab k3s
cluster, deployed manually (not via Argo CD/GitOps — this is disposable):

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/redis.yaml
kubectl wait -n redis-spike --for=condition=ready pod -l app=postgres --timeout=60s
kubectl wait -n redis-spike --for=condition=ready pod -l app=redis --timeout=60s

# In separate terminals (or backgrounded):
kubectl -n redis-spike port-forward svc/postgres 5432:5432
kubectl -n redis-spike port-forward svc/redis 6379:6379

pip install -r requirements.txt
python seed.py
python benchmark.py
```

Tear down when done — nothing here is meant to persist:

```bash
kubectl delete namespace redis-spike
```

## Redis configuration

`--maxmemory 128mb --maxmemory-policy allkeys-lru`, no persistence
(`--save "" --appendonly no`) — the two settings that most affect
real-world behavior (memory bounds + eviction policy), deliberately
without persistence since this data is disposable and durability wasn't
the thing being learned here.

## Results

Run against the live homelab k3s cluster (`redis-spike` namespace),
5 categories × 20 iterations per condition:

```
no_cache     n=100  min=151.6ms  p50=151.9ms  avg=152.0ms  max=155.6ms
cache_cold   n=5    min=154.0ms  p50=154.1ms  avg=154.1ms  max=154.3ms
cache_warm   n=95   min=  0.7ms  p50=  0.8ms  avg=  0.9ms  max=  1.2ms

Warm cache is ~176x faster than no cache on average.
```

**What this confirms, in plain English:**

- **No cache** costs ~152ms every single time — the full Postgres round
  trip (the simulated 150ms "expensive query" plus real scan/aggregate
  time) is paid on every read, even for identical repeated requests.
- **Cold cache** (the first read of a category) costs slightly *more* than
  no cache at all (~154ms vs ~152ms) — it pays the same DB cost, plus the
  extra round trip to write the result into Redis. This is the real,
  often-overlooked cost of the cache-aside pattern: the first reader after
  a miss/expiry is always slightly worse off, never better.
- **Warm cache** drops to under 1ms — three orders of magnitude faster,
  because the read never touches Postgres at all.

The hypothesis held: caching helps enormously for repeated reads of the
same data, at the cost of a marginally slower first read. The bigger
practical takeaway for production use is less about the *average* speedup
and more about *which reads* benefit — a cache only pays off when the same
key is read often enough, relative to its TTL, to amortize that cold-miss
cost across many warm hits. A key read exactly once per TTL window gets no
benefit at all (in fact a tiny loss), which is the real design question
when actually adopting Redis for a given endpoint: is this data read much
more often than it changes?

The spike's infra (`redis-spike` namespace, Postgres, Redis) has been torn
down — nothing from this exercise runs in the cluster any more. The code
and this write-up remain as the deliverable.
