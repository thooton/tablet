"""Compiles LSAT Falcon's question deck into the tablet's data files.

    python tools/build_data.py [--source deck]

Reads the web app's compiled deck and its LSAC conversion charts and
held-out list, from deck/ (questions.json.gz, conversion.js, held-out.js:
copies of the web app's, refreshed with tools/update_deck.py) or from a web
app checkout given as --source (src/generated/questions.json, written by its
`npm run build:questions`, src/conversion.js, src/held-out.js), and writes
three files to build/data/:

    meta.json    everything the UI needs up front: the per-question index
                 (test, section, number, difficulty, type, group, answer),
                 categories, passage groups, the test/section outline, the
                 practice exams and the conversion charts. The backend sends
                 this to the QML once, at startup.
    content.dat  the text: one JSON record per question (stem, choices,
                 answer stats, explanation), then one JSON string per passage
                 group. Read on demand, one question at a time.
    content.idx  byte offsets into content.dat, for the backend only.

Nothing here decides anything the web app hasn't already decided: groups,
order, labels and exams are copied from the compiled deck as they are.
"""
import argparse
import gzip
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "data"
FORMAT = 2  # the web app's questions.json format this reads

# Glyphs the bundled fonts don't carry, mapped to ones they do. Roboto covers
# Latin; the symbol font bundled next to it (see generate_assets.py) covers
# → ← ↑ ↓ ≠ ✓. Everything else the corpus uses is in Roboto's Latin set.
REPLACE = {
    "➞": "→",  # ➞
    "➔": "→",  # ➔
    "✅": "✓",  # ✅
    "❌": "×",  # ❌
    "❓": "?",       # ❓
    "⎯": "—",  # ⎯
    "‑": "-",       # non-breaking hyphen
    " ": " ",       # narrow no-break space
    " ": "\n",      # line separator
    "₂": "2",       # subscript two (CO₂)
    "\U0001faa6": "",    # 🪦
}
REPLACE_RE = re.compile("|".join(re.escape(k) for k in REPLACE))


def clean(text):
    if text is None:
        return None
    return REPLACE_RE.sub(lambda m: REPLACE[m.group(0)], text)


def conversions(path: Path):
    """CONVERSIONS from conversion.js: `  101: [120,120,...],` per test."""
    table = {}
    for m in re.finditer(r"^\s*(\d+):\s*\[([\d,\s]+)\]", path.read_text(encoding="utf-8"), re.M):
        table[m.group(1)] = [int(v) for v in m.group(2).split(",") if v.strip()]
    if not table:
        sys.exit(f"no conversion charts found in {path}")
    return table


def held_out(path: Path):
    m = re.search(r"new Set\(\[([\d,\s]+)\]\)", path.read_text(encoding="utf-8"))
    if not m:
        sys.exit(f"cannot read HELD_OUT_TESTS from {path}")
    return [int(v) for v in m.group(1).split(",") if v.strip()]


def section_list(sections, exam=False):
    out = []
    for s in sections:
        item = {
            "key": s["key"],
            "label": s["label"],
            "section": s["section"],
            "experimental": bool(s["experimental"]),
            "qs": s["questions"],
        }
        if exam:
            item["name"] = s.get("name")
        out.append(item)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source", type=Path, default=ROOT / "deck",
                    help="deck/ (the default), or a web app checkout such as ../demon")
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()

    if (args.source / "questions.json.gz").exists():
        src = args.source
        with gzip.open(src / "questions.json.gz", "rt", encoding="utf-8") as f:
            deck = json.load(f)
    else:
        src = args.source / "src"
        deck = json.loads((src / "generated" / "questions.json").read_text(encoding="utf-8"))
    if deck.get("format") != FORMAT:
        sys.exit(f"questions.json is format {deck.get('format')}, expected {FORMAT}. "
                 f"Run `npm run build:questions` in {args.source}.")

    questions = deck["questions"]
    groups = deck["groups"]
    passages = deck["passages"]

    # Per question: [test, section, number, difficulty, category, group,
    # correct, experimental]. Positional to keep the startup message small.
    index = []
    for q in questions:
        index.append([
            q["test"], q["section"], q["number"], q["difficulty"] or 0,
            q["category"], q["group"], q["correctAnswer"], 1 if q["experimental"] else 0,
        ])

    meta = {
        "format": 1,
        "builtAt": deck["builtAt"],
        "deckTitle": deck["deckTitle"],
        "heldOut": held_out(src / "held-out.js"),
        "categories": [
            {"section": c["section"], "group": c["group"], "type": c["type"],
             "subtype": c["subtype"], "path": c["path"], "label": c["label"]}
            for c in deck["categories"]
        ],
        "q": index,
        # [isRC, number, [question indexes]]; a group's passage is its own record.
        "groups": [[1 if g["isRC"] else 0, g["number"], g["questions"]] for g in groups],
        "tests": [
            {"key": t["key"], "test": t["test"], "label": t["label"], "heldOut": bool(t.get("heldOut")),
             "sections": section_list(t["sections"])}
            for t in deck["tests"]
        ],
        "exams": [
            {"key": e["key"], "test": e["test"], "label": e["label"], "heldOut": bool(e.get("heldOut")),
             "sections": section_list(e["sections"], exam=True)}
            for e in deck["exams"]
        ],
        "conversions": conversions(src / "conversion.js"),
    }

    args.out.mkdir(parents=True, exist_ok=True)
    blob = bytearray()
    offsets = {"q": [], "g": []}

    def put(kind, value):
        data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        offsets[kind].append([len(blob), len(data)])
        blob.extend(data)

    for q in questions:
        put("q", {
            "q": clean(q["question"]),
            "a": {k: clean(v) for k, v in q["answers"].items()},
            "s": q.get("stats"),
            "e": clean(q["explanation"] or ""),
        })
    for g in groups:
        put("g", clean(passages[g["passage"]]))

    (args.out / "content.dat").write_bytes(blob)
    (args.out / "content.idx").write_text(json.dumps(offsets, separators=(",", ":")), encoding="utf-8")
    (args.out / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, separators=(",", ":")),
                                        encoding="utf-8")

    for name in ("meta.json", "content.dat", "content.idx"):
        print(f"  {name:12} {(args.out / name).stat().st_size:>12,} bytes")
    print(f"{len(questions)} questions, {len(groups)} groups, {len(meta['exams'])} exams, "
          f"{len(meta['conversions'])} conversion charts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
