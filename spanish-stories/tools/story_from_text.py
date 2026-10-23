"""Turns a story written in the compact authoring format into a story .json.

    python tools/story_from_text.py stories/src/01-el-gato.txt [-o stories/01-el-gato.json]
    python tools/story_from_text.py --all      # every stories/src/*.txt -> stories/*.json

Authoring format (UTF-8 text):

    title: El gato perdido
    title_en: The Lost Cat
    level: A1
    description: Luna looks for her cat all over town.

    [Luna|Luna] [tiene|has] [un gato|a cat] [negro|black].
    —[¿Dónde|Where] [está|is] [Sol|Sol]? —[pregunta|asks] [Luna|Luna].

Header lines (key: value) come first, then a blank line, then the story.
Each [spanish|english] becomes one (spanish, english) pair; separate several
translations with " / ", e.g. [tiene|has / owns]. Anything outside brackets
must be punctuation and becomes an untranslated pair. A blank line starts a
new paragraph.
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPENING = "¿¡«“‘(\"'"
CLOSING = ".,;:!?»”’)…\"'"
HEADER_KEYS = {"id", "title", "title_en", "level", "description", "author"}


class StoryError(Exception):
    pass


def parse_text(text: str, name: str = "<story>") -> dict:
    text = text.lstrip("\ufeff").replace("\r\n", "\n")
    lines = text.split("\n")
    meta = {}
    i = 0
    while i < len(lines) and lines[i].strip():
        m = re.match(r"^([a-z_]+)\s*:\s*(.*)$", lines[i].strip())
        if not m or m.group(1) not in HEADER_KEYS:
            break
        meta[m.group(1)] = m.group(2).strip()
        i += 1
    body = "\n".join(lines[i:]).strip("\n")
    if not body.strip():
        raise StoryError(f"{name}: story text is empty")

    content = []
    paragraphs = re.split(r"\n\s*\n", body)
    for p_index, para in enumerate(paragraphs):
        if not para.strip():
            continue
        if content:
            content.append(["\n", ""])
        line_no = body[: body.find(para)].count("\n") + i + 1
        pos = 0
        while pos < len(para):
            ch = para[pos]
            if ch.isspace():
                pos += 1
                continue
            if ch == "[":
                end = para.find("]", pos)
                if end < 0:
                    raise StoryError(f"{name}, paragraph {p_index + 1}: unclosed '[' near {para[pos:pos + 30]!r}")
                inner = para[pos + 1:end]
                if "|" not in inner:
                    raise StoryError(f"{name}, paragraph {p_index + 1}: [{inner}] has no '|english' part")
                es, en = inner.split("|", 1)
                es = " ".join(es.split())
                en = " ".join(en.split())
                # Opening/closing punctuation typed inside the brackets
                # ([¿Dónde|Where]) is moved out so only the words are tappable.
                lead = re.match(r"^[" + OPENING + r"]*", es).group(0)
                trail = re.search(r"[" + CLOSING + r"]*$", es[len(lead):]).group(0)
                es = es[len(lead):len(es) - len(trail)].strip()
                if not es or not en:
                    raise StoryError(f"{name}, paragraph {p_index + 1}: empty side in [{inner}]")
                if lead:
                    content.append([lead, ""])
                content.append([es, en])
                if trail:
                    content.append([trail, ""])
                pos = end + 1
                continue
            # A run of punctuation outside brackets.
            m = re.match(r"[^\s\[\]]+", para[pos:])
            run = m.group(0)
            if re.search(r"\w", run):
                raise StoryError(
                    f"{name} (around line {line_no}): untranslated text {run!r} - wrap words as [spanish|english]")
            content.append([run, ""])
            pos += len(run)

    story = {k: meta[k] for k in ("id", "title", "title_en", "level", "description", "author") if k in meta}
    story["content"] = content
    return story


def dump_story(story: dict) -> str:
    """JSON with one (spanish, english) pair per line, easy to read and diff."""
    head = {k: v for k, v in story.items() if k != "content"}
    out = ["{"]
    for k, v in head.items():
        out.append(f"  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)},")
    out.append('  "content": [')
    pairs = [f"    {json.dumps(pair, ensure_ascii=False)}" for pair in story["content"]]
    out.append(",\n".join(pairs))
    out.append("  ]")
    out.append("}")
    return "\n".join(out) + "\n"


def convert(src: Path, dst: Path) -> int:
    story = parse_text(src.read_text(encoding="utf-8"), src.name)
    dst.write_text(dump_story(story), encoding="utf-8", newline="\n")
    return len(story["content"])


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="?", type=Path)
    ap.add_argument("-o", "--output", type=Path)
    ap.add_argument("--all", action="store_true", help="convert every stories/src/*.txt")
    args = ap.parse_args()

    jobs = []
    if args.all:
        jobs = [(src, ROOT / "stories" / (src.stem + ".json")) for src in sorted((ROOT / "stories" / "src").glob("*.txt"))]
    elif args.source:
        jobs = [(args.source, args.output or args.source.with_suffix(".json"))]
    else:
        ap.print_help()
        return 2

    failed = False
    for src, dst in jobs:
        try:
            n = convert(src, dst)
            print(f"{src.name} -> {dst.name} ({n} pairs)")
        except StoryError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
