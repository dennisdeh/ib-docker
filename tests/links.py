#!/usr/bin/env python3
"""Check every link in the tracked files - markdown and source alike.

Run it by hand - it needs the network, so it is not part of `tests/run.sh`:

    python3 tests/links.py

Three kinds:
  * anchors (#foo)  - resolved against the headings of the same file, using
                      GitHub's slug rules, so a rename that orphans a
                      cross-reference is caught offline.
  * URLs in markdown - fetched, and reported by status code.
  * URLs in comments - the same, for every other tracked text file. A comment
                      citing an issue or a manual page is documentation too,
                      and nothing else ever reads it: the 2026-08-27 repository
                      rename rewrote an upstream issue link in
                      image-files/tws-scripts/run_tws.sh into this project's own
                      tracker, where it 404s. Markdown-only checking could not
                      see it, and it survived until 2026-08-28.

Read-only. Nothing here changes a file.
"""
import concurrent.futures
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

def tracked(*patterns):
    out = subprocess.check_output(["git", "ls-files", *patterns], text=True).split()
    # latest/ and stable/ are generated copies; a finding there is a duplicate
    # of one in image-files/ or in a template, and is fixed at the source.
    return [f for f in out if not f.startswith(("latest/", "stable/"))]


FILES = tracked("*.md")

# Everything else that is text. Binary files are skipped by the read below
# rather than by extension, so a new asset type needs no change here.
SOURCES = [f for f in tracked() if f not in set(FILES)]

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


# A URL written in shell, YAML or a regex carries its context with it. Two
# forms have to be trimmed before fetching, and neither is a defect:
#   * a trailing `$` - a regex anchor, as in a grep pattern asserting a label's
#     exact value;
#   * trailing punctuation that belongs to the surrounding sentence.
# A URL holding `${...}` is a template and is dropped by skip(), same as in the
# markdown.
def urls_in_source(path):
    try:
        raw = open(path, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        return set()                             # binary, or unreadable
    out = set()
    for u in BARE.findall(raw):
        u = u.rstrip("$").rstrip(".,;:)\"'")
        if u.startswith(("http://", "https://")) and len(u) > len("https://"):
            out.add(u)
    return out


# A connection-level failure is retried once; an HTTP status is not. Some hosts
# are simply slow to answer a cold connection - manpages.ubuntu.com took 38s on
# the first request and under 3s on the fourth, measured 2026-08-28 - and a
# checker that reports those as broken links is one people learn to ignore. A
# 404 is a 404 on the first try, so it is returned straight away.
def check_url(url, attempts=2, timeout=40):
    req = urllib.request.Request(
        url, method="GET",
        headers={"User-Agent": "Mozilla/5.0 (link-check)"},
    )
    err = ""
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return url, r.status, ""
        except urllib.error.HTTPError as e:
            # 429 is the server declining to answer this checker, not a
            # verdict on the link. news.ycombinator.com returns it after a
            # couple of runs and 200 on the next - measured 2026-08-29 - so
            # back off and try once more before reporting it.
            if e.code == 429 and attempt + 1 < attempts:
                err = "429"
                time.sleep(10)
                continue
            return url, e.code, ""
        except Exception as e:                   # DNS, TLS, timeout
            err = type(e).__name__
            if attempt + 1 < attempts:
                time.sleep(2)
    return url, 0, err


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

source_urls = {}
for path in SOURCES:
    for u in urls_in_source(path):
        if skip(u):
            skipped += 1
            continue
        # Already covered as a markdown link; check it once.
        if u in urls or u in fenced_urls:
            continue
        source_urls.setdefault(u, []).append(path)

print(f"{len(FILES)} markdown files, {len(urls)} linked URLs, "
      f"{len(fenced_urls)} more inside code blocks, {skipped} skipped")
print(f"{len(SOURCES)} source files, {len(source_urls)} URLs in comments "
      f"and strings\n")

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

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    for url, code, err in pool.map(check_url, fenced_urls):
        if code != 200:
            bad.append((code, err, url, fenced_urls[url]))

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    for url, code, err in pool.map(check_url, source_urls):
        if code != 200:
            bad.append((code, err, url, source_urls[url]))

# A link that answered 429 twice is one this checker was throttled out of,
# which is not evidence either way. Report it, but do not fail on it - a check
# that cries wolf is one people stop reading.
throttled = [b for b in bad if b[0] == 429]
bad = [b for b in bad if b[0] != 429]

if not bad:
    print("URLs: all 200 (markdown links, code blocks and source files)")
else:
    print("URLs NOT 200")
    for code, err, url, where in sorted(bad, key=lambda x: -x[0]):
        print(f"  {code or err:<6} {url}")
        for w in sorted(set(where)):
            print(f"         in {w}")

if throttled:
    print()
    print("rate-limited, not checked (429 twice; not counted as failures)")
    for code, err, url, where in throttled:
        print(f"  {url}")
        for w in sorted(set(where)):
            print(f"         in {w}")

sys.exit(1 if (anchor_problems or bad) else 0)
