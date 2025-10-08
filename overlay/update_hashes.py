#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path


def compute_hash(path: Path) -> str:
  h = hashlib.sha256()
  with path.open('rb') as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b''):
      h.update(chunk)
  return h.hexdigest()


def main() -> None:
  repo_root = Path(__file__).resolve().parents[1]
  overlay_dir = repo_root / 'overlay'
  manifest_path = overlay_dir / 'forkswap_manifest.json'
  checksum_path = overlay_dir / 'forkswap_manifest.json.sha256'

  manifest = json.loads(manifest_path.read_text())
  results = {}
  for item in manifest.get('files', []):
    source = Path(item['source'])
    src_path = repo_root / source
    if item.get('type') == 'directory':
      results[str(source)] = None
      continue
    if not src_path.is_file():
      raise FileNotFoundError(f"Manifest entry '{source}' missing")
    results[str(source)] = compute_hash(src_path)

  checksum_path.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n")
  print("Updated", checksum_path)


if __name__ == '__main__':
  main()
