#!/usr/bin/env python3
"""
Local AGNOS Flasher - Flash AGNOS from cached files to device partitions.

This module enables fork switching with different AGNOS versions by:
1. Reading compressed AGNOS images from local cache
2. Decompressing on-the-fly (LZMA)
3. Writing directly to the target A/B partition slot
4. Verifying each partition after write
5. Swapping boot slot only after successful verification

Safety: Always flashes to ALTERNATE slot - current boot slot is never touched.
"""

import hashlib
import json
import lzma
import os
import struct
import subprocess
import logging
from pathlib import Path
from typing import Callable, Generator, Optional
from dataclasses import dataclass

logger = logging.getLogger(__name__)

# Sparse image format constants (Android sparse format)
SPARSE_MAGIC = 0xed26ff3a
SPARSE_CHUNK_FMT = struct.Struct('H2xI4x')

# Cache directory location
AGNOS_CACHE_DIR = Path("/data/forkswap/agnos_cache")


@dataclass
class FlashProgress:
    """Progress information for UI updates."""
    status: str  # "starting", "flashing", "verifying", "complete", "error"
    partition_name: str = ""
    partition_index: int = 0
    total_partitions: int = 0
    bytes_written: int = 0
    partition_size: int = 0
    percent: int = 0
    error: str = ""


class FlashError(Exception):
    """Raised when AGNOS flash fails."""
    pass


class CacheMissError(FlashError):
    """Raised when required cached file is missing."""
    pass


class VerificationError(FlashError):
    """Raised when partition verification fails after write."""
    pass


class LocalFileDecompressor:
    """
    Reads and decompresses a local LZMA-compressed file.
    API compatible with the native StreamingDecompressor but for local files.
    """

    def __init__(self, file_path: Path) -> None:
        self.file_path = file_path
        self.file = open(file_path, 'rb')
        self.buf = b""
        self.decompressor = lzma.LZMADecompressor(format=lzma.FORMAT_AUTO)
        self.eof = False
        self.sha256 = hashlib.sha256()
        self.compressed_sha256 = hashlib.sha256()

    def read(self, length: int) -> bytes:
        """Read and decompress up to `length` bytes."""
        while len(self.buf) < length and not self.eof:
            compressed = self.file.read(1024 * 1024)
            if not compressed:
                self.eof = True
                # Handle any remaining data in decompressor
                if not self.decompressor.eof:
                    try:
                        remaining = self.decompressor.flush()
                        self.buf += remaining
                    except lzma.LZMAError:
                        pass
                break

            self.compressed_sha256.update(compressed)
            out = self.decompressor.decompress(compressed)
            self.buf += out

        result = self.buf[:length]
        self.buf = self.buf[length:]
        self.sha256.update(result)
        return result

    def close(self):
        """Close the underlying file."""
        self.file.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class RawFileReader:
    """
    Reads an uncompressed file directly.
    For non-compressed images in the cache.
    """

    def __init__(self, file_path: Path) -> None:
        self.file_path = file_path
        self.file = open(file_path, 'rb')
        self.eof = False
        self.sha256 = hashlib.sha256()

    def read(self, length: int) -> bytes:
        """Read up to `length` bytes."""
        data = self.file.read(length)
        if not data:
            self.eof = True
        self.sha256.update(data)
        return data

    def close(self):
        self.file.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


def unsparsify(reader) -> Generator[bytes, None, None]:
    """
    Convert Android sparse format to raw data.
    Based on: https://source.android.com/devices/bootloader/images#sparse-format
    """
    # Read and verify magic
    magic_bytes = reader.read(4)
    if len(magic_bytes) < 4:
        raise FlashError("Invalid sparse image: too short")

    magic = struct.unpack("I", magic_bytes)[0]
    if magic != SPARSE_MAGIC:
        raise FlashError(f"Invalid sparse magic: {hex(magic)}")

    # Version check
    major = struct.unpack("H", reader.read(2))[0]
    minor = struct.unpack("H", reader.read(2))[0]
    if major != 1 or minor != 0:
        raise FlashError(f"Unsupported sparse version: {major}.{minor}")

    reader.read(2)  # file header size
    reader.read(2)  # chunk header size

    block_sz = struct.unpack("I", reader.read(4))[0]
    reader.read(4)  # total blocks
    num_chunks = struct.unpack("I", reader.read(4))[0]
    reader.read(4)  # crc checksum

    for _ in range(num_chunks):
        chunk_header = reader.read(12)
        if len(chunk_header) < 12:
            break

        chunk_type, out_blocks = SPARSE_CHUNK_FMT.unpack(chunk_header)

        if chunk_type == 0xcac1:  # Raw chunk
            yield reader.read(out_blocks * block_sz)
        elif chunk_type == 0xcac2:  # Fill chunk
            filler = reader.read(4) * (block_sz // 4)
            for _ in range(out_blocks):
                yield filler
        elif chunk_type == 0xcac3:  # Don't care chunk
            yield b""
        else:
            raise FlashError(f"Unknown sparse chunk type: {hex(chunk_type)}")


def passthrough(reader) -> Generator[bytes, None, None]:
    """Pass through raw data without sparse conversion."""
    while not reader.eof:
        data = reader.read(1024 * 1024)
        if data:
            yield data


def get_current_slot() -> str:
    """Get the currently booted slot (_a or _b)."""
    try:
        result = subprocess.check_output(
            ["abctl", "--boot_slot"],
            encoding='utf-8',
            stderr=subprocess.DEVNULL
        ).strip()
        return result
    except subprocess.SubprocessError as e:
        raise FlashError(f"Failed to get current boot slot: {e}")


def get_target_slot_number() -> int:
    """Get the target slot number (opposite of current boot slot)."""
    current = get_current_slot()
    return 1 if current == "_a" else 0


def slot_number_to_suffix(slot_number: int) -> str:
    """Convert slot number to partition suffix."""
    if slot_number not in (0, 1):
        raise FlashError(f"Invalid slot number: {slot_number}")
    return '_a' if slot_number == 0 else '_b'


def get_partition_path(target_slot: int, partition: dict) -> str:
    """Get the device path for a partition on the target slot."""
    name = partition['name']
    path = f"/dev/disk/by-partlabel/{name}"

    # Most partitions have A/B variants
    if partition.get('has_ab', True):
        path += slot_number_to_suffix(target_slot)

    return path


def verify_partition(target_slot: int, partition: dict) -> bool:
    """
    Verify a partition's hash after flashing.
    Returns True if verification passes.
    """
    path = get_partition_path(target_slot, partition)
    partition_size = partition['size']
    expected_hash = partition['hash_raw'].lower()

    raw_hash = hashlib.sha256()
    pos = 0
    chunk_size = 1024 * 1024

    try:
        with open(path, 'rb') as f:
            while pos < partition_size:
                n = min(chunk_size, partition_size - pos)
                data = f.read(n)
                if not data:
                    break
                raw_hash.update(data)
                pos += n

        actual_hash = raw_hash.hexdigest().lower()
        matches = actual_hash == expected_hash

        if not matches:
            logger.error(f"Hash mismatch for {partition['name']}: expected {expected_hash}, got {actual_hash}")

        return matches

    except IOError as e:
        logger.error(f"Failed to verify {partition['name']}: {e}")
        return False


def clear_partition_hash(target_slot: int, partition: dict) -> None:
    """
    Clear the hash marker at the end of a partition.
    This marks the partition as incomplete until successfully flashed.
    """
    if partition.get('full_check', False):
        return

    path = get_partition_path(target_slot, partition)
    try:
        with open(path, 'r+b') as f:
            f.seek(partition['size'])
            f.write(b"\x00" * 64)
            os.sync()
    except IOError as e:
        logger.warning(f"Could not clear hash marker for {partition['name']}: {e}")


def write_partition_hash(target_slot: int, partition: dict) -> None:
    """
    Write the hash marker at the end of a partition.
    This marks a successful flash for quick verification.
    """
    if partition.get('full_check', False):
        return

    path = get_partition_path(target_slot, partition)
    try:
        with open(path, 'r+b') as f:
            f.seek(partition['size'])
            f.write(partition['hash_raw'].lower().encode())
            os.sync()
    except IOError as e:
        logger.warning(f"Could not write hash marker for {partition['name']}: {e}")


def find_cached_file(cache_dir: Path, partition: dict) -> Optional[Path]:
    """
    Find the cached file for a partition.
    Files may be named by URL filename or partition name.
    """
    def add_url_candidates(url: str, bucket: list[str]) -> None:
        if not url:
            return
        filename = url.split('/')[-1]
        if filename:
            bucket.append(filename)
            if filename.endswith('.xz'):
                bucket.append(filename[:-3])

    candidates: list[str] = []
    add_url_candidates(partition.get('url', ''), candidates)
    alt = partition.get('alt', {}) or {}
    add_url_candidates(alt.get('url', ''), candidates)

    for filename in candidates:
        cache_file = cache_dir / filename
        if cache_file.exists():
            return cache_file

    # Try partition name with extensions
    name = partition['name']
    for ext in ['.img.xz', '.img', '.xz', '']:
        cache_file = cache_dir / f"{name}{ext}"
        if cache_file.exists():
            return cache_file

    return None


def flash_partition_from_cache(
    cache_file: Path,
    partition: dict,
    target_slot: int,
    progress_callback: Optional[Callable[[FlashProgress], None]] = None
) -> None:
    """
    Flash a single partition from a cached file.

    Args:
        cache_file: Path to the cached (possibly compressed) image
        partition: Partition metadata from manifest
        target_slot: Target slot number (0 or 1)
        progress_callback: Optional callback for progress updates
    """
    path = get_partition_path(target_slot, partition)
    partition_name = partition['name']
    partition_size = partition['size']
    is_sparse = partition.get('sparse', False)

    logger.info(f"Flashing {partition_name} from {cache_file} to {path}")

    # Determine if file is compressed
    is_compressed = cache_file.suffix == '.xz' or str(cache_file).endswith('.img.xz')

    # Clear hash marker before flashing
    clear_partition_hash(target_slot, partition)

    # Open appropriate reader
    if is_compressed:
        reader = LocalFileDecompressor(cache_file)
    else:
        reader = RawFileReader(cache_file)

    try:
        # Open partition for writing
        with open(path, 'wb') as out:
            raw_hash = hashlib.sha256()
            bytes_written = 0
            last_percent = -1

            # Choose sparse or raw processing
            processor = unsparsify if is_sparse else passthrough

            for chunk in processor(reader):
                if chunk:  # Don't care chunks yield empty bytes
                    raw_hash.update(chunk)
                    out.write(chunk)
                    bytes_written += len(chunk)

                # Progress update
                percent = int(bytes_written * 100 / partition_size) if partition_size > 0 else 0
                if percent != last_percent and progress_callback:
                    progress_callback(FlashProgress(
                        status="flashing",
                        partition_name=partition_name,
                        bytes_written=bytes_written,
                        partition_size=partition_size,
                        percent=min(percent, 100)
                    ))
                    last_percent = percent

            os.sync()

        # Verify raw hash
        actual_hash = raw_hash.hexdigest().lower()
        expected_hash = partition['hash_raw'].lower()

        if actual_hash != expected_hash:
            raise VerificationError(
                f"Raw hash mismatch for {partition_name}: "
                f"expected {expected_hash}, got {actual_hash}"
            )

        # Write hash marker for quick future verification
        write_partition_hash(target_slot, partition)

        logger.info(f"Successfully flashed {partition_name}")

    finally:
        reader.close()


def set_slot_unbootable(slot: int) -> None:
    """Mark a slot as unbootable."""
    try:
        subprocess.run(
            ["abctl", f"--set_unbootable", str(slot)],
            check=True,
            capture_output=True
        )
        logger.info(f"Marked slot {slot} as unbootable")
    except subprocess.SubprocessError as e:
        logger.warning(f"Could not mark slot {slot} unbootable: {e}")


def set_slot_active(slot: int) -> bool:
    """
    Set a slot as the active boot slot.
    Returns True if successful.
    """
    try:
        result = subprocess.run(
            ["abctl", f"--set_active", str(slot)],
            capture_output=True,
            text=True,
            check=False
        )

        output = result.stdout + result.stderr

        # Check for success indicators
        if "lun as boot lun" in output.lower():
            logger.info(f"Successfully set slot {slot} as active")
            return True

        # Retry logic for transient failures
        if "No such file or directory" in output:
            logger.warning(f"Slot swap retry needed: {output}")
            return False

        logger.info(f"Slot {slot} set active: {output}")
        return True

    except subprocess.SubprocessError as e:
        logger.error(f"Failed to set slot {slot} active: {e}")
        return False


def swap_boot_slot(target_slot: int, max_retries: int = 5) -> bool:
    """
    Swap to the target boot slot with retries.
    Returns True if successful.
    """
    for attempt in range(max_retries):
        if set_slot_active(target_slot):
            return True
        logger.info(f"Swap attempt {attempt + 1}/{max_retries} failed, retrying...")
        import time
        time.sleep(1)

    return False


def flash_agnos_from_cache(
    version: str,
    progress_callback: Optional[Callable[[FlashProgress], None]] = None
) -> dict:
    """
    Flash AGNOS from local cache to the target slot.

    This is the main entry point for local AGNOS flashing.

    Args:
        version: AGNOS version to flash (e.g., "16", "10.1")
        progress_callback: Optional callback for progress updates

    Returns:
        dict with success status and details
    """
    cache_dir = AGNOS_CACHE_DIR / version

    # Validate cache exists
    if not cache_dir.exists():
        return {
            "success": False,
            "error": f"AGNOS {version} not cached. Download first."
        }

    # Load manifest
    manifest_file = cache_dir / ".manifest.json"
    if not manifest_file.exists():
        return {
            "success": False,
            "error": f"AGNOS {version} cache incomplete (no manifest)"
        }

    try:
        with open(manifest_file) as f:
            manifest_data = json.load(f)

        # The manifest contains the original partition list
        partitions = manifest_data.get('partitions', [])
        if not partitions:
            return {
                "success": False,
                "error": "Empty partition manifest"
            }

    except json.JSONDecodeError as e:
        return {
            "success": False,
            "error": f"Invalid manifest: {e}"
        }

    # Get target slot
    try:
        target_slot = get_target_slot_number()
        current_slot = get_current_slot()
        logger.info(f"Current slot: {current_slot}, target slot: {target_slot}")
    except FlashError as e:
        return {"success": False, "error": str(e)}

    # Report starting
    if progress_callback:
        progress_callback(FlashProgress(
            status="starting",
            total_partitions=len(partitions)
        ))

    # Mark target slot unbootable during flash
    set_slot_unbootable(target_slot)

    # Flash each partition
    flashed = []
    try:
        for i, partition in enumerate(partitions):
            name = partition['name']

            # Find cached file
            cache_file = find_cached_file(cache_dir, partition)
            if not cache_file:
                raise CacheMissError(f"Missing cached file for partition: {name}")

            if progress_callback:
                progress_callback(FlashProgress(
                    status="flashing",
                    partition_name=name,
                    partition_index=i,
                    total_partitions=len(partitions),
                    partition_size=partition.get('size', 0)
                ))

            # Flash with retries
            for attempt in range(3):
                try:
                    flash_partition_from_cache(
                        cache_file, partition, target_slot, progress_callback
                    )
                    break
                except (IOError, FlashError) as e:
                    if attempt == 2:
                        raise
                    logger.warning(f"Flash attempt {attempt + 1} failed for {name}: {e}")
                    import time
                    time.sleep(2)

            # Verify after flash
            if progress_callback:
                progress_callback(FlashProgress(
                    status="verifying",
                    partition_name=name,
                    partition_index=i,
                    total_partitions=len(partitions)
                ))

            if not verify_partition(target_slot, partition):
                raise VerificationError(f"Verification failed for {name}")

            flashed.append(name)
            logger.info(f"Partition {i + 1}/{len(partitions)} complete: {name}")

        # All partitions flashed and verified
        if progress_callback:
            progress_callback(FlashProgress(
                status="complete",
                total_partitions=len(partitions),
                partition_index=len(partitions)
            ))

        return {
            "success": True,
            "target_slot": target_slot,
            "partitions_flashed": flashed,
            "message": f"AGNOS {version} ready on slot {target_slot}"
        }

    except (FlashError, IOError) as e:
        logger.error(f"AGNOS flash failed: {e}")

        if progress_callback:
            progress_callback(FlashProgress(
                status="error",
                error=str(e)
            ))

        return {
            "success": False,
            "error": str(e),
            "partitions_flashed": flashed
        }


def verify_agnos_from_cache(version: str) -> dict:
    """
    Verify that cached AGNOS can be flashed successfully.

    Checks:
    1. Cache directory exists
    2. Manifest is valid
    3. All required files are present
    4. Files are readable

    Returns:
        dict with validation status
    """
    cache_dir = AGNOS_CACHE_DIR / version

    if not cache_dir.exists():
        return {"valid": False, "error": f"Cache directory not found: {cache_dir}"}

    manifest_file = cache_dir / ".manifest.json"
    if not manifest_file.exists():
        return {"valid": False, "error": "Manifest file not found"}

    try:
        with open(manifest_file) as f:
            manifest_data = json.load(f)
        partitions = manifest_data.get('partitions', [])
    except json.JSONDecodeError as e:
        return {"valid": False, "error": f"Invalid manifest JSON: {e}"}

    if not partitions:
        return {"valid": False, "error": "No partitions in manifest"}

    # Check each partition file
    missing = []
    found = []
    for partition in partitions:
        cache_file = find_cached_file(cache_dir, partition)
        if cache_file:
            found.append(partition['name'])
        else:
            missing.append(partition['name'])

    if missing:
        return {
            "valid": False,
            "error": f"Missing files for: {', '.join(missing)}",
            "found": found,
            "missing": missing
        }

    return {
        "valid": True,
        "partitions": found,
        "total_size": sum(p.get('size', 0) for p in partitions)
    }


# Entry point for testing
if __name__ == "__main__":
    import argparse
    import sys

    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )

    parser = argparse.ArgumentParser(description="Flash AGNOS from local cache")
    parser.add_argument("version", help="AGNOS version to flash (e.g., 16, 10.1)")
    parser.add_argument("--verify-only", action="store_true", help="Only verify cache, don't flash")
    parser.add_argument("--swap", action="store_true", help="Swap boot slot after flash")
    args = parser.parse_args()

    def print_progress(p: FlashProgress):
        if p.status == "flashing":
            print(f"  Flashing {p.partition_name}: {p.percent}%", end='\r')
        elif p.status == "verifying":
            print(f"  Verifying {p.partition_name}...")
        elif p.status == "complete":
            print(f"\nComplete!")
        elif p.status == "error":
            print(f"\nError: {p.error}")

    if args.verify_only:
        result = verify_agnos_from_cache(args.version)
        print(json.dumps(result, indent=2))
        sys.exit(0 if result.get('valid') else 1)

    print(f"Flashing AGNOS {args.version} from cache...")
    result = flash_agnos_from_cache(args.version, print_progress)

    if result['success']:
        print(f"\nSuccess: {result['message']}")

        if args.swap:
            print(f"Swapping to slot {result['target_slot']}...")
            if swap_boot_slot(result['target_slot']):
                print("Boot slot swapped. Reboot to activate new AGNOS.")
            else:
                print("Warning: Boot slot swap failed!")
                sys.exit(1)
    else:
        print(f"\nFailed: {result['error']}")
        sys.exit(1)
