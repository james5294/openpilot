#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Optional

THIS_DIR = Path(__file__).resolve()
REPO_ROOT = THIS_DIR.parents[2]
if str(REPO_ROOT) not in sys.path:
  sys.path.insert(0, str(REPO_ROOT))

from openpilot.selfdrive.forkswap.service import ForkSwapService
from openpilot.selfdrive.forkswap.types import ForkSwapState, ForkSwapStatus


DEFAULT_MAIN_FORK = "james5294"


class FakeParams:
  def __init__(self) -> None:
    self._store: dict[str, str] = {}

  def get(self, key: str, block: bool = False, encoding: Optional[str] = None):  # pylint: disable=unused-argument
    value = self._store.get(key)
    if value is None:
      return None
    if encoding:
      return value if isinstance(value, str) else value.decode(encoding)
    return value

  def put_nonblocking(self, key: str, value: str) -> None:
    self._store[key] = value

  def put(self, key: str, value: str) -> None:
    self._store[key] = value

  def remove(self, key: str) -> None:
    self._store.pop(key, None)


def create_remote_repo(remote_path: Path, worktree_path: Path) -> None:
  subprocess.run(["git", "init", "--bare", remote_path.as_posix()], check=True)
  subprocess.run(["git", "init", worktree_path.as_posix()], check=True)
  subprocess.run(["git", "-C", worktree_path.as_posix(), "config", "user.email", "forkswap-harness@example.com"], check=True)
  subprocess.run(["git", "-C", worktree_path.as_posix(), "config", "user.name", "Forkswap Harness"], check=True)
  (worktree_path / "README.md").write_text("Harness repository\n", encoding="utf-8")
  subprocess.run(["git", "-C", worktree_path.as_posix(), "add", "README.md"], check=True)
  subprocess.run(["git", "-C", worktree_path.as_posix(), "commit", "-m", "Initial commit"], check=True)
  subprocess.run(["git", "-C", worktree_path.as_posix(), "branch", "-M", "main"], check=True)
  subprocess.run(["git", "-C", worktree_path.as_posix(), "remote", "add", "origin", remote_path.as_posix()], check=True)
  subprocess.run(["git", "-C", worktree_path.as_posix(), "push", "-u", "origin", "main"], check=True)


def run_request(service: ForkSwapService, params: FakeParams, payload: dict) -> ForkSwapStatus:
  request_id = payload.setdefault("request_id", uuid.uuid4().hex)
  params.put("ForkSwapPayload", json.dumps(payload))
  params.put("ForkSwapAction", request_id)
  service.process_once()
  status_raw = params.get("ForkSwapStatus")
  status = ForkSwapStatus.from_raw(status_raw)
  assert status.request_id == request_id, f"Status request_id mismatch: {status.request_id} != {request_id}"
  return status


def ensure(condition: bool, message: str) -> None:
  if not condition:
    raise AssertionError(message)


def resolved_link(path: Path) -> Path:
  target = Path(os.readlink(path))
  if not target.is_absolute():
    target = path.parent / target
  return target.resolve()


def main() -> None:
  tmp_root = Path(tempfile.mkdtemp(prefix="forkswap-service-"))
  keep_tmp = os.environ.get("FORKSWAP_HARNESS_KEEP_TMP") == "1"
  try:
    openpilot_dir = tmp_root / "openpilot"
    forks_dir = tmp_root / "forks"
    params_dir = tmp_root / "params"
    current_fork_file = tmp_root / "current_fork.txt"
    log_file = tmp_root / "forkswap.log"
    lock_path = tmp_root / "lock"
    assets_dir = tmp_root / "forkswap_assets"

    openpilot_dir.mkdir(parents=True, exist_ok=True)
    forks_dir.mkdir(parents=True, exist_ok=True)
    params_dir.mkdir(parents=True, exist_ok=True)
    (params_dir / "params.json").write_text('{"initial_param": 1}\n', encoding="utf-8")
    (openpilot_dir / "README.txt").write_text("Original checkout\n", encoding="utf-8")
    current_fork_file.write_text(f"{DEFAULT_MAIN_FORK}\n", encoding="utf-8")

    remote_root = tmp_root / "remotes"
    remote_root.mkdir(parents=True, exist_ok=True)
    remote_repo = remote_root / "localfork.git"
    worktree_path = tmp_root / "localfork-src"
    create_remote_repo(remote_repo, worktree_path)

    params = FakeParams()
    params.put("IsOffroad", "1")
    def make_service() -> ForkSwapService:
      return ForkSwapService(
        params=params,
        base_paths={
          "openpilot_dir": openpilot_dir.as_posix(),
          "forks_dir": forks_dir.as_posix(),
          "params_path": params_dir.as_posix(),
          "current_fork_file": current_fork_file.as_posix(),
          "log_file": log_file.as_posix(),
          "lock_path": lock_path.as_posix(),
        },
        env_overrides={"FORKSWAP_ALLOW_LOCAL_URLS": "1"},
      )

    service = make_service()
    metadata_file = assets_dir / "metadata.json"
    ensure(metadata_file.is_file(), "Asset metadata was not created during initialization.")
    asset_meta = json.loads(metadata_file.read_text(encoding="utf-8"))
    ensure(asset_meta.get("managed_fork") == DEFAULT_MAIN_FORK,
           f"Managed fork in asset metadata mismatch (expected {DEFAULT_MAIN_FORK}, got {asset_meta.get('managed_fork')}).")
    ensure(asset_meta.get("signature"), "Asset metadata missing signature field.")

    # Simulate managed fork change and ensure asset repository metadata updates
    current_fork_file.write_text("alt_manager\n", encoding="utf-8")
    service = make_service()
    asset_meta = json.loads(metadata_file.read_text(encoding="utf-8"))
    ensure(asset_meta.get("managed_fork") == "alt_manager",
           "Asset metadata did not update after managed fork change.")

    # Restore default managed fork before proceeding with rest of harness
    current_fork_file.write_text(f"{DEFAULT_MAIN_FORK}\n", encoding="utf-8")
    service = make_service()
    asset_meta = json.loads(metadata_file.read_text(encoding="utf-8"))
    ensure(asset_meta.get("managed_fork") == DEFAULT_MAIN_FORK,
           "Asset metadata did not revert to default managed fork.")

    # Clone new fork
    status = run_request(
      service,
      params,
      {
        "action": "clone",
        "fork": "localfork",
        "url": f"file://{remote_repo.as_posix()}",
        "branch": "main",
        "options": {"reboot": False},
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"Clone failed: {status.message}")
    actual_target = resolved_link(openpilot_dir)
    expected_target = (forks_dir / "localfork" / "openpilot").resolve()
    ensure(actual_target == expected_target,
           f"Symlink did not point to cloned fork (actual={actual_target}, expected={expected_target}).")

    # Switch back to main fork
    status = run_request(
      service,
      params,
      {
        "action": "switch",
        "fork": DEFAULT_MAIN_FORK,
        "options": {"reboot": False},
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"Switch failed: {status.message}")
    actual_target = resolved_link(openpilot_dir)
    expected_target = (forks_dir / DEFAULT_MAIN_FORK / "openpilot").resolve()
    ensure(actual_target == expected_target,
           f"Symlink did not point back to main fork (actual={actual_target}, expected={expected_target}).")

    # Clone again, forcing rename of existing localfork
    status = run_request(
      service,
      params,
      {
        "action": "clone",
        "fork": "localfork",
        "url": f"file://{remote_repo.as_posix()}",
        "branch": "main",
        "options": {"reboot": False, "on_exists": "rename", "rename_to": "localfork_backup"},
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"Clone with rename failed: {status.message}")
    ensure((forks_dir / "localfork_backup").is_dir(), "Renamed fork directory missing.")

    # Switch to main fork again before deleting inactive fork
    status = run_request(
      service,
      params,
      {
        "action": "switch",
        "fork": DEFAULT_MAIN_FORK,
        "options": {"reboot": False},
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"Switch before delete failed: {status.message}")

    # Delete inactive fork
    status = run_request(
      service,
      params,
      {
        "action": "delete",
        "fork": "localfork",
        "options": {"confirm": True},
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"Delete failed: {status.message}")
    ensure(not (forks_dir / "localfork").exists(), "localfork directory still present after deletion.")

    # Rename remaining fork
    status = run_request(
      service,
      params,
      {
        "action": "rename",
        "fork": "localfork_backup",
        "options": {"rename_to": "localfork_archive"},
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"Rename failed: {status.message}")
    ensure((forks_dir / "localfork_archive").is_dir(), "Renamed fork directory missing after rename action.")
    ensure(not (forks_dir / "localfork_backup").exists(), "Original fork directory still exists after rename.")

    # List forks
    status = run_request(
      service,
      params,
      {
        "action": "list",
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"List failed: {status.message}")
    names = {fork["name"] for fork in status.detail.get("forks", [])}
    ensure(DEFAULT_MAIN_FORK in names, "Main fork missing from listing.")
    ensure("localfork_archive" in names, "Renamed fork missing from listing.")

    # Status check with update detection disabled by default
    status = run_request(
      service,
      params,
      {
        "action": "status",
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"Status refresh failed: {status.message}")
    ensure(status.detail.get("current_fork") == DEFAULT_MAIN_FORK, "Current fork mismatch in status response.")
    ensure("duration" in status.to_json(), "Status payload missing duration field.")
    ensure(status.overlay_status == service.overlay_status, "Overlay status mismatch between service and payload after status action.")

    original_run_script = service._run_script

    # Simulate a failed repair to ensure status surfaces the error
    def failing_run_script(request, env, progress_cb=None, progress_interval=1.0):
      if request.action == "repair_overlay":
        return ("", "simulated failure", 1)
      return original_run_script(request, env, progress_cb, progress_interval)

    service._run_script = failing_run_script
    try:
      status = run_request(
        service,
        params,
        {
          "action": "repair_overlay",
          "options": {},
        },
      )
      ensure(status.state == ForkSwapState.ERROR, "Overlay repair should report failure when script returns non-zero.")
      ensure(status.overlay_status == "repair_failed", "Top-level overlay status did not report repair failure.")
      ensure(status.detail.get("overlay_status") == "repair_failed", "Detail overlay status did not report repair failure.")
      ensure(service.overlay_status == "repair_failed", "Service overlay status not updated after repair failure.")
    finally:
      service._run_script = original_run_script

    # Repair overlay (should succeed even if already healthy)
    status = run_request(
      service,
      params,
      {
        "action": "repair_overlay",
        "options": {},
      },
    )
    ensure(status.state == ForkSwapState.SUCCESS, f"Overlay repair action failed: {status.message}")
    ensure(status.overlay_status in {"ok", "repair_incomplete"}, "Unexpected overlay status after repair action.")
    ensure(status.detail.get("overlay_status") == status.overlay_status, "Detail overlay status should match top-level value.")
    ensure(service.overlay_status == status.overlay_status, "Service overlay status not cleared after successful repair.")

    # Concurrency: queue another action while one is running
    original_run_script = service._run_script
    second_request_id = uuid.uuid4().hex
    second_payload = {
      "action": "status",
      "options": {},
      "request_id": second_request_id,
    }

    def delayed_run_script(request, env, progress_cb=None, progress_interval=1.0):
      if request.action == "clone" and not getattr(service, "_concurrency_test", False):
        service._concurrency_test = True
        params.put("ForkSwapPayload", json.dumps(second_payload))
        params.put("ForkSwapAction", second_request_id)
      return original_run_script(request, env, progress_cb, progress_interval)

    service._run_script = delayed_run_script
    try:
      status = run_request(
        service,
        params,
        {
          "action": "clone",
          "fork": "localfork_concurrency",
          "url": f"file://{remote_repo.as_posix()}",
          "branch": "main",
          "options": {"reboot": False},
        },
      )
      ensure(status.state == ForkSwapState.SUCCESS, f"Clone during concurrency test failed: {status.message}")
    finally:
      service._run_script = original_run_script

    ensure(params.get("ForkSwapAction") == second_request_id, "Pending request cleared prematurely during concurrency test.")

    service.process_once()
    status_obj = ForkSwapStatus.from_raw(params.get("ForkSwapStatus"))
    ensure(status_obj.request_id == second_request_id, "Follow-up request was not processed after concurrency test.")
    ensure(status_obj.state == ForkSwapState.SUCCESS, "Follow-up status request failed after concurrency test.")
    ensure(params.get("ForkSwapAction") is None, "ForkSwapAction not cleared after processing queued request.")

    ensure(params._store.get("ForkSwapFailureStreak", "0") == "0", "Failure streak should reset after success.")
    ensure("ForkSwapLastResult" in params._store, "ForkSwapLastResult param missing.")

    print("Forkswap service harness completed successfully.")
    if keep_tmp:
      print(f"Harness workspace retained at: {tmp_root}")
    else:
      shutil.rmtree(tmp_root, ignore_errors=True)
  except Exception:
    if keep_tmp:
      print(f"Preserving failed workspace at: {tmp_root}")
    else:
      shutil.rmtree(tmp_root, ignore_errors=True)
    raise


if __name__ == "__main__":
  main()
