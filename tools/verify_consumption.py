#!/usr/bin/env python3
"""Cross-platform regression fixture for Calculator.derivedRows.

Mirrors the pure Swift calculation so the supplied JSON can be checked without
an iOS toolchain. Run the XCTest suite on macOS for the final UI/build check.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


def derive(records: list[dict]) -> list[dict]:
    recs = sorted(records, key=lambda r: (r["date"], r["createdAt"]))
    rows = []
    previous = None
    for record in recs:
        distance = None
        kind = "first"
        if previous is not None:
            delta = record["odometerKm"] - previous
            if delta > 0:
                distance, kind = delta, "ok"
            elif delta < 0:
                kind = "rollback"
        consumption = record["energyKWh"] / distance * 100 if distance and record["energyKWh"] > 0 else None
        cost = record["costCNY"] / distance if distance and record["costCNY"] > 0 else None
        rows.append({"record": record, "distance": distance, "kind": kind,
                     "consumption": consumption, "cost": cost, "groupDistance": None,
                     "pairedEnergy": 0.0, "pairedCost": 0.0})
        if math.isfinite(record["odometerKm"]) and kind != "rollback":
            previous = record["odometerKm"]

    original_consumption = [r["record"]["energyKWh"] / r["distance"] * 100
                            if r["distance"] and r["record"]["energyKWh"] > 0 else None
                            for r in rows]
    outliers = {i for i, r in enumerate(rows)
                if r["distance"] is not None and r["distance"] < 30
                and original_consumption[i] is not None
                and not 5 <= original_consumption[i] <= 40}
    groups = []
    i = 0
    while i < len(rows):
        if i not in outliers:
            i += 1
            continue
        start = i
        while i + 1 < len(rows) and i + 1 in outliers:
            i += 1
        if i + 1 < len(rows) and rows[i + 1]["distance"] is not None:
            groups.append((list(range(start, i + 2)), i + 1))
            i += 2
        else:
            i += 1
    for i in reversed(range(len(rows))):
        if i in outliers and not any(i in group[0] for group in groups):
            start = i
            while start > 0 and start - 1 in outliers and not any(start - 1 in group[0] for group in groups):
                start -= 1
            if (start > 0 and rows[start - 1]["distance"] is not None
                    and not any(start - 1 in group[0] for group in groups)):
                groups.append((list(range(start - 1, i + 1)), start - 1))

    for indices, settle_index in groups:
        distance = sum(rows[i]["distance"] or 0 for i in indices)
        energy = sum(rows[i]["record"]["energyKWh"] for i in indices)
        cost = sum(rows[i]["record"]["costCNY"] for i in indices)
        for i in indices:
            if i != settle_index:
                rows[i].update(kind="pending", consumption=None, cost=None)
        rows[settle_index].update(consumption=energy / distance * 100 if energy > 0 else None,
                                  cost=cost / distance if cost > 0 else None,
                                  groupDistance=distance, pairedEnergy=energy, pairedCost=cost)
    return rows


def close(actual: float, expected: float) -> None:
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), (actual, expected)


def record(odo: float, energy: float, day: int = 1, cost: float = 0.0) -> dict:
    return {"id": f"{odo}-{day}", "date": f"2026-10-{day:02d}T00:00:00Z",
            "createdAt": f"2026-10-{day:02d}T00:00:00Z", "odometerKm": odo,
            "energyKWh": energy, "costCNY": cost}


def test_fixture(payload: dict) -> list[dict]:
    rows = derive(payload["records"])
    assert len(rows) == len(payload["records"])
    by_date_odo = {(r["record"]["date"][:10], r["record"]["odometerKm"]): r for r in rows}
    short = by_date_odo[("2026-10-17", 1553)]
    settle = by_date_odo[("2026-10-21", 1809)]
    second = by_date_odo[("2026-10-24", 2044)]
    assert short["kind"] == "pending" and short["consumption"] is None
    assert second["kind"] == "pending" and second["consumption"] is None
    close(by_date_odo[("2026-10-24", 2028)]["groupDistance"], 235)
    close(settle["groupDistance"], 258)
    close(settle["consumption"], (4.8 + 23.1) / 258 * 100)
    close(by_date_odo[("2026-10-24", 2028)]["consumption"], (28.4 + 11) / 235 * 100)
    close(sum(r["distance"] or 0 for r in rows), 2044 - 508)
    close(sum(r["record"]["energyKWh"] for r in rows),
          sum(r["energyKWh"] for r in payload["records"]))
    return rows


def test_edges() -> None:
    # A long, genuinely high-consumption interval must remain visible and excluded.
    rows = derive([record(100, 0), record(300, 100, 2)])
    close(rows[-1]["consumption"], 50)
    assert not 5 <= rows[-1]["consumption"] <= 40

    # A short but plausible interval is not deferred.
    rows = derive([record(100, 0), record(120, 2, 2)])
    assert rows[-1]["kind"] == "ok"
    close(rows[-1]["consumption"], 10)

    # Multiple implausible short intervals settle as one group with one energy sum.
    rows = derive([record(100, 0), record(110, 5, 2, 5), record(120, 5, 3, 5), record(220, 20, 4, 20)])
    assert [r["kind"] for r in rows[1:]] == ["pending", "pending", "ok"]
    close(rows[-1]["groupDistance"], 120)
    close(rows[-1]["consumption"], 25)
    close(rows[-1]["cost"], 0.25)

    # A final short interval folds backward into the previous normal interval.
    rows = derive([record(100, 0), record(300, 20, 2), record(316, 11, 3)])
    assert rows[-1]["kind"] == "pending" and rows[-1]["consumption"] is None
    close(rows[-2]["groupDistance"], 216)
    close(rows[-2]["consumption"], 31 / 216 * 100)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("backup", type=Path)
    args = parser.parse_args()
    payload = json.loads(args.backup.read_text(encoding="utf-8-sig"))
    rows = test_fixture(payload)
    test_edges()
    print("PASS: supplied backup + 4 edge cases")
    for row in rows:
        r = row["record"]
        consumption = "—" if row["consumption"] is None else f"{row['consumption']:.2f}"
        print(f"{r['date'][:10]} | {r['odometerKm']:g} km | {row['distance'] or 0:g} km | {consumption}")


if __name__ == "__main__":
    main()
