"""Scrape presidential documents that mention China from the GovInfo Compilation of
Presidential Documents (WCPD weekly issues through Jan 2009, DCPD after), one row per
document, full text.

Replaces the HeinOnline export (Presidential_Library.xlsx), which held search-hit
snippets rather than documents. Every API response is cached under
raw/govinfo_cpd/, so an interrupted run resumes where it stopped. The search terms
cast a wide net on purpose: relevance filtering happens downstream in R.

Usage: .venv/bin/python scrape/01_scrape_govinfo_presdocs.py [--start 2002] [--end 2025] [--limit N]
"""
import argparse
import csv
import html
import json
import re
import sys
import time

import requests

from config import GOVINFO_API_KEY, RAW_DIR

API = "https://api.govinfo.gov"
TERMS = '(China OR Chinese OR Beijing OR PRC OR Taiwan OR "Hong Kong" OR Tibet OR Xinjiang)'
CACHE = RAW_DIR / "govinfo_cpd"
OUT = RAW_DIR / "01_govinfo_presdocs.csv"
FIELDS = ["doc_id", "collection", "date", "title", "president", "category",
          "subjects", "location", "notes", "n_chars", "text", "url"]

session = requests.Session()


def call(method, url, **kwargs):
    """Request with retries; backs off on rate limiting (429) and server errors."""
    params = {**kwargs.pop("params", {}), "api_key": GOVINFO_API_KEY}
    for attempt in range(8):
        r = session.request(method, url, params=params, timeout=60, **kwargs)
        if r.status_code == 429 or r.status_code >= 500:
            wait = 600 if r.status_code == 429 else 2 ** attempt
            print(f"  HTTP {r.status_code}, sleeping {wait}s", file=sys.stderr)
            time.sleep(wait)
            continue
        r.raise_for_status()
        if int(r.headers.get("x-ratelimit-remaining", 100)) < 5:
            time.sleep(60)
        return r
    raise RuntimeError(f"giving up on {url}")


def cached(path, fetch):
    """Return the cached text at path, fetching and saving it first if missing."""
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(fetch())
    return path.read_text()


def search_year(year):
    """All search hits for one year, following the offsetMark cursor."""
    def fetch():
        hits, mark = [], "*"
        while True:
            body = {"query": f"collection:CPD AND {TERMS} AND "
                             f"publishdate:range({year}-01-01,{year}-12-31)",
                    "pageSize": 1000, "offsetMark": mark,
                    "sorts": [{"field": "publishdate", "sortOrder": "ASC"}]}
            d = call("POST", f"{API}/search", json=body).json()
            hits += d.get("results", [])
            if not d.get("results") or d.get("offsetMark") in (None, mark):
                return json.dumps(hits)
            mark = d["offsetMark"]
    return json.loads(cached(CACHE / "search" / f"{year}.json", fetch))


def extract_text(raw_html):
    """Plain text of a GovInfo document. WCPD is <pre>-wrapped text and is kept as is.
    DCPD is HTML converted from PDF with one <P> per paragraph; its line breaks sit
    inside the tags, so paragraphs are rebuilt as blank-line-separated blocks (speaker
    turns start at paragraph breaks, so they must survive)."""
    # Some pages are served without a charset and were decoded as Latin-1, so UTF-8
    # dashes and quotes arrive as mojibake ("â\x80\x94"). Undo that where it applies.
    try:
        raw_html = raw_html.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        pass
    m = re.search(r"<pre>(.*?)</pre>", raw_html, re.S | re.I)
    if m:
        return html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip()
    body = re.sub(r"\s+", " ", raw_html)
    body = re.sub(r"</?p\b[^>]*>", "\n\n", body, flags=re.I)
    text = html.unescape(re.sub(r"<[^>]+>", "", body))
    paras = (p.strip() for p in text.split("\n\n"))
    return "\n\n".join(p for p in paras if p)


def build_row(hit):
    doc_id = hit["granuleId"] or hit["packageId"]
    collection = doc_id.split("-")[0]  # WCPD or DCPD
    text = extract_text(cached(CACHE / "docs" / f"{doc_id}.htm",
                               lambda: call("GET", hit["download"]["txtLink"]).text))
    # Only DCPD carries subject tags and categories; WCPD granule summaries add
    # nothing beyond the search hit, so skip that request.
    meta = {}
    if collection == "DCPD":
        meta = json.loads(cached(CACHE / "docs" / f"{doc_id}.json",
                                 lambda: call("GET", hit["resultLink"]).text))
    names = meta.get("president", {}).get("names", [])
    return {
        "doc_id": doc_id,
        "collection": collection,
        # The hit's dateIssued is the document date; a WCPD granule summary only
        # has the weekly issue date.
        "date": hit["dateIssued"],
        "title": hit["title"],
        "president": next((n["authority-fnf"] for n in names if "authority-fnf" in n), ""),
        "category": "; ".join(c.get("level1", "") for c in meta.get("dcpdCategory", [])),
        "subjects": "; ".join(": ".join(v for k, v in sorted(s.items())) for s in meta.get("subject", [])),
        "location": meta.get("location", ""),
        "notes": meta.get("notes", ""),
        "n_chars": len(text),
        "text": text,
        "url": f"https://www.govinfo.gov/app/details/{hit['packageId']}"
               + (f"/{hit['granuleId']}" if hit["granuleId"] else ""),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--start", type=int, default=2002)
    ap.add_argument("--end", type=int, default=2025)
    ap.add_argument("--limit", type=int, help="stop after this many documents (for testing)")
    args = ap.parse_args()
    if GOVINFO_API_KEY == "DEMO_KEY":
        print("warning: GOVINFO_API_KEY not set; DEMO_KEY is limited to ~10 requests/hour",
              file=sys.stderr)

    seen, rows = set(), []
    for year in range(args.start, args.end + 1):
        hits = search_year(year)
        print(f"{year}: {len(hits)} hits")
        for hit in hits:
            doc_id = hit["granuleId"] or hit["packageId"]
            if doc_id in seen:
                continue
            seen.add(doc_id)
            rows.append(build_row(hit))
            if len(rows) % 100 == 0:
                print(f"  {len(rows)} documents")
            if args.limit and len(rows) >= args.limit:
                break
        if args.limit and len(rows) >= args.limit:
            break

    with open(OUT, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} documents to {OUT}")


if __name__ == "__main__":
    main()
