"""Seeds the throwaway Postgres instance with a small synthetic dataset:
an inventory_movements table, shaped like a real inventory ledger (product
movements by category) so the report query below reads as something a real
app would actually run — without touching any real stock-hpp data.

Run once after the Postgres pod is up, via `kubectl port-forward`:
    python seed.py
"""
import os
import random

import psycopg2

DB_DSN = os.environ.get(
    "SPIKE_DATABASE_URL",
    "postgresql://spike_user:spike_pass@localhost:5432/spike_db",
)

CATEGORIES = ["bags", "wallets", "belts", "accessories", "footwear"]
ROW_COUNT = 5000


def main() -> None:
    conn = psycopg2.connect(DB_DSN)
    try:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS inventory_movements")
            cur.execute(
                """
                CREATE TABLE inventory_movements (
                    id SERIAL PRIMARY KEY,
                    category TEXT NOT NULL,
                    movement_type TEXT NOT NULL,
                    quantity INTEGER NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
            )
            # No index on category -- deliberate, so the report query below
            # does a real sequential scan + aggregate rather than an
            # index-only lookup, closer to how an un-optimized report query
            # behaves in production before someone reaches for a cache.
            rows = [
                (
                    random.choice(CATEGORIES),
                    random.choice(["in", "out"]),
                    random.randint(1, 50),
                )
                for _ in range(ROW_COUNT)
            ]
            cur.executemany(
                "INSERT INTO inventory_movements (category, movement_type, quantity) VALUES (%s, %s, %s)",
                rows,
            )
        conn.commit()
        print(f"Seeded {ROW_COUNT} rows across {len(CATEGORIES)} categories.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
