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


SOURCE_FILE = re.compile(r"test(\d+)-section(\d+)-(lr|rc)\.md#")


def repair(deck, held):
    """Puts back questions the web app's parser lost track of.

    A few LR section files open with a doubled front matter (`---` twice),
    and the web app's parser then reads none of their questions' test or
    section: it lumps them all into one group, with "---" as its passage,
    under an "Unlabeled" test, and leaves those sections out of their tests
    and practice exams. Here each such question gets its test and section
    back from its file name (its id), a group of its own with its stimulus as
    the passage (the parser left stimulus and stem together), and its place
    in its section, test and exam. Fix the files in the web app and this
    finds nothing to do.
    """
    qs, groups, passages = deck["questions"], deck["groups"], deck["passages"]
    lost = [i for i, q in enumerate(qs) if q["test"] is None and SOURCE_FILE.search(q["id"])]
    if not lost:
        return 0
    lost_set = set(lost)
    free = sorted({qs[i]["group"] for i in lost})  # the lumped groups, reused first
    sections = {}
    for i in lost:
        q = qs[i]
        m = SOURCE_FILE.search(q["id"])
        q["test"], q["section"] = int(m.group(1)), int(m.group(2))
        stimulus, sep, stem = q["question"].rpartition("\n\n")
        if sep:
            q["question"] = stem
        passages.append(stimulus.strip() if sep else "")
        g = {"number": q["number"], "isRC": m.group(3) == "rc", "passage": len(passages) - 1, "questions": [i]}
        if free:
            gi = free.pop(0)
            g["id"] = groups[gi]["id"]
            groups[gi] = g
        else:
            gi = len(groups)
            g["id"] = f"g{gi}"
            groups.append(g)
        q.update(group=gi, groupSize=1, indexInGroup=0, passage=g["passage"])
        sections.setdefault((q["test"], q["section"], m.group(3)), []).append(i)
    for gi in free:  # a lumped group with nothing left in it
        groups[gi]["questions"] = []

    def place(outline, make):
        # Out of wherever the parser put them ("Unlabeled")...
        for t in outline:
            for sec in t["sections"]:
                sec["questions"] = [i for i in sec["questions"] if i not in lost_set]
            t["sections"] = [sec for sec in t["sections"] if sec["questions"]]
            t["questions"] = [i for i in t["questions"] if i not in lost_set]
        outline[:] = [t for t in outline if t["questions"]]
        # ...and into their own sections.
        for (test, section, kind), members in sorted(sections.items()):
            t = next((t for t in outline if t["test"] == test), None) or make(test)
            if t is None:
                continue
            name = "Logical Reasoning" if kind == "lr" else "Reading Comprehension"
            members = sorted(members, key=lambda i: qs[i]["number"])
            t["sections"].append({
                "key": f"t-{test}-s-{section}", "test": test, "section": section, "experimental": False,
                "questions": members, "name": name, "number": f"Section {section}",
                "label": f"Section {section} | {name}",
            })
            t["sections"].sort(key=lambda sec: sec["section"] or 0)
            t["questions"] = [i for sec in t["sections"] for i in sec["questions"]]
            if "total" in t:
                t["total"] = len(t["questions"])

    def new_test(test):
        t = {"key": f"t-{test}", "test": test, "label": f"Test {test}", "questions": [], "sections": [],
             "heldOut": test in held}
        deck["tests"].append(t)
        deck["tests"].sort(key=lambda t: (t["test"] is None, t["test"] or 0))
        return t

    place(deck["tests"], new_test)
    place(deck["exams"], lambda test: None)  # only exams the web app already has
    return len(lost)


def section_list(sections, exam=False):
    out = []
    for s in sections:
        item = {
            "key": s["key"],
            # The web app's "Section 2 · Logical Reasoning": no · on the tablet.
            "label": s["label"].replace(" · ", " | "),
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

    repaired = repair(deck, set(held_out(src / "held-out.js")))
    if repaired:
        print(f"  repaired {repaired} questions the web app's parser left without a test")
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
