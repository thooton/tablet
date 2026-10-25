"""Glosses a plain Spanish text into a Biblioteca story with an LLM on OpenRouter.

    OPENROUTER_API_KEY=... python tools/gloss_story.py book.md --level B1 -o stories/src/book.txt
    python tools/gloss_story.py book.md --key-file ~/.config/openrouter/key ...

The text is split at paragraph boundaries into parts of at most --max-words
words. Each part is sent with the prompt in gloss-prompt.md, and its answer is
checked against the original (check_gloss.py). If the Spanish was changed, the
model is told where and asked again (--retries times). Parts are saved in
<output>.parts/ as they finish, so an interrupted run picks up where it left
off. Parts whose Spanish still differed are redone on the next run, as is any
part whose text changed.

Markdown headings (# Title, ## Capítulo 1) become plain paragraphs, and a
first-line "# Title" is the title unless --title is given.
"""
import argparse
import concurrent.futures
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_gloss import compare  # noqa: E402
from story_from_text import StoryError, parse_text  # noqa: E402

HERE = Path(__file__).resolve().parent
API = "https://openrouter.ai/api/v1/chat/completions"
HEADER = re.compile(r"^(title|title_en|level|author|description|id)\s*:")


def load_template() -> str:
    text = (HERE / "gloss-prompt.md").read_text(encoding="utf-8")
    return text.split("=====\n")[1].strip() + "\n"


def read_source(path: Path):
    """Returns (title from a leading '# ' line or None, list of paragraphs).

    Markdown is reduced to plain text: each line of a > quote (a letter, a
    list, a verse) becomes its own paragraph, and * emphasis is dropped.
    """
    text = path.read_text(encoding="utf-8").lstrip("\ufeff").replace("\r\n", "\n")
    title = None
    paragraphs = []
    for block in re.split(r"\n\s*\n", text):
        lines = [l.strip() for l in block.split("\n") if l.strip()]
        if not lines:
            continue
        if all(l.startswith(">") for l in lines):
            pieces = [l.lstrip(">").strip() for l in lines]
        else:
            pieces = [" ".join(lines)]
        for para in pieces:
            if re.fullmatch(r"(\*\s*){3,}", para):
                paragraphs.append("* * *")
                continue
            para = " ".join(para.replace("*", "").split())
            if not para:
                continue
            m = re.match(r"^(#+)\s*(.*)$", para)
            if m:
                if m.group(1) == "#" and title is None and not paragraphs:
                    title = m.group(2).strip()
                    continue
                para = m.group(2).strip()
            paragraphs.append(para)
    return title, paragraphs


def split_parts(paragraphs, max_words):
    parts, current, count = [], [], 0
    for para in paragraphs:
        n = len(para.split())
        if current and count + n > max_words:
            parts.append(current)
            current, count = [], 0
        current.append(para)
        count += n
    if current:
        parts.append(current)
    return parts


def clean_answer(answer: str):
    """Strips fences and chatter; returns (header dict, story body)."""
    lines = [l for l in answer.replace("\r\n", "\n").split("\n") if not l.strip().startswith("```")]
    while lines and not lines[0].strip():
        lines.pop(0)
    # Drop any preamble before the header or the first bracket.
    for i, line in enumerate(lines):
        if HEADER.match(line.strip()) or line.lstrip().startswith(("[", "—", "¿", "¡", "«", "“", "\"")):
            lines = lines[i:]
            break
    header = {}
    while lines and HEADER.match(lines[0].strip()):
        key, value = lines.pop(0).split(":", 1)
        header[key.strip()] = value.strip()
    return header, "\n".join(lines).strip() + "\n"


def call(messages, args, key, label, log):
    """Streams one answer, logging progress every 30 s; returns (text, usage)."""
    body = {
        "model": args.model,
        "messages": messages,
        "temperature": args.temperature,
        "max_tokens": args.max_tokens,
        "stream": True,
    }
    if args.reasoning != "default":
        body["reasoning"] = {"effort": args.reasoning}
    req = urllib.request.Request(API, data=json.dumps(body).encode(), headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "X-Title": "Biblioteca glosser",
    })
    for attempt in range(5):
        text, thought, usage, finish = [], 0, {}, None
        try:
            with urllib.request.urlopen(req, timeout=args.timeout) as resp:
                last = time.time()
                for raw in resp:
                    line = raw.decode("utf-8", errors="replace").strip()
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    chunk = json.loads(data)
                    if "error" in chunk:
                        raise RuntimeError(f"model error: {chunk['error'].get('message', chunk['error'])}")
                    usage = chunk.get("usage") or usage
                    for choice in chunk.get("choices", []):
                        delta = choice.get("delta", {})
                        text.append(delta.get("content") or "")
                        thought += len(delta.get("reasoning") or "")
                        finish = choice.get("finish_reason") or finish
                    if time.time() - last > 30:
                        last = time.time()
                        log(f"{label}: {sum(map(len, text))} characters written"
                            + (f", {thought} thinking" if thought else ""))
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            if e.code in (429, 500, 502, 503, 504) and attempt < 4:
                time.sleep(10 * (attempt + 1))
                continue
            raise RuntimeError(f"HTTP {e.code}: {detail}") from None
        except (urllib.error.URLError, TimeoutError, ConnectionError, json.JSONDecodeError) as e:
            if attempt < 4:
                log(f"{label}: connection problem ({e}); retrying")
                time.sleep(10 * (attempt + 1))
                continue
            raise RuntimeError(f"request failed: {e}") from None
        if finish == "length":
            raise RuntimeError(f"{label}: answer cut off at max_tokens; lower --max-words or raise --max-tokens")
        return "".join(text), usage


def gloss_part(index, total, paragraphs, args, key, template, meta, parts_dir, log):
    out = parts_dir / f"part-{index:03d}.txt"
    plain = "\n\n".join(paragraphs) + "\n"
    plain_file = parts_dir / f"plain-{index:03d}.txt"
    info_file = parts_dir / f"part-{index:03d}.json"
    if out.exists() and info_file.exists() and plain_file.exists() \
            and plain_file.read_text(encoding="utf-8") == plain:
        info = json.loads(info_file.read_text(encoding="utf-8"))
        if not info["problems"]:
            log(f"part {index}/{total}: already done")
            return index, info
    plain_file.write_text(plain, encoding="utf-8")

    prompt = (template.replace("{{TITLE}}", meta["title"]).replace("{{AUTHOR}}", meta["author"])
              .replace("{{LEVEL}}", meta["level"]).replace("{{STORY}}", plain.strip()))
    if total > 1:
        prompt = prompt.replace("END OF STORY", f"END OF STORY (part {index} of {total}; gloss only this part)")
    messages = [{"role": "user", "content": prompt}]
    best = None
    for round_ in range(args.retries + 1):
        started = time.time()
        answer, usage = call(messages, args, key, f"part {index}/{total}", log)
        header, body = clean_answer(answer)
        try:
            _, diffs, warnings, n_pairs, _, n_words = compare(plain, "title: x\n\n" + body)
            problem = diffs
        except StoryError as e:
            diffs, warnings, n_pairs, n_words = None, [], 0, len(plain.split())
            problem = [str(e).replace("x, ", "", 1)]
        log(f"part {index}/{total}: round {round_ + 1}, {n_pairs} pairs, "
            + ("Spanish matches" if not problem else f"{len(problem)} problem(s)")
            + f" ({time.time() - started:.0f} s, {usage.get('completion_tokens', '?')} tokens out)")
        score = len(problem) if diffs is not None else 10 ** 6
        if best is None or score < best["score"]:
            best = {"score": score, "header": header, "body": body, "problems": problem, "warnings": warnings}
        if not problem:
            break
        messages += [
            {"role": "assistant", "content": answer},
            {"role": "user", "content":
                "Your file has these problems compared with the story:\n\n" + "\n".join(problem[:60])
                + "\n\nFix only those places, keeping the rules, and give the whole file again. "
                  "The Spanish must be the original story word for word."},
        ]
    if best["score"] >= 10 ** 6:
        raise RuntimeError(f"part {index}: answer never parsed: {best['problems'][0]}")
    out.write_text(best["body"], encoding="utf-8")
    (parts_dir / f"part-{index:03d}.json").write_text(json.dumps(
        {"header": best["header"], "problems": best["problems"], "warnings": best["warnings"]},
        ensure_ascii=False, indent=1), encoding="utf-8")
    return index, {"header": best["header"], "problems": best["problems"], "warnings": best["warnings"]}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", type=Path, help="plain Spanish text (.txt or .md)")
    ap.add_argument("-o", "--output", type=Path, help="glossed .txt (default: next to source)")
    ap.add_argument("--title")
    ap.add_argument("--title-en")
    ap.add_argument("--author", default="")
    ap.add_argument("--level", default="B1")
    ap.add_argument("--description")
    ap.add_argument("--model", default="deepseek/deepseek-v4.1-flash-1017")
    ap.add_argument("--max-words", type=int, default=1500)
    ap.add_argument("--max-tokens", type=int, default=120000)
    ap.add_argument("--temperature", type=float, default=0.2)
    ap.add_argument("--retries", type=int, default=3, help="repair rounds when the Spanish differs")
    ap.add_argument("--jobs", type=int, default=8, help="parts glossed at once")
    ap.add_argument("--timeout", type=int, default=300, help="seconds of silence before a request is retried")
    ap.add_argument("--reasoning", default="none", choices=["none", "minimal", "low", "medium", "high", "default"],
                    help="reasoning effort (default: none)")
    ap.add_argument("--key-file", type=Path)
    args = ap.parse_args()

    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if args.key_file:
        key = args.key_file.expanduser().read_text(encoding="utf-8").strip()
    if not key:
        print("No key: set OPENROUTER_API_KEY or pass --key-file.", file=sys.stderr)
        return 2

    title, paragraphs = read_source(args.source)
    if not paragraphs:
        print("The source has no text.", file=sys.stderr)
        return 2
    meta = {"title": args.title or title or args.source.stem, "author": args.author or "unknown",
            "level": args.level}
    output = args.output or args.source.with_suffix(".txt")
    if output.resolve() == args.source.resolve():
        output = output.with_name(output.stem + "-glossed.txt")
    parts_dir = output.with_name(output.name + ".parts")
    parts_dir.mkdir(parents=True, exist_ok=True)
    template = load_template()
    parts = split_parts(paragraphs, args.max_words)
    total = len(parts)
    print(f"{sum(len(p.split()) for p in paragraphs)} words in {total} part(s), model {args.model}"
          f" (reasoning {args.reasoning})", flush=True)

    def log(msg):
        print(msg, flush=True)

    results, failed = {}, []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = [pool.submit(gloss_part, i + 1, total, p, args, key, template, meta, parts_dir, log)
                   for i, p in enumerate(parts)]
        for f in concurrent.futures.as_completed(futures):
            try:
                i, info = f.result()
                results[i] = info
            except RuntimeError as e:
                print(f"ERROR: {e}", file=sys.stderr)
                failed.append(str(e))
    if failed:
        print(f"{len(failed)} part(s) failed; run again to retry them.", file=sys.stderr)
        return 1

    first = results[1]["header"]
    header = {
        "title": meta["title"],
        "title_en": args.title_en or first.get("title_en", ""),
        "level": meta["level"],
        "author": args.author,
        "description": args.description or first.get("description", ""),
    }
    head = "".join(f"{k}: {v}\n" for k, v in header.items() if v)
    bodies = [(parts_dir / f"part-{i:03d}.txt").read_text(encoding="utf-8").strip() for i in range(1, total + 1)]
    text = head + "\n" + "\n\n".join(bodies) + "\n"
    story = parse_text(text, output.name)
    output.write_text(text, encoding="utf-8")

    problems = [(i, p) for i in range(1, total + 1) for p in results[i]["problems"]]
    print(f"wrote {output} ({len(story['content'])} pairs)")
    for i, p in problems:
        print(f"part {i}: {p}")
    if problems:
        print(f"{len(problems)} place(s) where the Spanish differs from the source; fix them in {output}.")
        return 1
    print("Spanish matches the source.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
