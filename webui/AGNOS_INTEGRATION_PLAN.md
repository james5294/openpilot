# AGNOS Integration Plan - Comprehensive Fork Switching

## Problem Statement

When switching between forks that require different AGNOS versions, the native openpilot AGNOS updater:
1. Streams files from remote URLs directly to partitions
2. Ignores any locally cached files
3. Can fail mid-update, leaving device in boot loop

Our current "preloading" feature downloads files but they're never used.

## Solution: Pre-Flash AGNOS Before Fork Switch

### Core Concept

Instead of letting the target fork's AGNOS updater handle the update after boot, we:
1. **Detect** AGNOS version mismatch before switch
2. **Flash** AGNOS from our cache BEFORE switching forks
3. **Verify** flash succeeded
4. **Switch** fork symlink
5. **Reboot** into new AGNOS + new fork together

### Architecture

```
User clicks "Switch to ForkX"
         │
         ▼
┌─────────────────────────────┐
│  Check AGNOS Compatibility  │
│  Current: 10.1              │
│  Target:  16                │
└─────────────────────────────┘
         │
         ▼ (Mismatch detected)
┌─────────────────────────────┐
│  Check AGNOS Cache          │
│  Is 16 cached & complete?   │
└─────────────────────────────┘
         │
    ┌────┴────┐
    │ Yes     │ No
    ▼         ▼
┌───────┐ ┌─────────────────┐
│ Flash │ │ Download first  │
│ from  │ │ then Flash      │
│ cache │ │                 │
└───────┘ └─────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Verify Flash Success       │
│  (Hash check all partitions)│
└─────────────────────────────┘
         │
    ┌────┴────┐
    │ Success │ Fail
    ▼         ▼
┌───────────┐ ┌─────────────┐
│ Switch    │ │ Abort, stay │
│ fork      │ │ on current  │
│ symlink   │ │ fork+AGNOS  │
└───────────┘ └─────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Reboot                     │
│  Device boots new AGNOS     │
│  + new fork simultaneously  │
└─────────────────────────────┘
```

## Scenarios & Edge Cases

### Scenario 1: Same AGNOS Version
- **Example**: frogpilot (10.1) → our fork (10.1)
- **Action**: Direct switch, no AGNOS flash needed
- **Risk**: None

### Scenario 2: Different AGNOS, Cache Available
- **Example**: our fork (10.1) → stock (16), AGNOS 16 cached
- **Action**: Flash from cache, switch fork, reboot
- **Risk**: Flash failure (mitigated by verification)

### Scenario 3: Different AGNOS, Cache Missing
- **Example**: our fork (10.1) → stock (16), AGNOS 16 not cached
- **Action**: Download AGNOS 16, flash, switch fork, reboot
- **Risk**: Download failure, flash failure (both mitigated)

### Scenario 4: Downgrade AGNOS
- **Example**: stock (16) → our fork (10.1)
- **Action**: Flash AGNOS 10.1 from cache, switch fork, reboot
- **Risk**: Same as upgrade

### Scenario 5: Network Failure During Download
- **Action**: Abort switch, user stays on current fork
- **Recovery**: Retry when network available

### Scenario 6: Flash Failure
- **Action**: Abort switch, don't change fork symlink
- **Recovery**: Device boots normally on current fork
- **Why safe**: We flash to ALTERNATE slot, current slot untouched

### Scenario 7: Power Loss During Flash
- **Action**: On reboot, current slot boots (no change)
- **Recovery**: Retry the switch
- **Why safe**: A/B partition system, current slot untouched

### Scenario 8: Incomplete Cache
- **Detection**: Check `.manifest.json` completion marker
- **Action**: Re-download missing files before flash

## Implementation Components

### 1. Local AGNOS Flasher (`flash_agnos_local.py`)

New module that:
- Reads compressed files from cache directory
- Decompresses on-the-fly (lzma)
- Writes directly to target partition slot
- Handles sparse images
- Verifies hash after write
- Uses same logic as openpilot's agnos.py but with local files

```python
def flash_from_cache(version: str, target_slot: int) -> bool:
    """
    Flash AGNOS from local cache to target slot.
    Returns True if successful, False otherwise.
    """
    cache_dir = AGNOS_CACHE_DIR / version
    manifest = load_manifest(cache_dir)

    for partition in manifest:
        cache_file = find_cached_file(cache_dir, partition)
        if not cache_file.exists():
            raise CacheMissError(f"Missing: {partition['name']}")

        flash_partition_from_file(cache_file, partition, target_slot)

        if not verify_partition(partition, target_slot):
            raise FlashError(f"Verification failed: {partition['name']}")

    return True
```

### 2. Enhanced Switch Flow (`server.py`)

Modify switch handler:

```python
async def handle_switch(request):
    fork_name = data['fork']

    # Get AGNOS versions
    current_agnos = get_device_agnos_version()
    target_agnos = get_fork_agnos_version(fork_name)

    if current_agnos != target_agnos:
        # Check cache
        if not is_agnos_cached(target_agnos):
            return {"success": False, "error": f"AGNOS {target_agnos} not cached. Download first."}

        # Flash AGNOS from cache
        try:
            target_slot = get_target_slot()
            flash_from_cache(target_agnos, target_slot)
        except FlashError as e:
            return {"success": False, "error": f"AGNOS flash failed: {e}"}

    # Now switch fork
    run_fork_swap("switch", fork_name)

    # Swap boot slot if AGNOS was flashed
    if current_agnos != target_agnos:
        swap_boot_slot(target_slot)

    # Reboot
    trigger_reboot()
```

### 3. UI Changes (`embedded_ui.py`)

- Show clear warning when switching to fork with different AGNOS
- Show "Download AGNOS first" button if not cached
- Show flash progress during switch
- Disable other actions during AGNOS flash

### 4. Cache Management

- Store downloaded files persistently in `/data/forkswap/agnos_cache/{version}/`
- Track completion with `.manifest.json`
- Verify file integrity with hash checks
- Support multiple versions simultaneously

## Safety Mechanisms

1. **A/B Slot Protection**: Always flash to alternate slot, current slot untouched
2. **Pre-flight Verification**: Verify cache completeness before starting flash
3. **Post-flash Verification**: Verify each partition hash after write
4. **Atomic Swap**: Only swap boot slot after all partitions verified
5. **Rollback**: If anything fails, abort and stay on current fork
6. **Lock File**: Prevent concurrent operations

## File Structure

```
/data/forkswap/
├── agnos_cache/
│   ├── 10.1/
│   │   ├── .manifest.json          # Completion marker with metadata
│   │   ├── boot-hash.img.xz        # Compressed boot image
│   │   ├── system-hash.img         # System image (possibly sparse)
│   │   └── ...                     # Other partitions
│   ├── 16/
│   │   ├── .manifest.json
│   │   └── ...
│   └── 15.1/
│       └── ...
├── current_fork.txt
├── fork_swap.sh
└── webui/
```

## API Changes

### New Endpoints

- `POST /api/flash-agnos` - Flash AGNOS from cache to target slot
- `GET /api/agnos-flash-progress` - Get flash progress

### Modified Endpoints

- `POST /api/switch` - Now handles AGNOS flashing before switch

## Implementation Order

1. Create `flash_agnos_local.py` module
2. Test local flashing in isolation
3. Integrate with switch handler
4. Update UI with warnings and progress
5. Comprehensive testing
6. Documentation

## Testing Plan

1. **Unit Tests**: Flash logic, decompression, hash verification
2. **Integration Tests**: Full switch flow with AGNOS mismatch
3. **Recovery Tests**: Power loss simulation, partial flash recovery
4. **Edge Cases**: Downgrade, same version, missing cache

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Brick device | A/B slots, never touch current slot |
| Corrupt flash | Hash verification, abort on mismatch |
| Network failure | Cache check before switch, clear error |
| Power loss | A/B slots, current slot untouched |
| Disk full | Pre-check space before download |
