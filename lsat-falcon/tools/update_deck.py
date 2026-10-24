"""Refreshes deck/ from the LSAT Falcon web app, after its
`npm run build:questions`:

    python tools/update_deck.py [../demon]

Copies src/generated/questions.json (gzipped), src/conversion.js and
src/held-out.js. Commit deck/ with a version bump: CI builds from it.
"""
import gzip
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT.parent.parent / "demon") / "src"
    deck = ROOT / "deck"
    deck.mkdir(exist_ok=True)
    data = (src / "generated" / "questions.json").read_bytes()
    with open(deck / "questions.json.gz", "wb") as raw:
        with gzip.GzipFile(fileobj=raw, mode="wb", compresslevel=9, mtime=0, filename="") as f:
            f.write(data)
    for name in ("conversion.js", "held-out.js"):
        shutil.copy(src / name, deck / name)
    print(f"deck/ updated from {src}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
