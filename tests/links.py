#!/usr/bin/env python3
"""Check every link in the tracked markdown files.

Run it by hand - it needs the network, so it is not part of `tests/run.sh`:

    python3 tests/links.py

Two kinds:
  * anchors (#foo)  - resolved against the headings of the same file, using
                      GitHub's slug rules, so a rename that orphans a
                      cross-reference is caught offline.
  * URLs            - fetched, and reported by status code.

Read-only. Nothing here changes a file.
"""
import concurrent.futures
import re
import subprocess
import sys
import urllib.error
import urllib.request

FILES = [
    f for f in subprocess.check_output(["git", "ls-files", "*.md"], text=True).split()
    if not f.startswith(("latest/", "stable/"))
]

INLINE = re.compile(r"\[[^\]]*\]\(\s*<?([^)\s>]+)>?\s*(?:\"[^\"]*\")?\)")
REFDEF = re.compile(r"^\[[^\]]+\]:\s*<?(\S+)>?", re.M)
AUTOLINK = re.compile(r"<(https?://[^>\s]+)>")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*$", re.M)
# Fenced code blocks - links inside them are examples, not navigation.
FENCE = re.compile(r"```.*?```", re.S)
BARE = re.compile(r"https?://[^\s`'\"<>()\\]+")


def slug(text):
    """GitHub's heading -> anchor rule, near enough for our headings."""
    s = text.strip().lower()
    s = re.sub(r"[`*_~\[\]()]", "", s)          # inline markup
    s = re.sub(r"[^\w\s-]", "", s)              # punctuation
    return re.sub(r"\s+", "-", s.strip())


def links_of(path):
    raw = open(path, encoding="utf-8").read()
    body = FENCE.sub("", raw)
    out = set()
    for pat in (INLINE, AUTOLINK):
        out |= set(pat.findall(body))
    out |= set(REFDEF.findall(raw))             # ref defs live outside fences
    # Bare URLs inside fenced blocks are instructions a reader will paste - a
    # `git clone` of a repository that does not exist fails just as loudly as
    # a broken link, and hid here until 2026-08-27.
    fenced = set()
    for block in FENCE.findall(raw):
        fenced |= {u.rstrip(".,;:)\"'") for u in BARE.findall(block)}
    return raw, out, fenced - out


def check_url(url):
    req = urllib.request.Request(
        url, method="GET",
        headers={"User-Agent": "Mozilla/5.0 (link-check)"},
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return url, r.status, ""
    except urllib.error.HTTPError as e:
        return url, e.code, ""
    except Exception as e:                       # DNS, TLS, timeout
        return url, 0, type(e).__name__


# URLs that cannot be fetched and are not defects:
#   * anything holding a ${...} placeholder is a template the reader
#     substitutes - the resolved form is what must work, and does.
#   * starchart.cc answers 400 to any automated request, including for
#     torvalds/linux; it renders fine in a browser. Checked 2026-08-27.
def skip(url):
    return "${" in url or url.startswith("https://starchart.cc/")


anchor_problems = []
urls = {}
skipped = 0

fenced_urls = {}

for path in FILES:
    raw, found, fenced = links_of(path)
    for u in fenced:
        if skip(u):
            skipped += 1
            continue
        fenced_urls.setdefault(u, []).append(path)
    headings = {slug(m.group(2)) for m in HEADING.finditer(raw)}
    for link in found:
        if link.startswith("#"):
            if slug(link[1:]) not in headings:
                anchor_problems.append((path, link))
        elif link.startswith(("http://", "https://")):
            if skip(link):
                skipped += 1
                continue
            urls.setdefault(link, []).append(path)
        elif link.startswith("mailto:"):
            pass
        else:
            # relative path, possibly with an anchor
            target = link.split("#", 1)[0]
            if target and not subprocess.run(
                    ["test", "-e", target], capture_output=True).returncode == 0:
                anchor_problems.append((path, link + "   (missing file)"))

print(f"{len(FILES)} markdown files, {len(urls)} linked URLs, "
      f"{len(fenced_urls)} more inside code blocks, {skipped} skipped\n")

if anchor_problems:
    print("BROKEN ANCHORS / RELATIVE LINKS")
    for path, link in sorted(anchor_problems):
        print(f"  {path}: {link}")
else:
    print("anchors: all resolve")

print()
bad = []
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    for url, code, err in pool.map(check_url, urls):
        if code == 200:
            continue
        bad.append((code, err, url, urls[url]))

for url, code, err in __import__("concurrent.futures", fromlist=["x"]).ThreadPoolExecutor(
        max_workers=8).map(check_url, fenced_urls):
    if code != 200:
        bad.append((code, err, url, fenced_urls[url]))

if not bad:
    print("URLs: all 200 (links and code blocks)")
else:
    print("URLs NOT 200")
    for code, err, url, where in sorted(bad, key=lambda x: -x[0]):
        print(f"  {code or err:<6} {url}")
        for w in sorted(set(where)):
            print(f"         in {w}")

sys.exit(1 if (anchor_problems or bad) else 0)
