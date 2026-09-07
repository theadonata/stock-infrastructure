"""The test case: runs get_category_report() N times under three
conditions and reports latency stats for each --

  no_cache   -- every call hits Postgres directly (use_cache=False)
  cache_cold -- the first call per category, cache empty (miss -> DB -> set)
  cache_warm -- every call after the first, cache populated (hit, no DB)

Run via `kubectl port-forward` to both services (see use-case.md), then:
    python benchmark.py
"""
import os
import statistics

import psycopg2
import redis

from cache_service import get_category_report, timed

DB_DSN = os.environ.get(
    "SPIKE_DATABASE_URL",
    "postgresql://spike_user:spike_pass@localhost:5432/spike_db",
)
REDIS_HOST = os.environ.get("SPIKE_REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("SPIKE_REDIS_PORT", "6379"))

CATEGORIES = ["bags", "wallets", "belts", "accessories", "footwear"]
ITERATIONS_PER_CATEGORY = 20  # per condition, per category


def summarize(label: str, samples_ms: list[float]) -> None:
    print(
        f"{label:<12} n={len(samples_ms):<4} "
        f"min={min(samples_ms):7.1f}ms  "
        f"p50={statistics.median(samples_ms):7.1f}ms  "
        f"avg={statistics.fmean(samples_ms):7.1f}ms  "
        f"max={max(samples_ms):7.1f}ms"
    )


def main() -> None:
    conn = psycopg2.connect(DB_DSN)
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT)
    r.flushall()

    no_cache_samples: list[float] = []
    cache_cold_samples: list[float] = []
    cache_warm_samples: list[float] = []

    try:
        # Condition 1: no cache at all, every call hits Postgres.
        for category in CATEGORIES:
            for _ in range(ITERATIONS_PER_CATEGORY):
                elapsed, _ = timed(get_category_report, conn, r, category, False)
                no_cache_samples.append(elapsed * 1000)

        r.flushall()

        # Condition 2 + 3: cache-aside. First call per category is a cold
        # miss (DB + populate); every subsequent call for that category is
        # a warm hit (Redis only).
        for category in CATEGORIES:
            elapsed, _ = timed(get_category_report, conn, r, category, True)
            cache_cold_samples.append(elapsed * 1000)
            for _ in range(ITERATIONS_PER_CATEGORY - 1):
                elapsed, _ = timed(get_category_report, conn, r, category, True)
                cache_warm_samples.append(elapsed * 1000)
    finally:
        conn.close()

    print("\nLatency comparison (report query: SELECT ... WHERE category GROUP BY category)\n")
    summarize("no_cache", no_cache_samples)
    summarize("cache_cold", cache_cold_samples)
    summarize("cache_warm", cache_warm_samples)

    speedup = statistics.fmean(no_cache_samples) / statistics.fmean(cache_warm_samples)
    print(f"\nWarm cache is ~{speedup:.1f}x faster than no cache on average.")


if __name__ == "__main__":
    main()
