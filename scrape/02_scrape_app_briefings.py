"""Scrape White House press briefings from the American Presidency Project (UC Santa
Barbara), one row per briefing, full text with paragraph breaks kept.

Briefings are not in the GovInfo Compilation of Presidential Documents, and a daily
spokesperson Q&A is the closest US counterpart to the MFA press conferences. Every
briefing in the date range is kept, not only those mentioning China, so the China
share of briefings can serve as a salience measure; relevance filtering happens
downstream in R. The output has the same columns as 01_scrape_govinfo_presdocs.py.

The site's robots.txt asks for a 10-second crawl delay, so a full run takes about a
day. Every page is cached under raw/app_briefings/, so an interrupted run resumes
where it stopped.

Usage: .venv/bin/python scrape/02_scrape_app_briefings.py [--start 2002] [--end 2025] [--limit N]
"""
import argparse
import csv
import re
import sys
import time

import requests
from bs4 import BeautifulSoup

from config import RAW_DIR

BASE = "https://www.presidency.ucsb.edu"
LISTING = f"{BASE}/documents/app-categories/press-office/press-releases/press-briefings"
PER_PAGE = 60
CRAWL_DELAY = 10  # seconds, from robots.txt
CACHE = RAW_DIR / "app_briefings"
OUT = RAW_DIR / "02_app_briefings.csv"
FIELDS = ["doc_id", "collection", "date", "title", "president", "category",
          "subjects", "location", "notes", "n_chars", "text", "url"]

session = requests.Session()
session.headers["User-Agent"] = "honors-thesis academic research scraper (python-requests)"
last_request = 0.0


def get(url, **kwargs):
    """GET with the crawl delay between requests and retries on 429, server errors and
    dropped connections (wifi blips, or the laptop sleeping mid-request)."""
    global last_request
    for attempt in range(6):
        time.sleep(max(0, last_request + CRAWL_DELAY - time.time()))
        last_request = time.time()
        try:
            r = session.get(url, timeout=60, **kwargs)
        except (requests.ConnectionError, requests.Timeout) as e:
            r, problem = None, type(e).__name__
        else:
            problem = f"HTTP {r.status_code}"
        if r is None or r.status_code == 429 or r.status_code >= 500:
            wait = 60 * 2 ** attempt
            print(f"  {problem}, sleeping {wait}s", file=sys.stderr)
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r
    raise RuntimeError(f"giving up on {url}")


def cached(path, fetch):
    """Return the cached text at path, fetching and saving it first if missing."""
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(fetch())
    return path.read_text()


def listing_page(n):
    """Rows (date, title, president, url) on page n of the briefings listing.

    New briefings are added at the top, so a listing page fetched in a later run can
    only overlap a cached one, never skip past it; duplicates are dropped in main().
    Delete raw/app_briefings/listing/ to pick up briefings added since the last run.
    """
    soup = BeautifulSoup(cached(CACHE / "listing" / f"{n:04d}.html",
                                lambda: get(LISTING, params={"items_per_page": PER_PAGE,
                                                             "page": n}).text),
                         "html.parser")
    rows = []
    for item in soup.select("div.view-content div.node-teaser"):
        link = item.select_one("div.field-title a")
        president = item.select_one('a[href^="/people/president/"]')
        rows.append({
            "date": item.select_one("span.date-display-single")["content"][:10],
            "title": link.get_text(strip=True),
            "president": president.get_text(strip=True) if president else "",
            "url": BASE + link["href"],
        })
    return rows


def clean(s):
    return " ".join(s.split())


def build_row(listed):
    slug = listed["url"].rsplit("/", 1)[-1]
    soup = BeautifulSoup(cached(CACHE / "docs" / f"{slug}.html",
                                lambda: get(listed["url"]).text),
                         "html.parser")
    body = soup.select_one("div.field-docs-content")
    paragraphs = [clean(p.get_text()) for p in body.find_all("p")] if body else []
    text = "\n\n".join(p for p in paragraphs if p) or (body.get_text("\n", strip=True) if body else "")
    # The citation carries the stable node id; slugs can be renamed.
    citation = soup.select_one("p.ucsbapp_citation")
    node = re.search(r"/node/(\d+)", citation.get_text()) if citation else None
    title = soup.select_one("div.field-ds-doc-title h1")
    president = soup.select_one("div.field-docs-person h3.diet-title")
    location = soup.select_one("div.field-spot-state")
    return {
        "doc_id": f"APP-{node.group(1)}" if node else f"APP-{slug}",
        "collection": "APP",
        "date": listed["date"],
        "title": clean(title.get_text()) if title else listed["title"],
        "president": clean(president.get_text()) if president else listed["president"],
        "category": "; ".join(clean(a.get_text()) for a in soup.select('a[property~="rdfs:label"]')),
        "subjects": "",
        "location": clean(location.get_text()) if location else "",
        "notes": "",
        "n_chars": len(text),
        "text": text,
        "url": listed["url"],
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--start", type=int, default=2002)
    ap.add_argument("--end", type=int, default=2025)
    ap.add_argument("--limit", type=int, help="stop after this many documents (for testing)")
    args = ap.parse_args()

    # The listing is only roughly sorted by date, so walk all of it and filter.
    listed, seen, n = [], set(), 0
    while rows := listing_page(n):
        for row in rows:
            if row["url"] not in seen and args.start <= int(row["date"][:4]) <= args.end:
                seen.add(row["url"])
                listed.append(row)
        n += 1
        if args.limit and len(listed) >= args.limit:
            break
    print(f"{n} listing pages, {len(listed)} briefings in {args.start}-{args.end}")

    rows = []
    for item in sorted(listed, key=lambda r: r["date"])[:args.limit]:
        rows.append(build_row(item))
        if len(rows) % 100 == 0:
            print(f"  {len(rows)} documents")

    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} documents to {OUT}")


if __name__ == "__main__":
    main()
