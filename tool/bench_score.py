#!/usr/bin/env python3
"""Score the OCR importer benchmark output against the fixture truth.

Reads build/bench3_out.json and build/bench4_out.json (written by
test/bench3_round_test.dart and test/bench4_round_test.dart) and compares each
tier with test/fixtures/bench{3,4}_truth.json.

Three subject views are reported for every tier:

  class  the right class was identified, even if the subject text carries OCR
         noise or is truncated ("followed by Science at in" still counts as
         Science; "History" counts as "World History")
  clean  the subject text is usable as-is: exact, or a truncation of the truth
         subject ("History" for "World History", "Library" for "Library
         period"), but not contaminated with extra words
  exact  the subject matches the truth verbatim after case/punctuation
         normalisation

The slot/time buckets follow BENCHMARK_ROUND3.md:

  full      subject + day + start + end all match
  time-off  subject + day match, time is wrong
  day-off   subject + time match, day is wrong
  other     subject matches but day and time are both wrong
  missed    truth row has no counterpart
  FP        predicted row has no counterpart

Usage:
  python tool/bench_score.py                 # score both benches
  python tool/bench_score.py --bench bench4  # score one bench
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test" / "fixtures"
BUILD = ROOT / "build"

DAY_ALIASES = {
    "mon": 1, "monday": 1,
    "tue": 2, "tues": 2, "tuesday": 2,
    "wed": 3, "weds": 3, "wednesday": 3,
    "thu": 4, "thur": 4, "thurs": 4, "thursday": 4,
    "fri": 5, "friday": 5,
    "sat": 6, "saturday": 6,
    "sun": 7, "sunday": 7,
}
DAY_LABEL = {1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"}

BUCKETS = ("full", "time_off", "day_off", "other")
COUNTS = BUCKETS + ("missed", "fp", "slot_matched", "slot_missed", "slot_fp")

# Extra subject words that describe the class rather than contaminate it
# ("Biology lab" for truth "Biology"). OCR noise such as "Science e" is not
# in this set and therefore fails the clean check.
DESCRIPTIVE_TOKENS = {
    "lab", "room", "class", "workshop", "training", "club", "assembly",
    "period", "subject",
}


def norm_day(value) -> int | None:
    if isinstance(value, int):
        return value if 1 <= value <= 7 else None
    if isinstance(value, float) and value.is_integer():
        return int(value) if 1 <= int(value) <= 7 else None
    key = re.sub(r"[^a-z]", "", str(value).lower())
    return DAY_ALIASES.get(key)


def parse_minutes(value) -> int | None:
    if isinstance(value, (int, float)):
        return int(value)
    text = str(value).strip()
    match = re.search(r"(\d{1,2})[:.](\d{2})\s*(am|pm)?", text, re.I)
    if not match:
        return None
    hour = int(match.group(1))
    minute = int(match.group(2))
    suffix = (match.group(3) or "").lower()
    if suffix == "pm" and hour < 12:
        hour += 12
    elif suffix == "am" and hour == 12:
        hour = 0
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return None
    return hour * 60 + minute


def subject_key(value: str) -> str:
    text = str(value).lower().replace("&", " and ")
    text = text.replace(".", "").replace("'", "")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    if text.startswith("the "):
        text = text[4:]
    return text


def subject_exact(truth: str, pred: str) -> bool:
    return subject_key(truth) == subject_key(pred)


def subject_clean(truth: str, pred: str) -> bool:
    """Pred is exact or a clean truncation of truth; no extra words."""
    kt, kp = subject_key(truth), subject_key(pred)
    if not kt or not kp:
        return False
    if kt == kp:
        return True
    st, sp = set(kt.split()), set(kp.split())
    if sp <= st and min(len(token) for token in sp) >= 2:
        return True
    if st <= sp and (sp - st) <= DESCRIPTIVE_TOKENS:
        return True
    return len(kp) >= 4 and kt.startswith(kp)


def subject_match(truth: str, pred: str) -> bool:
    """Tolerant class identification for abbreviated/truncated/noisy OCR text."""
    kt, kp = subject_key(truth), subject_key(pred)
    if not kt or not kp:
        return False
    if kt == kp:
        return True
    st, sp = set(kt.split()), set(kp.split())
    if (st <= sp or sp <= st) and min(len(token) for token in (st if st <= sp else sp)) >= 2:
        return True
    short, long = (kt, kp) if len(kt) <= len(kp) else (kp, kt)
    if len(short) >= 4 and long.startswith(short):
        return True
    return SequenceMatcher(None, kt, kp).ratio() >= 0.82


def normalize_row(row: dict) -> dict:
    return {
        "subject": str(row.get("subject") or ""),
        "day": norm_day(row.get("day")),
        "start": parse_minutes(row.get("start")),
        "end": parse_minutes(row.get("end")),
        "raw": row,
    }


def pair_rows(truth_rows: list[dict], pred_rows: list[dict], matcher) -> dict:
    """One-to-one subject-anchored matching, best (slot + subject) first."""
    truth = [normalize_row(r) for r in truth_rows]
    pred = [normalize_row(r) for r in pred_rows]

    pairs = []
    for ti, t in enumerate(truth):
        for pi, p in enumerate(pred):
            if not matcher(t["subject"], p["subject"]):
                continue
            same_day = t["day"] is not None and t["day"] == p["day"]
            same_time = (
                t["start"] is not None
                and t["start"] == p["start"]
                and t["end"] is not None
                and t["end"] == p["end"]
            )
            if same_day and same_time:
                score, bucket = 4, "full"
            elif same_day:
                score, bucket = 3, "time_off"
            elif same_time:
                score, bucket = 2, "day_off"
            else:
                score, bucket = 1, "other"
            pairs.append((score, ti, pi, bucket))

    pairs.sort(key=lambda item: (-item[0], item[1], item[2]))
    used_t: set[int] = set()
    used_p: set[int] = set()
    matches = []
    for score, ti, pi, bucket in pairs:
        if ti in used_t or pi in used_p:
            continue
        used_t.add(ti)
        used_p.add(pi)
        matches.append((ti, pi, bucket))

    # Slot-only matching (day + time, subject ignored) for a "did we find the
    # right time block at all" view. Subject match breaks ties.
    slot_pairs = []
    for ti, t in enumerate(truth):
        for pi, p in enumerate(pred):
            same_day = t["day"] is not None and t["day"] == p["day"]
            same_time = (
                t["start"] is not None
                and t["start"] == p["start"]
                and t["end"] is not None
                and t["end"] == p["end"]
            )
            if not (same_day and same_time):
                continue
            bonus = 1 if matcher(t["subject"], p["subject"]) else 0
            slot_pairs.append((bonus, ti, pi))
    slot_pairs.sort(key=lambda item: (-item[0], item[1], item[2]))
    slot_t: set[int] = set()
    slot_p: set[int] = set()
    slot_matches = []
    for _, ti, pi in slot_pairs:
        if ti in slot_t or pi in slot_p:
            continue
        slot_t.add(ti)
        slot_p.add(pi)
        slot_matches.append((ti, pi))

    counts = {bucket: 0 for bucket in BUCKETS}
    for _, _, bucket in matches:
        counts[bucket] += 1
    counts["missed"] = len(truth) - len(matches)
    counts["fp"] = len(pred) - len(matches)
    counts["slot_matched"] = len(slot_matches)
    counts["slot_missed"] = len(truth) - len(slot_matches)
    counts["slot_fp"] = len(pred) - len(slot_matches)

    return {
        "n": len(truth),
        "pred": len(pred),
        **counts,
        "matches": matches,
        "truth": truth,
        "pred_rows": pred,
    }


def pct(num: int, den: int) -> float:
    return (100.0 * num / den) if den else 0.0


def rows_from_entry(bench: str, entry: dict, tier: str) -> list[dict] | None:
    """Return the row list for a tier, or None when the tier did not run."""
    if bench == "bench4":
        if tier in ("t2a", "t2b"):
            node = (entry.get("t2") or {}).get(tier)
            return (node or {}).get("rows")
        if tier in ("t1", "t2"):
            node = entry.get(tier)
            return (node or {}).get("rows")
        node = entry.get(tier)
        return node if isinstance(node, list) else None
    node = entry.get(tier)
    return node if isinstance(node, list) else None


def slim(result: dict) -> dict:
    return {key: result[key] for key in ("n", "pred", *COUNTS)}


def score_bench(bench: str) -> dict:
    truth = json.loads((FIXTURES / f"{bench}_truth.json").read_text(encoding="utf-8"))
    out_path = BUILD / f"{bench}_out.json"
    if not out_path.exists():
        raise SystemExit(f"missing {out_path}; run the matching flutter test first")
    out = json.loads(out_path.read_text(encoding="utf-8"))

    tesseract = shutil.which("tesseract") is not None
    tiers = (
        ["t1", "t2", "t2a", "t2b", "t3"]
        if bench == "bench4"
        else ["t1", "t2a", "t2b", "t3"]
    )
    variants = {
        "class": subject_match,
        "clean": subject_clean,
        "exact": subject_exact,
    }

    report = {"bench": bench, "tiers": {}}
    for tier in tiers:
        photos = {}
        for photo, meta in truth.items():
            rows = rows_from_entry(bench, out.get(photo, {}), tier)
            if rows is None:
                continue
            results = {
                name: pair_rows(meta["truth_classes"], rows, matcher)
                for name, matcher in variants.items()
            }
            photos[photo] = {
                "style": meta.get("style", "unknown"),
                "n": results["class"]["n"],
                "pred": results["class"]["pred"],
                **{name: slim(result) for name, result in results.items()},
                "matches": results["class"]["matches"],
                "truth_rows": results["class"]["truth"],
                "pred_rows": results["class"]["pred_rows"],
            }

        # A tier where every photo returned zero rows is not a measurement when
        # the OCR proxy itself is absent.
        measured = any(p["pred"] > 0 for p in photos.values())
        status = "ok"
        if tier == "t3" and not measured:
            status = "not_measurable" if not tesseract else "empty"
        report["tiers"][tier] = {
            "status": status,
            "photos": photos,
            "summary": summarize(photos),
        }
    return report


def summarize(photos: dict) -> dict:
    totals = {name: {key: 0 for key in ("n", "pred", *COUNTS)} for name in ("class", "clean", "exact")}
    styles: dict[str, dict] = {}

    for p in photos.values():
        for name in totals:
            totals[name]["n"] += p["n"]
            totals[name]["pred"] += p["pred"]
            for key in COUNTS:
                totals[name][key] += p[name][key]

        bucket = styles.setdefault(
            p["style"],
            {
                "photos": 0,
                "n": 0,
                "pred": 0,
                "class": {key: 0 for key in COUNTS},
                "clean": {key: 0 for key in COUNTS},
                "exact": {key: 0 for key in COUNTS},
            },
        )
        bucket["photos"] += 1
        bucket["n"] += p["n"]
        bucket["pred"] += p["pred"]
        for name in ("class", "clean", "exact"):
            for key in COUNTS:
                bucket[name][key] += p[name][key]

    for name in totals:
        t = totals[name]
        t["full_pct"] = pct(t["full"], t["n"])
        t["slot_pct"] = pct(t["slot_matched"], t["n"])
        t["full_precision"] = pct(t["full"], t["pred"])

    for bucket in styles.values():
        for name in ("class", "clean", "exact"):
            bucket[name]["full_pct"] = pct(bucket[name]["full"], bucket["n"])
            bucket[name]["slot_pct"] = pct(bucket[name]["slot_matched"], bucket["n"])

    return {
        "photos": len(photos),
        "n": totals["class"]["n"],
        "pred": totals["class"]["pred"],
        "class": totals["class"],
        "clean": totals["clean"],
        "exact": totals["exact"],
        "styles": styles,
    }


def fmt_time(minutes) -> str:
    if minutes is None:
        return "??:??"
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def describe(row: dict) -> str:
    return (
        f"{DAY_LABEL.get(row['day'], '?')} {fmt_time(row['start'])}-"
        f"{fmt_time(row['end'])} {row['subject']!r}"
    )


def print_table(report: dict) -> None:
    bench = report["bench"]
    label = "NON-TIMETABLE" if bench == "bench4" else "TIMETABLE"
    print(f"\n{'=' * 100}")
    print(f"{bench.upper()} ({label})")
    print("=" * 100)

    for tier, data in report["tiers"].items():
        summary = data["summary"]
        if not data["photos"]:
            print(f"\n[{tier}] no output (tier did not run in this checkout)")
            continue
        status = data["status"]
        note = "" if status == "ok" else f"  ({status})"
        cls, clean, exact = summary["class"], summary["clean"], summary["exact"]
        print(
            f"\n[{tier}] {len(data['photos'])} photos, {summary['n']} truth rows, "
            f"{summary['pred']} predicted{note}"
        )
        print(
            f"  class {cls['full']}/{summary['n']} ({cls['full_pct']:.1f}%)  "
            f"clean {clean['full']}/{summary['n']} ({clean['full_pct']:.1f}%)  "
            f"exact {exact['full']}/{summary['n']} ({exact['full_pct']:.1f}%)  "
            f"slot {cls['slot_matched']}/{summary['n']} ({cls['slot_pct']:.1f}%)"
        )
        print(
            f"  time-off {cls['time_off']}  day-off {cls['day_off']}  "
            f"other {cls['other']}  missed {cls['missed']}  FP {cls['fp']}"
        )
        if summary["pred"]:
            print(f"  full-row precision (class) {cls['full_precision']:.1f}%")

        print(
            f"  {'style':<22} {'n':>4} {'pred':>5} {'class%':>7} {'clean%':>7} "
            f"{'slot%':>6} {'t-off':>5} {'d-off':>5} {'miss':>5} {'FP':>4}"
        )
        for style, s in sorted(summary["styles"].items()):
            print(
                f"  {style:<22} {s['n']:>4} {s['pred']:>5} "
                f"{s['class']['full_pct']:>6.1f}% {s['clean']['full_pct']:>6.1f}% "
                f"{s['class']['slot_pct']:>5.1f}% {s['class']['time_off']:>5} "
                f"{s['class']['day_off']:>5} {s['class']['missed']:>5} "
                f"{s['class']['fp']:>4}"
            )

    # Per-photo detail with the actual misses/extras.
    print(f"\n{bench.upper()} per-photo detail (class view)")
    for tier, data in report["tiers"].items():
        if data["status"] != "ok":
            continue
        for photo, p in data["photos"].items():
            c = p["class"]
            print(
                f"  {photo:<28} {p['style']:<20} {tier:<4} "
                f"class {c['full']}/{p['n']:<3} clean {p['clean']['full']}/{p['n']:<3} "
                f"slot {c['slot_matched']}/{p['n']:<3} missed {c['missed']:<3} FP {c['fp']}"
            )
            for ti, pi, bucket in p["matches"]:
                if bucket != "full":
                    print(f"      {bucket:<9} truth {describe(p['truth_rows'][ti])}")
                    print(f"                pred  {describe(p['pred_rows'][pi])}")
            matched_t = {ti for ti, _, _ in p["matches"]}
            matched_p = {pi for _, pi, _ in p["matches"]}
            for ti, row in enumerate(p["truth_rows"]):
                if ti not in matched_t:
                    print(f"      missed    truth {describe(row)}")
            for pi, row in enumerate(p["pred_rows"]):
                if pi not in matched_p:
                    print(f"      FP        pred  {describe(row)}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bench", choices=["bench3", "bench4", "all"], default="all")
    args = parser.parse_args()

    benches = ["bench3", "bench4"] if args.bench == "all" else [args.bench]
    reports = [score_bench(bench) for bench in benches]

    for report in reports:
        print_table(report)

    slim_reports = []
    for report in reports:
        tiers = {}
        for tier, data in report["tiers"].items():
            tiers[tier] = {
                "status": data["status"],
                "summary": data["summary"],
                "photos": {
                    photo: {
                        "style": p["style"],
                        "n": p["n"],
                        "pred": p["pred"],
                        "class": p["class"],
                        "clean": p["clean"],
                        "exact": p["exact"],
                    }
                    for photo, p in data["photos"].items()
                },
            }
        slim_reports.append({"bench": report["bench"], "tiers": tiers})
    (BUILD / "bench_score.json").write_text(
        json.dumps(slim_reports, indent=1), encoding="utf-8"
    )
    print(f"\nWrote {BUILD / 'bench_score.json'}")


if __name__ == "__main__":
    main()
