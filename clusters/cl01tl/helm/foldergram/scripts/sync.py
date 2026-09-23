import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

IMMICH_URL = os.environ.get("IMMICH_URL", "http://immich-main.immich:80/api").rstrip("/")
API_KEY = os.environ.get("IMMICH_API_KEY", "")
GALLERY_PATH = os.environ.get("GALLERY_PATH", "/gallery/Favorites")
PRUNE_DELETED = os.environ.get("PRUNE_DELETED", "true").lower() in ("true", "1", "yes")

# Persistent index file: maps asset_id -> filename on disk
INDEX_PATH = os.path.join(GALLERY_PATH, ".foldergram-index.json")


def sanitize_filename(name):
    """Replace filesystem-unsafe characters, collapse multiple underscores."""
    name = re.sub(r'[^\w. -]', '_', name)
    name = re.sub(r'_+', '_', name)
    return name.strip("_. ")


def parse_immich_datetime(dt_str):
    """Parse Immich ISO-8601 datetime string to a datetime object (UTC)."""
    if not dt_str:
        return None
    # Immich returns e.g. "2023-07-15T14:32:10.000Z"
    dt_str = dt_str.rstrip("Z")
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(dt_str, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def build_filename(asset):
    """
    Build a filesystem-safe filename from Immich metadata.
    Format: YYYY-MM-DD_HH-MM-SS_originalname.ext
    Falls back to asset ID prefix if date is missing.
    Preserves the original file extension.
    """
    orig = asset.get("originalFileName", f"{asset['id']}.jpg")
    name, ext = os.path.splitext(orig)
    ext = ext.lower() if ext else ".jpg"
    safe_name = sanitize_filename(name)

    dt = parse_immich_datetime(asset.get("fileCreatedAt"))
    if dt:
        date_prefix = dt.strftime("%Y-%m-%d_%H-%M-%S")
    else:
        date_prefix = asset["id"][:8]

    return f"{date_prefix}_{safe_name}{ext}"


def ensure_unique_filename(desired, existing_names):
    """If desired filename collides, append a short ID suffix before extension."""
    if desired not in existing_names:
        return desired
    name, ext = os.path.splitext(desired)
    suffix = 1
    while True:
        candidate = f"{name}_{suffix}{ext}"
        if candidate not in existing_names:
            return candidate
        suffix += 1


def api_request(endpoint, method="GET", data=None):
    url = f"{IMMICH_URL}/{endpoint.lstrip('/')}"
    headers = {
        "x-api-key": API_KEY,
        "Accept": "application/json",
    }
    body = None
    if data is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(data).encode("utf-8")

    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_asset_detail(asset_id):
    """Fetch full asset detail (includes tags, description, exifInfo)."""
    return api_request(f"assets/{asset_id}")


def download_asset(asset_id, dest_path):
    url = f"{IMMICH_URL}/assets/{asset_id}/original"
    req = urllib.request.Request(url, headers={"x-api-key": API_KEY})
    tmp_path = f"{dest_path}.tmp"
    with urllib.request.urlopen(req, timeout=300) as resp, open(tmp_path, "wb") as f:
        while True:
            chunk = resp.read(64 * 1024)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp_path, dest_path)


def embed_metadata(asset, file_path):
    """
    Embed EXIF/XMP metadata into the downloaded file using exiftool.
    Handles both images and videos.
    """
    exif = asset.get("exifInfo") or {}
    detail = {}
    try:
        detail = fetch_asset_detail(asset["id"])
    except Exception as e:
        print(f"[sync]   Warning: could not fetch full asset detail for metadata: {e}")

    args = ["exiftool", "-overwrite_original", "-charset", "UTF8"]

    # ── Date / Time ────────────────────────────────────────────────────────────
    dt = parse_immich_datetime(asset.get("fileCreatedAt"))
    if dt:
        dt_exif = dt.strftime("%Y:%m:%d %H:%M:%S")
        args += [
            f"-DateTimeOriginal={dt_exif}",
            f"-CreateDate={dt_exif}",
            f"-ModifyDate={dt_exif}",
            # QuickTime tags for video
            f"-QuickTime:CreateDate={dt_exif}",
            f"-QuickTime:ModifyDate={dt_exif}",
        ]

    # ── GPS ───────────────────────────────────────────────────────────────────
    lat = exif.get("latitude")
    lon = exif.get("longitude")
    if lat is not None and lon is not None:
        # exiftool accepts signed decimal degrees
        args += [
            f"-GPSLatitude={abs(lat)}",
            f"-GPSLatitudeRef={'N' if lat >= 0 else 'S'}",
            f"-GPSLongitude={abs(lon)}",
            f"-GPSLongitudeRef={'E' if lon >= 0 else 'W'}",
        ]

    # ── Location text ─────────────────────────────────────────────────────────
    city = exif.get("city") or ""
    country = exif.get("country") or ""
    state = exif.get("state") or ""
    if city or country:
        location_parts = [p for p in [city, state, country] if p]
        location_str = ", ".join(location_parts)
        args += [
            f"-IPTC:City={city}",
            f"-IPTC:Country-PrimaryLocationName={country}",
            f"-XMP:City={city}",
            f"-XMP:Country={country}",
            f"-XMP:Location={location_str}",
        ]

    # ── Description / Caption ─────────────────────────────────────────────────
    description = (detail.get("exifInfo") or {}).get("description") or \
                  detail.get("description") or ""
    if description:
        args += [
            f"-ImageDescription={description}",
            f"-IPTC:Caption-Abstract={description}",
            f"-XMP:Description={description}",
            # QuickTime comment for video
            f"-QuickTime:Comment={description}",
        ]

    # ── Camera info ───────────────────────────────────────────────────────────
    make = exif.get("make") or ""
    model = exif.get("model") or ""
    if make:
        args.append(f"-Make={make}")
    if model:
        args.append(f"-Model={model}")

    # ── Artist / Copyright ────────────────────────────────────────────────────
    owner = (detail.get("owner") or {}).get("name") or ""
    if owner:
        args += [
            f"-Artist={owner}",
            f"-XMP:Creator={owner}",
            f"-IPTC:By-line={owner}",
        ]

    args.append(file_path)

    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            print(f"[sync]   Warning: exiftool returned {result.returncode}: {result.stderr.strip()}")
        else:
            print(f"[sync]   Metadata embedded OK.")
    except FileNotFoundError:
        print("[sync]   Warning: exiftool not found — metadata not embedded.")
    except subprocess.TimeoutExpired:
        print("[sync]   Warning: exiftool timed out — metadata not embedded.")


def load_index():
    """Load {asset_id: filename} index from disk."""
    if os.path.exists(INDEX_PATH):
        try:
            with open(INDEX_PATH) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def save_index(index):
    tmp = INDEX_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(index, f, indent=2)
    os.replace(tmp, INDEX_PATH)


def fetch_all_favorites():
    assets = []
    page = 1
    size = 250
    while True:
        payload = {
            "isFavorite": True,
            "page": page,
            "size": size,
        }
        res = api_request("search/metadata", method="POST", data=payload)
        items = res.get("assets", {}).get("items", [])
        if not items:
            break
        assets.extend(items)
        total = res.get("assets", {}).get("total", len(assets))
        if len(assets) >= total:
            break
        page += 1
    return assets


def sync_favorites():
    if not API_KEY:
        print("[sync] ERROR: IMMICH_API_KEY is not set. Skipping sync.")
        return

    os.makedirs(GALLERY_PATH, exist_ok=True)
    print(f"[sync] Fetching favorites from {IMMICH_URL}...")
    try:
        favorites = fetch_all_favorites()
    except Exception as e:
        print(f"[sync] Failed to query Immich API: {e}")
        return

    print(f"[sync] Found {len(favorites)} favorite assets in Immich.")

    # Load persisted index: asset_id → filename on disk
    index = load_index()

    # Build the desired filename for each remote asset, resolving collisions
    used_names = set(index.values())
    remote_assets = {}  # asset_id -> desired filename
    for a in favorites:
        aid = a["id"]
        if aid in index:
            # Already know the filename for this asset
            remote_assets[aid] = index[aid]
        else:
            desired = build_filename(a)
            fname = ensure_unique_filename(desired, used_names)
            used_names.add(fname)
            remote_assets[aid] = fname

    # Prune stale .tmp files
    for fname in os.listdir(GALLERY_PATH):
        if fname.endswith(".tmp"):
            try:
                os.remove(os.path.join(GALLERY_PATH, fname))
            except OSError:
                pass

    # Download missing assets
    downloaded = 0
    for a in favorites:
        aid = a["id"]
        fname = remote_assets[aid]
        target = os.path.join(GALLERY_PATH, fname)
        if not os.path.exists(target):
            print(f"[sync] Downloading: {fname} ...")
            try:
                download_asset(aid, target)
                embed_metadata(a, target)
                index[aid] = fname
                save_index(index)
                downloaded += 1
            except Exception as e:
                print(f"[sync] Failed to download {aid}: {e}")
                # Clean up partial file if present
                if os.path.exists(target):
                    try:
                        os.remove(target)
                    except OSError:
                        pass

    # Prune un-favourited / deleted assets
    pruned = 0
    if PRUNE_DELETED:
        for aid in list(index.keys()):
            if aid not in remote_assets:
                fname = index[aid]
                target = os.path.join(GALLERY_PATH, fname)
                print(f"[sync] Pruning: {fname} ...")
                try:
                    os.remove(target)
                    pruned += 1
                except FileNotFoundError:
                    pruned += 1  # already gone
                except Exception as e:
                    print(f"[sync] Failed to remove {target}: {e}")
                del index[aid]
        save_index(index)

    print(
        f"[sync] Sync finished: {downloaded} downloaded, {pruned} pruned, "
        f"{len(remote_assets)} total in gallery."
    )


def main():
    print("[sync] Starting Immich favorites sync...")
    sync_favorites()
    print("[sync] Sync completed successfully.")


if __name__ == "__main__":
    main()
