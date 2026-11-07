#!/usr/bin/env python3
import io
import os
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

NGRAMS_DIR = Path("/ngrams")
REQUIRED_DIRS = [
    NGRAMS_DIR / "en" / "1grams",
    NGRAMS_DIR / "en" / "2grams",
    NGRAMS_DIR / "en" / "3grams",
]
MARKER_FILE = NGRAMS_DIR / "en" / ".initialized"
URL = "https://languagetool.org/download/ngram-data/ngrams-en-20150817.zip"
HEADERS = {"User-Agent": "Wget"}


class HTTPRangeFile(io.RawIOBase):
    def __init__(self, url: str):
        self.url = url
        req = urllib.request.Request(url, method="HEAD", headers=HEADERS)
        with urllib.request.urlopen(req, timeout=60) as resp:
            self.size = int(resp.headers["Content-Length"])
        self.pos = 0

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def seek(self, offset: int, whence: int = os.SEEK_SET) -> int:
        if whence == os.SEEK_SET:
            self.pos = offset
        elif whence == os.SEEK_CUR:
            self.pos += offset
        elif whence == os.SEEK_END:
            self.pos = self.size + offset
        return self.pos

    def tell(self) -> int:
        return self.pos

    def readinto(self, b) -> int:
        if self.pos >= self.size:
            return 0
        end = min(self.pos + len(b) - 1, self.size - 1)
        headers = {**HEADERS, "Range": f"bytes={self.pos}-{end}"}
        req = urllib.request.Request(self.url, headers=headers)
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = resp.read()
        n = len(data)
        b[:n] = data
        self.pos += n
        return n


def main() -> int:
    print(">> Checking N-grams status...", flush=True)
    # Clean up any leftover zip archive from previous attempts
    legacy_zip = NGRAMS_DIR / "ngrams-en-20150817.zip"
    if legacy_zip.exists():
        print(f">> Removing leftover archive {legacy_zip}...", flush=True)
        legacy_zip.unlink()

    if MARKER_FILE.exists() and all(d.is_dir() for d in REQUIRED_DIRS):
        print(
            ">> N-grams are already unpacked and initialized. Skipping download.",
            flush=True,
        )
        return 0

    print(f">> Provisioning English N-grams from {URL}...", flush=True)
    NGRAMS_DIR.mkdir(parents=True, exist_ok=True)

    remote_file = io.BufferedReader(HTTPRangeFile(URL), buffer_size=16 * 1024 * 1024)
    with zipfile.ZipFile(remote_file) as zf:
        infos = zf.infolist()
        total_files = len(infos)
        for idx, info in enumerate(infos, 1):
            target = NGRAMS_DIR / info.filename
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue

            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists() and target.stat().st_size == info.file_size:
                print(
                    f">> [{idx}/{total_files}] Skipping {info.filename} (already extracted)",
                    flush=True,
                )
                continue

            size_mb = info.file_size / (1024 * 1024)
            print(
                f">> [{idx}/{total_files}] Extracting {info.filename} ({size_mb:.1f} MiB)...",
                flush=True,
            )
            tmp_target = target.with_name(f".{target.name}.tmp")
            with zf.open(info) as src, open(tmp_target, "wb") as dst:
                shutil.copyfileobj(src, dst, length=4 * 1024 * 1024)
            tmp_target.replace(target)

    MARKER_FILE.touch()
    print(">> Initialization complete!", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
