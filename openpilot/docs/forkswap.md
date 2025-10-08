# Forkswap Modernization Notes

## Overview

`tools/scripts/forkswap.sh` now manages OpenPilot forks with explicit symlink
validation, metadata tracking, and portable shell primitives. The script
migrates an existing `/data/openpilot` tree into a managed fork on first run,
backs up params before every swap, restores the target fork's params after
switching, and keeps the active checkout's `tools/scripts/forkswap.sh` in sync
with the device copy. Interactive prompts were updated to avoid accidental
reboots and to surface errors more clearly.

Key behaviour changes:
- Environment overrides (`OPENPILOT_DIR`, `FORKS_DIR`, etc.) allow sandboxed
  testing without touching `/data`.
- `FORKSWAP_ALLOW_NONROOT=1` gates the root check so automated tests can run as
  an unprivileged user.
- `FORKSWAP_SKIP_MAIN=1` lets harnesses source the script without launching the
  interactive loop.
- `FORKSWAP_ALLOW_LOCAL_URLS=1` accepts `file://` URLs for local testing.
- `FORKSWAP_DISABLE_UPDATE_CHECK=1` skips the GitHub update probe when network access is unavailable.
- `FORKSWAP_LOCK_PATH` overrides the per-run lock directory (defaults to
  `$FORKS_DIR/.forkswap.lock`) so multiple environments can coexist.
- `FORKSWAP_HOLD_LOCK=1` (with optional `FORKSWAP_HOLD_LOCK_DURATION`) keeps the
  lock for a bounded interval—useful for concurrency testing.
- `FORKSWAP_REBOOT_CMD` customises the command executed when a user confirms the
  reboot prompt (default: `reboot`).
- `FORKSWAP_SIMULATE_MISSING_CMD` (comma-separated list) forces the script to
  treat selected binaries as missing—useful for automated negative tests.
- `ForkSwapAction`, `ForkSwapPayload`, and `ForkSwapStatus` are Params keys used
  by the forkswap service to coordinate requests and publish structured status.
- `ForkSwapFailureStreak` counts consecutive failures; `ForkSwapLastResult`
  stores a compact JSON record of the latest outcome for telemetry.
- `ForkSwapServiceHeartbeat` and `ForkSwapServiceErrorCount` help monitor the
  background daemon’s health and error rates.
- Every time a fork is cloned or activated, the script now copies the overlay
  components (service, UI panel, manager hooks) into the target so the
  forkswap experience remains consistent across forks.
- Overlay contents are defined in `overlay/forkswap_manifest.json` with
  SHA-256 checksums in `overlay/forkswap_manifest.json.sha256`. The swap
  script validates these before copying, so keep the manifest in sync whenever
  you edit overlay files (run the helper script that regenerates hashes).

## Test Harness

A self-contained regression harness is available at
`tools/scripts/forkswap_harness.sh`. It creates temporary directories, seeds a
local bare Git repository, and drives the interactive workflow (clone, switch,
delete) via scripted input. The harness verifies that:

1. An existing checkout is migrated into a managed fork and symlinked.
2. Params from the active fork are backed up before switching.
3. Switching restores the destination fork's params and updates the symlink.
4. Deleting a fork removes its managed directory.

Run it from the repository root:

```bash
./tools/scripts/forkswap_harness.sh
```

The harness leaves no residue outside of a temporary directory and prints the
captured `forkswap.sh` output if a step fails.

- Set `FORKSWAP_HARNESS_USE_REAL_REPO=1` to mirror the current repository into a
  bare remote and exercise the script against a full history.
- Provide `FORKSWAP_HARNESS_REMOTE_URL=<git-url>` to test against an external
  network-accessible remote (use cautiously, as the clone will fetch all data).
- `FORKSWAP_HARNESS_KEEP_TMP=1` preserves the temporary workspace so you can
  inspect logs and cloned forks after the run.

Additional built-in checks cover lock contention handling, detection of missing
required executables, and log rotation. Harness output records the temporary
log path (`fork_swap.log`) plus the managed forks directory so you can inspect
state after each run.

### Service Harness

For the Python service wrapper use
`tools/scripts/forkswap_service_harness.py`. It exercises the service against a
staged repository, verifying clone/rename/switch/delete flows using the new
Params contract.

```bash
./tools/scripts/forkswap_service_harness.py
FORKSWAP_HARNESS_KEEP_TMP=1 ./tools/scripts/forkswap_service_harness.py  # keep workspace for inspection
```

The harness relies on `ForkSwapAction`/`ForkSwapPayload`/`ForkSwapStatus`
updates to drive the service, making it easy to bolt into automated testing or
CI.

## Forkswap Service

The daemon lives in `selfdrive/forkswap/service.py` and watches the params keys
above. Clients should:

1. Write a JSON payload describing the request to `ForkSwapPayload`. Required
   fields are `action`, `fork`, `url` (for clone), and a unique `request_id`.
2. Set `ForkSwapAction` to the same `request_id` to trigger the service.
3. Poll `ForkSwapStatus` for progress (`state` transitions: `idle`, `running`,
   `success`, `error`). The payload captures `started_at`, `duration`, detailed
   metadata, and a short log tail for debugging.

Supported actions today are `clone`, `switch`, `delete`, `update`, `list`, and
`status`. Options allow you to control behaviour (e.g., `reboot`, conflict
policy for clone, path overrides for testing).

Run the service via:

```bash
python -m openpilot.selfdrive.forkswap.service
```

On-device the manager now launches `forkswapd` automatically (it can be disabled
by setting the persistent param `ForkSwapServiceDisabled` to `"1"` if
troubleshooting is required). Monitor `ForkSwapFailureStreak` and
`ForkSwapLastResult` (both cleared on manager start) to raise alerts if repeated
failures occur.

In production the manager should supervise this module so the UI can submit
requests entirely through Params, without shell access.

### CLI Client

For quick manual testing use `tools/scripts/forkswap_request.py`, which wraps
the Params contract:

```bash
# queue a clone request and follow progress
./tools/scripts/forkswap_request.py clone --fork sunnypilot --url https://github.com/sunnypilot/sunnypilot.git --branch main

# list available forks without waiting
./tools/scripts/forkswap_request.py list --no-wait
```

The client prints status transitions (including duration, log tail, and extra
detail payloads) so you can confirm the service handled the request.

### UI Helpers

`selfdrive/ui/forkswap_client.py` exposes `read_status`, `queue_request`, and
`clear_pending` helpers so the Qt UI (or other clients) can interact with the
service without reimplementing JSON plumbing.

## UI Integration Plan

To expose fork management inside the new OpenPilot UI (“new eye”), implement
the following roadmap:

1. **Backend service layer**
   - Wrap `forkswap.sh` operations in a daemon or Python service that accepts
     RPC/param requests (`clone`, `switch`, `delete`, `list`, `update`).
   - Reuse the environment overrides to point the script at test sandboxes and
     to skip the interactive loop (`FORKSWAP_SKIP_MAIN=1`).
   - Emit structured responses (success, error text, required confirmation) so
     the UI can react without parsing console output.
2. **Params interface**
   - Define a small set of params (`ForkSwapAction`, `ForkSwapPayload`,
     `ForkSwapStatus`) to signal actions and propagate progress back to the UI.
   - Persist fork metadata (`fork_info.json`) in params for quick access without
     hitting the filesystem on every render.
3. **UI components**
   - Add a management panel that lists all forks, highlights update availability,
     and shows the active fork badge.
   - Provide affordances for cloning (name, URL, branch), switching (with param
     backup notice), deleting (with confirmation), and updating.
   - Surface log snippets or status toasts sourced from `ForkSwapStatus`.
4. **Validation & safety**
- Run the harness inside CI to guarantee core flows continue working.
- Gate destructive actions when OpenPilot is engaged by checking existing
  engagement params before invoking the backend.
- Offer a dry-run mode (set `FORKSWAP_SKIP_MAIN=1` and `FORKSWAP_ALLOW_NONROOT=1`)
  for diagnostic screens.

## Testing & Monitoring Checklist

- Add both harnesses to your CI pipeline: run the bash harness with a mirrored
  repo and the Python service harness to validate the Params contract.
- A convenience wrapper `tools/scripts/run_forkswap_tests.sh` executes both
  harnesses sequentially—handy for CI jobs or pre-commit hooks.
- Alert if `ForkSwapFailureStreak` exceeds a chosen threshold; inspect
  `ForkSwapLastResult` for the JSON payload describing the failing action.
- Capture `cloudlog` entries emitted by `forkswapd` for success/failure timing
  to feed dashboards.
- When updating overlay files run `./overlay/update_hashes.py` (or an
  equivalent helper) to regenerate `forkswap_manifest.json.sha256`; this keeps
  the hash validation in sync with your changes.

Document the API and UI expectations alongside the service implementation so
future forks can integrate with the same interface.
