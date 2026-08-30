#!/usr/bin/env python3
"""Fetch and normalize Tela's curated public-domain artwork assets.

Sources are resolved through the Wikimedia Commons API.  The script only
accepts files explicitly marked Public domain or CC0 and writes a report with
the exact Commons page and license used for each bundled image.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "Scripts" / "public_domain_artworks.json"
ASSETS = ROOT / "Tela" / "Resources" / "Assets.xcassets"
REPORT = ROOT / "Tela" / "Resources" / "ArtworkDownloadReport.json"
API = "https://commons.wikimedia.org/w/api.php"
ALLOWED_LICENSES = {"Public domain", "CC0", "CC BY 4.0", "CC BY-SA 4.0", "CC BY-SA 3.0"}
USER_AGENT = "TelaArtCatalogBot/1.0 (https://github.com/pietroMastro92; offline artwork asset builder)"


def open_with_backoff(url: str, timeout: int = 60):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(5):
        try:
            return urllib.request.urlopen(request, timeout=timeout)
        except urllib.error.HTTPError as error:
            if error.code not in (429, 503) or attempt == 4:
                raise
            retry_after = error.headers.get("Retry-After")
            delay = int(retry_after) if retry_after and retry_after.isdigit() else min(60, 5 * (2 ** attempt))
            print(f"Rate limited; retrying in {delay}s", flush=True)
            time.sleep(delay)
    raise RuntimeError("unreachable")


def api(params: dict[str, str]) -> dict:
    url = API + "?" + urllib.parse.urlencode(params)
    with open_with_backoff(url, timeout=45) as response:
        return json.load(response)


def clean(value: str) -> str:
    value = re.sub(r"<[^>]+>", "", value or "")
    return re.sub(r"\s+", " ", value).strip()


def resolve(entry: dict) -> dict:
    params = {
        "action": "query",
        "prop": "imageinfo",
        "iiprop": "url|size|extmetadata",
        "iiurlwidth": "1800",
        "format": "json",
        "formatversion": "2",
    }
    if entry.get("commonsTitle"):
        params["titles"] = entry["commonsTitle"]
    else:
        params.update({
            "generator": "search",
            "gsrsearch": entry["query"] + " filetype:bitmap",
            "gsrnamespace": "6",
            "gsrlimit": "12",
        })
    data = api(params)
    pages = data.get("query", {}).get("pages", [])
    wanted = set(re.findall(r"[a-z0-9]+", (entry["artist"] + " " + entry["title"]).lower()))

    candidates = []
    for page in pages:
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {})
        license_name = clean(meta.get("LicenseShortName", {}).get("value", ""))
        if license_name not in ALLOWED_LICENSES:
            continue
        title = page.get("title", "")
        words = set(re.findall(r"[a-z0-9]+", title.lower()))
        score = len(wanted & words) * 10 + min(info.get("width", 0), info.get("height", 0)) / 1000
        lowered = title.lower()
        for discouraged in ("detail", "frame", "poster", "copy", "after ", "installation", "wall"):
            if discouraged in lowered:
                score -= 18
        candidates.append((score, page, info, meta, license_name))

    if not candidates:
        raise RuntimeError(f"No Public domain/CC0 image found for {entry['artist']} — {entry['title']}")
    _, page, info, meta, license_name = max(candidates, key=lambda item: item[0])
    return {
        "commonsTitle": page["title"],
        "commonsPage": info.get("descriptionurl"),
        "downloadURL": info.get("thumburl") or info["url"],
        "originalWidth": info.get("width", 0),
        "originalHeight": info.get("height", 0),
        "license": license_name,
        "artistCredit": clean(meta.get("Artist", {}).get("value", "")),
        "sourceCredit": clean(meta.get("Credit", {}).get("value", "")),
    }


def write_asset(entry: dict, resolved: dict) -> None:
    image_set = ASSETS / f"{entry['assetName']}.imageset"
    image_set.mkdir(parents=True, exist_ok=True)
    raw_path = image_set / "source-download"
    output_path = image_set / "artwork.jpg"
    with open_with_backoff(resolved["downloadURL"], timeout=90) as response, raw_path.open("wb") as output:
        output.write(response.read())
    subprocess.run([
        "magick", str(raw_path), "-auto-orient", "-resize", "1800x1800>",
        "-strip", "-sampling-factor", "4:2:0", "-quality", "84", str(output_path)
    ], check=True)
    raw_path.unlink()
    contents = {
        "images": [{"filename": "artwork.jpg", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": False},
    }
    (image_set / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> int:
    entries = json.loads(MANIFEST.read_text())
    previous_results = json.loads(REPORT.read_text()) if REPORT.exists() else []
    results = []
    for index, entry in enumerate(entries, 1):
        print(f"[{index}/{len(entries)}] {entry['artist']} — {entry['title']}", flush=True)
        output_path = ASSETS / f"{entry['assetName']}.imageset" / "artwork.jpg"
        previous = next((item for item in previous_results if item.get("assetName") == entry["assetName"] and item.get("title") == entry["title"] and item.get("commonsTitle") == entry.get("commonsTitle", item.get("commonsTitle")) and "error" not in item), None)
        try:
            resolved = previous or resolve(entry)
            if previous is None or not output_path.exists():
                write_asset(entry, resolved)
            results.append({**entry, **resolved})
        except Exception as error:
            print(f"ERROR: {error}", file=sys.stderr)
            results.append({**entry, "error": str(error)})
        time.sleep(1.1)
    REPORT.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    failed = [item for item in results if "error" in item]
    print(f"Resolved {len(results) - len(failed)}/{len(results)} artworks; report: {REPORT}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
