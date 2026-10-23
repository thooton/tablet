"""Checks story files before they go onto the tablet.

    python tools/validate_stories.py [files...]     (default: stories/*.json)

Errors (exit code 1) are things the app cannot read. Warnings point at likely
authoring mistakes, such as a word without a translation or punctuation stuck
to a word.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LETTER = re.compile(r"[^\W\d_]")


def check(path: Path):
    errors, warnings = [], []
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e:
        return [f"cannot read: {e}"], []

    if isinstance(data, dict):
        content = data.get("content")
        if not data.get("title"):
            warnings.append('no "title" (the file name will be used)')
        for key in ("title", "title_en", "level", "description", "id", "author"):
            if key in data and not isinstance(data[key], str):
                errors.append(f'"{key}" must be a string')
    elif isinstance(data, list):
        content = data
    else:
        return ["file must contain a JSON object or array"], []

    if not isinstance(content, list) or not content:
        return errors + ['"content" must be a non-empty list of [spanish, english] pairs'], warnings

    words = 0
    for n, pair in enumerate(content, 1):
        if isinstance(pair, dict):
            pair = [pair.get("es"), pair.get("en")]
        if not isinstance(pair, list) or not 1 <= len(pair) <= 2:
            errors.append(f"entry {n}: expected [spanish, english], got {pair!r}")
            continue
        es = pair[0]
        en = pair[1] if len(pair) == 2 else ""
        if not isinstance(es, str) or not es:
            errors.append(f"entry {n}: spanish must be a non-empty string")
            continue
        if en is None:
            en = ""
        if isinstance(en, list):
            if not all(isinstance(x, str) for x in en):
                errors.append(f"entry {n} ({es!r}): english list must contain strings")
                continue
            en = " / ".join(en)
        if not isinstance(en, str):
            errors.append(f"entry {n} ({es!r}): english must be a string or list of strings")
            continue
        if es in ("\n", "\n\n", "¶"):
            continue
        has_letters = bool(LETTER.search(es))
        if has_letters:
            words += len(es.split())
            if not en.strip():
                warnings.append(f"entry {n}: {es!r} has no translation (it will not be tappable)")
            if re.search(r"[.,;:!?¿¡«»]", es):
                warnings.append(f"entry {n}: {es!r} contains punctuation - put punctuation in its own entry")
        if es != es.strip():
            warnings.append(f"entry {n}: {es!r} has leading/trailing spaces")
    return errors, warnings


def main(argv) -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    quiet = "--quiet" in argv
    files = [Path(a) for a in argv if not a.startswith("--")]
    if not files:
        files = sorted((ROOT / "stories").glob("*.json"))
    total_errors = 0
    for f in files:
        errors, warnings = check(f)
        total_errors += len(errors)
        if errors or warnings or not quiet:
            status = "ERROR" if errors else ("warnings" if warnings else "ok")
            print(f"{f.name}: {status}")
        for e in errors:
            print(f"   error: {e}")
        for w in warnings:
            print(f"   warning: {w}")
    if total_errors:
        print(f"{total_errors} error(s) found.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
