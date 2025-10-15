# ForkSwap Knowledge Base
**Version**: 3.0.0-dev
**Last Updated**: 2025-10-15
**Status**: Architecture Redesign Phase

---

## Table of Contents
1. [Quick Reference](#quick-reference)
2. [Architecture Evolution](#architecture-evolution)
3. [Critical Findings](#critical-findings)
4. [Current Architecture](#current-architecture)
5. [Update Safety Analysis](#update-safety-analysis)
6. [Architectural Decisions](#architectural-decisions)
7. [Known Issues](#known-issues)
8. [Next Steps](#next-steps)

---

## Quick Reference

### Product Goal
**A truly modular, web-based fork management utility that:**
- Does not hinder any fork
- Is easily dropped in
- Survives all OS and openpilot updates
- Works with ANY openpilot fork (stock, FrogPilot, dragonpilot, etc.)

### Current Status
- ✅ Web UI v2.2.0 operational
- ✅ Flask auto-install working
- ✅ Overlay deployment system implemented
- ⚠️ **CRITICAL ISSUE**: Update system breaks ForkSwap (v2.x architecture)
- 🔄 **IN PROGRESS**: Redesigning to update-safe architecture (v3.0)

### Key Locations (v3.0 Design)
```
/data/forkswap/          ← Persistent ForkSwap core (update-safe)
/data/forks/             ← Fork storage
/data/openpilot          ← Symlink to active fork
```

---

## Architecture Evolution

### v1.0: CLI-Only (2023)
- Bash script (`tools/scripts/forkswap.sh`)
- Fork switching via symlinks
- No UI, SSH access required

### v2.0-2.2: Web UI + Overlay Deployment (2024-2025)
- Added Flask-based Web UI (port 8080)
- Implemented overlay deployment system
- Auto-start via process_config.py
- **FLAW DISCOVERED**: Files get overwritten during openpilot updates

### v3.0: Update-Safe Architecture (Current Design)
- Move core files to `/data/forkswap/` (outside any fork)
- Minimal launcher shims in each fork
- Direct execution from persistent location
- **100% immune to updates**

---

## Critical Findings

### Finding #1: AGNOS Update Triggers Stock Openpilot Incompatibility
**Date**: 2025-10-15
**Severity**: HIGH
**Impact**: Device can become unusable when switching to stock comma.ai openpilot

**Details**:
- Stock comma.ai openpilot automatically updates AGNOS (OS)
- Updated AGNOS may be incompatible with custom forks (older code)
- Updated AGNOS may have strict firmware requirements
- Users can get "trapped" - can't run stock (firmware error) and can't switch back (update in progress)

**Resolution**:
- Warn users before switching to stock openpilot
- Recommend staying with custom forks
- Consider AGNOS version detection before fork switch

---

### Finding #2: Openpilot Updates Overwrite ForkSwap Files
**Date**: 2025-10-15
**Severity**: CRITICAL
**Impact**: ForkSwap disappears after openpilot updates

**Root Cause**:
```python
# Openpilot updater replaces ALL files in /data/openpilot
# including selfdrive/forkswap/*
/data/openpilot/selfdrive/forkswap/webui.py  ← OVERWRITTEN
/data/openpilot/system/manager/process_config.py  ← OVERWRITTEN
```

**Resolution Path**:
Move ForkSwap core to `/data/forkswap/` (outside update scope)

---

### Finding #3: /data Partition is Update-Safe
**Date**: 2025-10-15
**Severity**: INFO (Enables solution)
**Impact**: Enables persistent ForkSwap installation

**Evidence**:
```bash
# Updater ONLY touches:
/data/openpilot/*         ← Updated
/data/safe_staging/*      ← Staging area
/tmp/*                    ← Temporary files

# Updater NEVER touches:
/data/params/             ← Preserved
/data/media/              ← Preserved
/data/ssh/                ← Preserved
/data/forkswap/           ← SAFE for our files
```

**Confirmation**: Analyzed `system/updated/updated.py` - no code paths touch custom directories.

---

## Update Safety Analysis

### What Gets Updated?

#### AGNOS (OS) Updates
- System partition (/)
- Kernel
- **DOES NOT** touch /data partition contents

#### Openpilot Updates
- Everything in `/data/openpilot/*` (git pull + overlay system)
- `/data/safe_staging/` (staging directory)
- **DOES NOT** touch other /data subdirectories

### Safe Zones in /data Partition
✅ **Completely Safe** (never touched by updates):
- `/data/params/` - Params storage
- `/data/media/` - User media
- `/data/ssh/` - SSH keys
- `/data/log/` - Logs
- `/data/forkswap/` - **OUR NEW HOME**
- `/data/forks/` - Fork storage

⚠️ **Update Targets** (overwritten by updates):
- `/data/openpilot/` - Active openpilot fork
- `/data/safe_staging/` - Update staging

### Update Flow Diagram
```
┌─────────────────────────────────────────────────┐
│  Update Initiated (stock openpilot)            │
└────────────────┬────────────────────────────────┘
                 │
                 ├─► Check for AGNOS update
                 │   └─► If available: Update OS (reboot)
                 │
                 ├─► Fetch git updates
                 │   └─► /data/safe_staging/upper/
                 │
                 ├─► Apply overlay
                 │   └─► Merge changes
                 │
                 └─► Finalize update
                     └─► Replace /data/openpilot/*
                         ├─► ALL FILES REPLACED
                         └─► Custom files LOST

/data/forkswap/ ◄─────── NEVER TOUCHED
```

---

## Current Architecture (v2.2)

### File Structure
```
/data/openpilot → /data/forks/james5294/openpilot

/data/forks/
├── james5294/openpilot/
│   ├── selfdrive/forkswap/
│   │   ├── webui.py              (42,936 bytes) ← LOST ON UPDATE
│   │   ├── service.py            (33,957 bytes)
│   │   ├── types.py              (5,250 bytes)
│   │   └── __init__.py           (357 bytes)
│   ├── system/manager/process_config.py  ← LOST ON UPDATE
│   └── tools/scripts/
│       ├── forkswap.sh           ← LOST ON UPDATE
│       └── deploy_overlay_to_fork.sh
└── commaai-master/openpilot/
    └── [same structure after overlay deployment]
```

### Auto-Start Mechanism
```python
# /data/openpilot/system/manager/process_config.py
procs += [
  PythonProcess("forkswapd", "selfdrive.forkswap.service", enabled=not Params().get_bool("ForkSwapServiceDisabled")),
  PythonProcess("forkswap_webui", "selfdrive.forkswap.webui", enabled=not Params().get_bool("ForkSwapWebUIDisabled")),
]
```

### Problems
1. **Files inside fork directory** → Overwritten by updates
2. **Each fork needs deployment** → Complexity
3. **Version drift** → Different forks have different ForkSwap versions
4. **Update breaks everything** → Users lose access

---

## Proposed Architecture (v3.0)

### Design Principles
1. **Persistence First**: Core files outside update scope
2. **Minimal Fork Footprint**: Only tiny launcher shim in forks
3. **Single Source of Truth**: One ForkSwap installation
4. **Zero Deployment**: Works immediately after fork switch

### New File Structure
```
/data/forkswap/                        ← PERSISTENT (never updated)
├── core/
│   ├── webui.py                       ← Main Web UI
│   ├── service.py                     ← ForkSwap daemon
│   ├── fork_manager.py                ← Fork operations
│   ├── __init__.py
│   └── version.py                     ← v3.0.0
├── tools/
│   ├── deploy_shim.sh                 ← Deploy launcher to forks
│   └── forkswap_cli.py                ← CLI interface
├── overlay/
│   ├── process_config_patch.py        ← Patch for process_config.py
│   └── launcher_shim.py               ← Minimal shim for forks
└── version.txt                        ← "3.0.0"

/data/forks/
├── james5294/openpilot/
│   └── selfdrive/forkswap/            ← ONLY contains 3-line shim
│       └── __init__.py                ← import sys; sys.path.insert(0, '/data/forkswap/core')
└── commaai-master/openpilot/
    └── selfdrive/forkswap/            ← ONLY contains 3-line shim
        └── __init__.py                ← Same shim (survives updates)
```

### Launcher Shim (per fork)
Each fork gets a tiny `selfdrive/forkswap/__init__.py`:
```python
"""ForkSwap Launcher Shim - Redirects to persistent core"""
import sys
sys.path.insert(0, '/data/forkswap/core')
# All functionality lives in /data/forkswap/core/
```

**Size**: ~150 bytes (vs 82KB for full deployment)

### Process Config Integration
```python
# Option A: Direct execution (no import needed)
PythonProcess("forkswap_webui", None,
              cmdline=["python3", "/data/forkswap/core/webui.py"])

# Option B: Patch process_config.py to add custom process paths
# Via /data/forkswap/overlay/process_config_patch.py
```

### Update Flow (v3.0)
```
┌─────────────────────────────────────────────────┐
│  Update Initiated (any fork)                   │
└────────────────┬────────────────────────────────┘
                 │
                 ├─► Replace /data/openpilot/*
                 │   ├─► selfdrive/forkswap/__init__.py
                 │   │   └─► Tiny shim SURVIVES (or gets recreated)
                 │   └─► All other files replaced
                 │
                 └─► /data/forkswap/ ◄─── COMPLETELY UNTOUCHED
                     └─► ForkSwap continues working
```

---

## Architectural Decisions

### Decision #1: Persistent Core Location
**Chosen**: `/data/forkswap/`
**Alternatives Considered**:
- `/data/params/forkswap/` - No, params is for key-value storage
- `/data/.forkswap/` - No, hidden directories can be confusing
- `/home/comma/forkswap/` - No, home directory may not persist

**Rationale**:
- `/data/` partition is user data area (proven persistent)
- Clear naming convention (not hidden)
- Parallel to `/data/params/`, `/data/media/`, etc.
- Never touched by updater (confirmed via code analysis)

---

### Decision #2: Shim vs Direct Execution
**Chosen**: Launcher Shim in forks
**Alternative**: Direct execution only

**Rationale**:
- Maintains Python module structure (`selfdrive.forkswap`)
- Compatible with existing process_config.py patterns
- Allows imports from other parts of openpilot
- Tiny footprint (150 bytes vs 82KB)
- Easy to verify/recreate after updates

---

### Decision #3: Overlay Deployment vs Persistent Install
**Chosen**: Persistent Install (v3.0)
**Previous**: Overlay Deployment (v2.0-2.2)

**Comparison**:
| Aspect | v2.x Overlay | v3.0 Persistent |
|--------|--------------|-----------------|
| Survives updates | ❌ No | ✅ Yes |
| Deployment needed | ✅ Every fork | ❌ Once only |
| Version sync | ❌ Manual | ✅ Automatic |
| Complexity | High | Low |
| Maintenance | Per-fork | Single location |

---

## Known Issues

### Issue #1: Stock Openpilot AGNOS Update Trap
**Status**: KNOWN, DOCUMENTED
**Workaround**: Warn users, recommend custom forks
**Fix**: Add AGNOS version detection before fork switch

### Issue #2: v2.x Files Get Overwritten
**Status**: RESOLVED in v3.0 design
**Fix**: Move to /data/forkswap/

### Issue #3: process_config.py Modification
**Status**: NEEDS SOLUTION
**Options**:
1. Patch process_config.py during shim deployment
2. Use direct Python execution (no import)
3. Create custom process loader

---

## Next Steps

### Phase 1: Architecture Implementation ⏳
1. ✅ Analyze update safety (`/data/forkswap/` confirmed safe)
2. ⏳ Create `/data/forkswap/` structure
3. ⏳ Move core files to persistent location
4. ⏳ Create launcher shim template
5. ⏳ Implement shim deployment script

### Phase 2: Testing
1. ⏳ Test fork switching with persistent install
2. ⏳ Trigger openpilot update, verify ForkSwap survives
3. ⏳ Test Web UI accessibility after update
4. ⏳ Verify auto-start mechanism

### Phase 3: Migration
1. ⏳ Create migration script (v2.x → v3.0)
2. ⏳ Update documentation
3. ⏳ Deploy to test device
4. ⏳ Production release

### Phase 4: Enhancements
1. AGNOS version detection
2. Fork compatibility warnings
3. Update notification system
4. Backup/restore functionality

---

## Reference Materials

### Related Documents (To Be Consolidated)
- `FORKSWAP_COMPREHENSIVE_TEST_REPORT.md` (v2.2 testing)
- `FORKSWAP_TODO.md` (outdated, migrate to this doc)
- `overlay/forkswap_manifest.json` (v2.2 deployment manifest)

### External Resources
- [AGNOS Builder](https://github.com/commaai/agnos-builder)
- [Openpilot Updater](https://github.com/commaai/openpilot/blob/master/system/updated/updated.py)
- [Comma Discord #dev-agnos](https://discord.gg/comma)

---

## Changelog

### 2025-10-15: Critical Findings & v3.0 Design
- Discovered AGNOS update trap (stock openpilot breaks custom forks)
- Discovered openpilot update overwrites ForkSwap files
- Confirmed `/data/forkswap/` is update-safe via code analysis
- Designed v3.0 persistent architecture
- Created knowledge base structure

### 2025-10-14: v2.2.0 Release
- Implemented overlay deployment system
- Added Flask auto-install
- Created deploy_overlay_to_fork.sh
- Modified api_switch() and api_clone() for auto-deployment

### 2025-10-13: v2.1.0 Release
- Web UI operational
- Complete CLI parity
- Auto-start on boot
- Removed obsolete C++ UI panel

---

**Document Maintenance**: This knowledge base should be updated whenever:
- New issues are discovered
- Architectural decisions are made
- Implementation phases complete
- Testing reveals new information
