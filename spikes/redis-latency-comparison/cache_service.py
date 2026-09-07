"""The thing being compared: a cache-aside read path in front of a slow
report-style query, exactly the shape a real backend endpoint would use
(check cache -> on miss, query DB -> populate cache -> return).

pg_sleep(0.15) is added to the query on top of the real aggregate. This is
a deliberate, documented stand-in for "a query that's known to be expensive
in production" (a report query, a heavy join, whatever) — it makes the
"slow" baseline reproducible regardless of the machine this spike runs on,
while the surrounding query is still a real Postgres round-trip against
real (if synthetic) rows, not a fake in-memory delay.
"""
import json
import time


def get_category_report(conn, redis_client, category: str, use_cache: bool) -> dict:
    cache_key = f"report:category:{category}"

    if use_cache:
        cached = redis_client.get(cache_key)
        if cached is not None:
            return json.loads(cached)

    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT pg_sleep(0.15), category, COUNT(*) AS movements, SUM(quantity) AS total_quantity
            FROM inventory_movements
            WHERE category = %s
            GROUP BY category
            """,
            (category,),
        )
        row = cur.fetchone()

    result = {
        "category": row[1],
        "movements": row[2],
        "total_quantity": row[3],
    }

    if use_cache:
        # 60s TTL: long enough to stay warm for the length of a benchmark
        # run, short enough that this isn't pretending to be a real
        # production caching policy.
        redis_client.setex(cache_key, 60, json.dumps(result))

    return result


def timed(fn, *args, **kwargs) -> tuple[float, dict]:
    """Runs fn once, returning (elapsed_seconds, result)."""
    start = time.perf_counter()
    result = fn(*args, **kwargs)
    elapsed = time.perf_counter() - start
    return elapsed, result
