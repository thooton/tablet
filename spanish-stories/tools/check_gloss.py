"""Checks an LLM-glossed story against the plain Spanish it was given.

    python tools/check_gloss.py plain.txt glossed.txt

plain.txt is the story as given to the model (gloss-prompt.md); glossed.txt is
the model's answer in the story_from_text.py format. Reports parse errors,
every place the Spanish differs from the original (changed, added or missing
words), and lone articles or pronouns. Exit code 1 if the Spanish differs or
the file doesn't parse.
"""
import difflib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from story_from_text import StoryError, parse_text  # noqa: E402

LONE = {"el", "la", "los", "las", "un", "una", "unos", "unas", "su", "sus",
        "mi", "mis", "tu", "tus", "se", "lo", "le", "les", "me", "te", "nos"}


def words(text: str) -> list:
    return re.findall(r"[^\W_]+(?:\.(?=\s|$))?", text)


def compare(plain: str, glossed: str, name: str = "<glossed>"):
    """Returns (story, differences, warnings, pairs, words glossed, words in plain).

    Raises StoryError if glossed does not parse.
    """
    story = parse_text(glossed, name)
    pairs = [p for p in story["content"] if p[0] != "\n"]
    original = [w.rstrip(".") for w in words(plain)]
    got, where = [], []
    for n, (es, en) in enumerate(pairs):
        for w in words(es):
            got.append(w.rstrip("."))
            where.append(n)

    def context(n):
        return " ".join(f"[{es}|{en}]" if en else es for es, en in pairs[max(0, n - 2):n + 3])

    diffs = []
    sm = difflib.SequenceMatcher(None, original, got, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == "equal":
            continue
        before = " ".join(original[i1:i2]) or "(nothing)"
        after = " ".join(got[j1:j2]) or "(nothing)"
        at = where[min(j1, len(where) - 1)] if where else 0
        diffs.append(f"{op}: original {before!r} -> glossed {after!r}\n    near: {context(at)}")

    warnings = []
    for n, (es, en) in enumerate(pairs):
        if es.lower() in LONE:
            warnings.append(f"lone {es!r}: {context(n)}")
        if "|" in en:
            warnings.append(f"'|' in English: [{es}|{en}]")
    return story, diffs, warnings, len(pairs), len(got), len(original)


def main(argv) -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(argv) != 2:
        print(__doc__)
        return 2
    plain = Path(argv[0]).read_text(encoding="utf-8")
    glossed = Path(argv[1]).read_text(encoding="utf-8")
    try:
        _, diffs, warnings, n_pairs, n_got, n_orig = compare(plain, glossed, argv[1])
    except StoryError as e:
        print(f"ERROR: {e}")
        return 1
    for line in diffs + warnings:
        print(line)
    print(f"{n_pairs} pairs, {n_got} of {n_orig} words; "
          + ("Spanish matches." if not diffs else f"{len(diffs)} difference(s)."))
    return 1 if diffs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
