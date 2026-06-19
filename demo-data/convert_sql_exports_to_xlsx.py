#!/usr/bin/env python3
"""Convert the SQL demo CSV exports into compact .xlsx workbooks for RAG ingestion.

Document Intelligence layout does not parse raw .csv, so the structured demo
tables are surfaced as .xlsx documents under the ``sql-demo`` source. The large
tables are capped to a representative sample (exhaustive analytics are served by
the structured ``query_structured_data`` tool against the Synapse views), which
keeps each workbook small enough to ingest within the Functions HTTP timeout and
embedding throughput budget.
"""

from __future__ import annotations

import csv
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Font

ROOT = Path(__file__).resolve().parent
EXPORTS = ROOT / "sql" / "exports"
OUT = ROOT / "landing" / "sql-demo"
OUT.mkdir(parents=True, exist_ok=True)

# Per-table data-row cap (header excluded). Small tables are kept whole.
CAPS = {
    "customers": None,        # 300 rows — keep all
    "projects": None,         # 1200 rows — keep all
    "workorders": 800,        # 5000 -> sample
    "inspection_findings": 800,  # 9000 -> sample
    "telemetry_readings": 800,   # 20000 -> sample
}


def convert(name: str, cap: int | None) -> None:
    src = EXPORTS / f"{name}.csv"
    if not src.exists():
        print(f"skip {name}: {src} not found")
        return
    wb = Workbook()
    ws = wb.active
    ws.title = name[:31]
    with src.open(newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        header = next(reader)
        ws.append(header)
        for cell in ws[1]:
            cell.font = Font(bold=True)
        written = 0
        for row in reader:
            if cap is not None and written >= cap:
                break
            ws.append(row)
            written += 1
    dst = OUT / f"{name}.xlsx"
    wb.save(dst)
    print(f"{name}: wrote {written} rows -> {dst.relative_to(ROOT)}")


def main() -> None:
    for name, cap in CAPS.items():
        convert(name, cap)


if __name__ == "__main__":
    main()
