from __future__ import annotations

import json
import os
import re
import subprocess
import time
from dataclasses import asdict
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from openpilot.common.basedir import BASEDIR
try:
  from openpilot.common.params import Params, UnknownKeyName  # type: ignore
except (ImportError, OSError):  # pragma: no cover - fallback for harness environments
  Params = None  # type: ignore

  class UnknownKeyName(Exception):  # type: ignore
    pass
try:
  from openpilot.common.swaglog import cloudlog
except (ImportError, OSError):
  class _CloudlogStub:  # pragma: no cover - fallback for harness environments without full deps
    def __getattr__(self, name):
      return lambda *args, **kwargs: None
  cloudlog = _CloudlogStub()
from openpilot.selfdrive.forkswap.types import (
  ForkInfo,
  ForkSwapRequest,
  ForkSwapState,
  ForkSwapStatus,
  SUPPORTED_ACTIONS,
)


DEFAULT_SCRIPT_PATH = os.path.join(BASEDIR, "tools", "scripts", "forkswap.sh")
DEFAULT_OPENPILOT_DIR = "/data/openpilot"
DEFAULT_FORKS_DIR = "/data/forks"
DEFAULT_CURRENT_FORK_FILE = "/data/current_fork.txt"
DEFAULT_LOG_FILE = "/data/fork_swap.log"
DEFAULT_POLL_INTERVAL = 1.0
DEFAULT_TIMEOUT = 900.0  # 15 minutes
GIT_URL_PATTERN = re.compile(r'^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?/?$')


class ForkSwapService:
  """
  Service wrapper that watches the ForkSwapAction param, executes forkswap.sh
  actions, and publishes structured status updates for the UI.
  """

  def __init__(
    self,
    *,
    params: Optional[Params] = None,
    script_path: Optional[str] = None,
    poll_interval: float = DEFAULT_POLL_INTERVAL,
    timeout: float = DEFAULT_TIMEOUT,
    allow_nonroot: bool = True,
    log_tail_lines: int = 200,
    base_paths: Optional[Dict[str, str]] = None,
    env_overrides: Optional[Dict[str, str]] = None,
  ) -> None:
    if params is not None:
      self.params = params
    else:
      if Params is None:
        raise RuntimeError("ForkSwapService requires a Params instance when openpilot.common.params is unavailable.")
      self.params = Params()
    self.script_path = script_path or DEFAULT_SCRIPT_PATH
    self.poll_interval = poll_interval
    self.timeout = timeout
    self.allow_nonroot = allow_nonroot
    self.log_tail_lines = log_tail_lines
    self.base_paths = base_paths or {}
    default_env = {
      "FORKSWAP_DISABLE_UPDATE_CHECK": "1",
    }
    if env_overrides:
      default_env.update(env_overrides)
    self.env_overrides = default_env

    if not os.path.exists(self.script_path):
      raise FileNotFoundError(f"forkswap script not found at {self.script_path}")

    self.status = ForkSwapStatus(message="Forkswap service initialized.")
    self.overlay_status = "ok"
    self._set_overlay_status("ok")
    self.last_request_id: Optional[str] = None

    try:
      self._verify_overlay()
    except Exception as exc:  # pylint: disable=broad-exception-caught
      cloudlog.error("ForkSwapService overlay verification failed: %s", exc)

  # ------------------------------------------------------------------------- #
  # Public API
  # ------------------------------------------------------------------------- #
  def run_forever(self) -> None:
    """Main loop – monitor params and process requests."""
    self._publish_status()
    while True:
      try:
        self.process_once()
      except Exception as exc:  # pylint: disable=broad-exception-caught
        self.status.update(
          state=ForkSwapState.ERROR,
          message=f"Unhandled service error: {exc}",
          detail=self._detail_with_overlay({"exception": repr(exc)}),
        )
        self._publish_status()
        self._increment_error_counter()
      finally:
        self._write_heartbeat()
      time.sleep(self.poll_interval)

  def process_once(self) -> None:
    """Check if a new request arrived and handle it."""
    token = self._read_param("ForkSwapAction")
    if token is None or token == self.last_request_id:
      return

    payload_raw = self._read_param("ForkSwapPayload")
    try:
      request = ForkSwapRequest.from_raw(payload_raw)
    except (ValueError, TypeError) as exc:
      self._handle_invalid_request(token, f"Invalid payload: {exc}")
      cloudlog.warning("ForkSwapService invalid payload (token=%s): %s", token, exc)
      return

    if request.request_id != token:
      # Ensure UI and service are aligned on request identity
      self._handle_invalid_request(token, "Request ID mismatch between action and payload.")
      cloudlog.warning("ForkSwapService request_id mismatch action=%s payload=%s", token, request.request_id)
      return

    self.last_request_id = token
    cloudlog.info("ForkSwapService handling request %s (%s)", request.request_id, request.action)
    self._handle_request(request)

  # ------------------------------------------------------------------------- #
  # Request handling
  # ------------------------------------------------------------------------- #
  def _handle_request(self, request: ForkSwapRequest) -> None:
    validation_error = self._validate_request(request)
    if validation_error is not None:
      self._reject_request(request, validation_error)
      return

    start_time = time.time()
    duration = 0.0
    success = False
    if request.action == "repair_overlay":
      self._set_overlay_status("repairing")
    self.status.update(
      state=ForkSwapState.RUNNING,
      action=request.action,
      request_id=request.request_id,
      message="Processing request.",
      detail=self._detail_with_overlay({"request": asdict(request)}),
      log_tail=[],
      started_at=start_time,
      duration=None,
    )
    self._publish_status()

    env = self._build_env(request)

    if request.action == "clone":
      forks_dir = env.get("FORKS_DIR", self.base_paths.get("forks_dir", DEFAULT_FORKS_DIR))
      if not self._check_disk_space(forks_dir):
        self._reject_request(request, "Insufficient disk space for clone operation.")
        return

    try:
      if request.action == "list":
        forks = self._list_forks(env, request)
        duration = time.time() - start_time
        self.status.update(
          state=ForkSwapState.SUCCESS,
          message=f"Found {len(forks)} fork(s).",
          detail=self._detail_with_overlay({"forks": [fork.to_dict() for fork in forks]}),
          duration=time.time() - start_time,
        )
        success = True
        self._publish_status()
        return

      if request.action == "status":
        forks = self._list_forks(env, request)
        active = self._read_current_fork(env)
        duration = time.time() - start_time
        self.status.update(
          state=ForkSwapState.SUCCESS,
          message="Status refreshed.",
          detail=self._detail_with_overlay({"forks": [fork.to_dict() for fork in forks], "current_fork": active}),
          duration=time.time() - start_time,
        )
        success = True
        self._publish_status()
        return

      try:
        progress_interval = float(request.options.get("progress_interval", 1.0))
      except (TypeError, ValueError):
        progress_interval = 1.0
      if not progress_interval or progress_interval < 0:
        progress_interval = 1.0
      progress_interval = max(0.3, min(progress_interval, 5.0))

      def progress_cb() -> None:
        self._publish_running_progress(request, start_time, env)

      stdout, stderr, returncode = self._run_script(request, env, progress_cb, progress_interval)
      log_tail = self._read_log_tail(env)

      if returncode == 0:
        msg = f"{request.action.capitalize()} operation completed."
        success = True
        duration = time.time() - start_time
        cloudlog.info("ForkSwapService success %s (%.2fs)", request.action, time.time() - start_time)
        overlay_state = self.overlay_status
        if request.action == "repair_overlay":
          overlay_state = "ok"
          self._set_overlay_status(overlay_state)
        detail_payload = {
          "request": asdict(request),
          "stdout": stdout,
          "stderr": stderr,
          "returncode": returncode,
          "overlay_status": overlay_state,
        }
        self.status.update(
          state=ForkSwapState.SUCCESS,
          message=msg,
          detail=self._detail_with_overlay(detail_payload),
          log_tail=log_tail,
          duration=time.time() - start_time,
        )
        self._refresh_assets_bundle()
      else:
        msg = f"{request.action.capitalize()} failed (return code {returncode})."
        cloudlog.error("ForkSwapService failure %s returncode=%s", request.action, returncode)
        duration = time.time() - start_time
        overlay_state = self.overlay_status
        if request.action == "repair_overlay":
          overlay_state = "repair_failed"
          self._set_overlay_status(overlay_state)
        detail_payload = {
          "request": asdict(request),
          "stdout": stdout,
          "stderr": stderr,
          "returncode": returncode,
          "overlay_status": overlay_state,
        }
        self.status.update(
          state=ForkSwapState.ERROR,
          message=msg,
          detail=self._detail_with_overlay(detail_payload),
          log_tail=log_tail,
          duration=time.time() - start_time,
        )
    except subprocess.TimeoutExpired as exc:
      cloudlog.error("ForkSwapService timeout %s after %.0fs", request.action, self.timeout)
      duration = time.time() - start_time
      overlay_state = self.overlay_status
      if request.action == "repair_overlay":
        overlay_state = "repair_failed"
        self._set_overlay_status(overlay_state)
      self.status.update(
        state=ForkSwapState.ERROR,
        message=f"{request.action.capitalize()} timed out after {self.timeout:.0f}s.",
        detail=self._detail_with_overlay({"request": asdict(request), "exception": repr(exc), "overlay_status": overlay_state}),
        duration=time.time() - start_time,
      )
    except FileNotFoundError as exc:
      cloudlog.error("ForkSwapService missing resource for %s: %s", request.action, exc)
      duration = time.time() - start_time
      overlay_state = self.overlay_status
      if request.action == "repair_overlay":
        overlay_state = "repair_failed"
        self._set_overlay_status(overlay_state)
      self.status.update(
        state=ForkSwapState.ERROR,
        message=f"Required resource missing: {exc}",
        detail=self._detail_with_overlay({"request": asdict(request), "overlay_status": overlay_state}),
        duration=time.time() - start_time,
      )
    except Exception as exc:  # pylint: disable=broad-exception-caught
      cloudlog.exception("ForkSwapService unhandled exception during %s", request.action)
      duration = time.time() - start_time
      overlay_state = self.overlay_status
      if request.action == "repair_overlay":
        overlay_state = "repair_failed"
        self._set_overlay_status(overlay_state)
      self.status.update(
        state=ForkSwapState.ERROR,
        message=f"Unhandled exception during {request.action}: {exc}",
        detail=self._detail_with_overlay({
          "request": asdict(request),
          "exception": repr(exc),
          "overlay_status": overlay_state,
        }),
        duration=time.time() - start_time,
      )
    finally:
      self._record_outcome(success, request, duration)
      self._publish_status()
      self._clear_action_params(request.request_id)

  def _publish_running_progress(self, request: ForkSwapRequest, start_time: float, env: Dict[str, str]) -> None:
    log_tail = self._read_log_tail(env)
    duration = time.time() - start_time
    self.status.update(
      log_tail=log_tail,
      duration=duration,
    )
    self._publish_status()

  def _handle_invalid_request(self, token: str, message: str) -> None:
    self.last_request_id = token
    self.status.update(
      state=ForkSwapState.ERROR,
      action=None,
      request_id=token,
      message=message,
    )
    self._publish_status()
    self._clear_action_params(token)

  # ------------------------------------------------------------------------- #
  # Environment & execution helpers
  # ------------------------------------------------------------------------- #
  def _validate_request(self, request: ForkSwapRequest) -> Optional[str]:
    if request.action in {"clone", "switch", "delete", "update"} and not self._is_offroad():
      return "Cannot modify forks while vehicle is engaged."

    # Clone actions auto-generate fork name from URL+branch, so fork name is optional
    if request.action in {"switch", "delete", "update", "rename"}:
      if not request.fork or not self._validate_fork_name(request.fork):
        return "Invalid fork name provided."

    if request.action == "clone":
      if not request.url or not self._validate_url(request.url):
        return "Invalid repository URL."
      if request.branch and not self._validate_branch_name(request.branch):
        return "Invalid branch name."
      exists_mode = request.options.get("on_exists") if isinstance(request.options, dict) else None
      if exists_mode == "rename":
        rename_to = request.options.get("rename_to")
        if not rename_to or not self._validate_fork_name(str(rename_to)):
          return "Invalid rename target for existing fork."
      elif exists_mode and exists_mode not in {"overwrite", "abort", None}:
        return "Invalid on_exists option."

    if request.action == "rename":
      new_name = None
      if isinstance(request.options, dict):
        new_name = request.options.get("rename_to")
      if not new_name or not self._validate_fork_name(str(new_name)):
        return "Invalid rename target provided."
      if str(new_name).strip().lower() == request.fork.strip().lower():
        return "New fork name must be different from the current name."
    if request.action == "repair_overlay":
      return None

    return None

  def _reject_request(self, request: ForkSwapRequest, message: str) -> None:
    payload = asdict(request)
    self.status.update(
      state=ForkSwapState.ERROR,
      action=request.action,
      request_id=request.request_id,
      message=message,
      detail=self._detail_with_overlay({"request": payload}),
    )
    self._record_outcome(False, request, 0.0)
    self._publish_status()
    self._clear_action_params(request.request_id)

  def _validate_fork_name(self, name: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_-]+", name))

  def _validate_branch_name(self, name: str) -> bool:
    if ".." in name:
      return False
    return bool(re.fullmatch(r"[A-Za-z0-9._/-]+", name))

  def _validate_url(self, url: str) -> bool:
    if url.startswith("file://"):
      return True
    return bool(GIT_URL_PATTERN.fullmatch(url))

  def _extract_github_username(self, url: str) -> Optional[str]:
    """Extract GitHub username from URL for auto-naming."""
    # Remove protocol, www, .git, trailing slashes
    cleaned = url.replace("https://", "").replace("http://", "").replace("www.", "").rstrip("/")
    if cleaned.endswith(".git"):
      cleaned = cleaned[:-4]

    # Extract username from github.com/username/repo
    if "github.com/" in cleaned:
      parts = cleaned.split("github.com/", 1)
      if len(parts) == 2:
        username = parts[1].split("/")[0]
        return username if username else None
    return None

  def _is_offroad(self) -> bool:
    try:
      if hasattr(self.params, "get_bool"):
        return bool(self.params.get_bool("IsOffroad"))
    except UnknownKeyName:
      pass
    except Exception:
      pass
    try:
      raw = self.params.get("IsOffroad", encoding="utf-8")
      if raw is None:
        return False
      if isinstance(raw, bytes):
        raw = raw.decode("utf-8")
      return raw == "1"
    except UnknownKeyName:
      return False
    except Exception:
      return False

  def _check_disk_space(self, path: str, required_mb: int = 500) -> bool:
    try:
      os.makedirs(path, exist_ok=True)
      stats = os.statvfs(path)
      available_mb = (stats.f_bavail * stats.f_frsize) / (1024 * 1024)
      return available_mb >= required_mb
    except OSError:
      return False

  def _write_heartbeat(self) -> None:
    timestamp = str(int(time.time()))
    try:
      self.params.put_nonblocking("ForkSwapServiceHeartbeat", timestamp)
    except (UnknownKeyName, AttributeError):
      pass

  def _increment_error_counter(self) -> None:
    try:
      raw = self.params.get("ForkSwapServiceErrorCount", encoding="utf-8")
      current = int(raw) if raw is not None else 0
    except (UnknownKeyName, ValueError, TypeError):
      current = 0
    current += 1
    try:
      self.params.put_nonblocking("ForkSwapServiceErrorCount", str(current))
    except (UnknownKeyName, AttributeError):
      pass

  PATH_ENV_MAPPING: Dict[str, str] = {
    "openpilot_dir": "OPENPILOT_DIR",
    "forks_dir": "FORKS_DIR",
    "params_path": "PARAMS_PATH",
    "current_fork_file": "CURRENT_FORK_FILE",
    "log_file": "LOG_FILE",
    "lock_path": "FORKSWAP_LOCK_PATH",
  }

  def _apply_paths(self, env: Dict[str, str], paths: Dict[str, Any]) -> None:
    for key, env_key in self.PATH_ENV_MAPPING.items():
      if key in paths and paths[key]:
        env[env_key] = str(paths[key])

  def _base_env(self) -> Dict[str, str]:
    env: Dict[str, str] = dict(os.environ)
    env.setdefault("TERM", "dumb")
    if self.allow_nonroot:
      env["FORKSWAP_ALLOW_NONROOT"] = "1"
    env.setdefault("FORKSWAP_REBOOT_CMD", ":")

    self._apply_paths(env, self.base_paths)

    env.update({str(k): str(v) for k, v in self.env_overrides.items()})
    return env

  def _build_env(self, request: ForkSwapRequest) -> Dict[str, str]:
    env = self._base_env()

    if request.options.get("allow_nonroot") is True:
      env["FORKSWAP_ALLOW_NONROOT"] = "1"
    elif not self.allow_nonroot and "FORKSWAP_ALLOW_NONROOT" in env:
      env.pop("FORKSWAP_ALLOW_NONROOT", None)

    request_paths = request.options.get("paths")
    if isinstance(request_paths, dict):
      self._apply_paths(env, request_paths)

    if request.options.get("reboot") is True:
      env["FORKSWAP_REBOOT_CMD"] = request.options.get("reboot_cmd", "reboot")

    if isinstance(request.options.get("env"), dict):
      env.update({str(k): str(v) for k, v in request.options["env"].items()})

    if request.options.get("skip_overlay") is True or request.action in {"status", "list"}:
      env["FORKSWAP_SKIP_OVERLAY"] = "1"
    else:
      env.pop("FORKSWAP_SKIP_OVERLAY", None)
    return env

  def _set_overlay_status(self, value: str) -> None:
    self.overlay_status = value
    self.status.overlay_status = value
    if isinstance(self.status.detail, dict):
      self.status.detail["overlay_status"] = value
    else:
      self.status.detail = {"overlay_status": value}

  def _detail_with_overlay(self, base: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    detail: Dict[str, Any] = dict(base or {})
    detail["overlay_status"] = self.overlay_status
    return detail

  def _refresh_assets_bundle(self) -> None:
    env = self._base_env()
    env["FORKSWAP_SKIP_MAIN"] = "1"
    env["FORKSWAP_DISABLE_UPDATE_CHECK"] = "1"
    env["FORKSWAP_SKIP_OVERLAY"] = "1"
    try:
      result = subprocess.run(
        [self.script_path, "--refresh-assets"],
        check=True,
        capture_output=True,
        text=True,
        env=env,
      )
      if result.stdout.strip():
        cloudlog.debug("ForkSwapService asset refresh output: %s", result.stdout.strip())
    except subprocess.CalledProcessError as exc:
      cloudlog.error("ForkSwapService asset refresh failed (returncode=%s): %s", exc.returncode, exc.stderr.strip())

  def _verify_overlay(self) -> None:
    openpilot_dir = Path(self.base_paths.get("openpilot_dir", DEFAULT_OPENPILOT_DIR))
    marker = openpilot_dir / "selfdrive" / "forkswap" / "__init__.py"
    if marker.exists():
      self._refresh_assets_bundle()
      self._set_overlay_status("ok")
      return

    cloudlog.warning("Forkswap overlay missing; attempting repair.")
    env = self._base_env()
    env["FORKSWAP_SKIP_MAIN"] = "1"
    env["FORKSWAP_DISABLE_UPDATE_CHECK"] = "1"

    try:
      result = subprocess.run(
        [self.script_path, "--repair-overlay"],
        check=True,
        capture_output=True,
        text=True,
        env=env,
      )
      cloudlog.info("Overlay repair output: %s", result.stdout.strip())
    except subprocess.CalledProcessError as exc:
      cloudlog.error("Overlay repair failed (returncode=%s): %s", exc.returncode, exc.stderr.strip())
      self._set_overlay_status("repair_failed")
      return

    if not marker.exists():
      cloudlog.error("Overlay repair completed but marker still missing at %s", marker)
      self._set_overlay_status("repair_incomplete")
    else:
      cloudlog.info("Overlay repair successful; marker restored at %s", marker)
      self._set_overlay_status("ok")

  def _run_script(
    self,
    request: ForkSwapRequest,
    env: Dict[str, str],
    progress_cb: Optional[Callable[[], None]] = None,
    progress_interval: float = 1.0,
  ) -> Tuple[str, str, int]:
    input_lines = self._build_input_sequence(request, env)
    command_input = "\n".join(input_lines) + "\n" if input_lines else None
    cmd = ["/bin/bash", self.script_path]
    if request.action == "repair_overlay":
      cmd.append("--repair-overlay")
      command_input = None
    timeout = float(request.options.get("timeout", self.timeout))

    proc = subprocess.Popen(
      cmd,
      stdin=subprocess.PIPE,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
      env=env,
    )

    if command_input is not None:
      try:
        if proc.stdin:
          try:
            proc.stdin.write(command_input)
            proc.stdin.flush()
          except BrokenPipeError:
            pass
          finally:
            proc.stdin.close()
      except OSError:
        pass

    deadline = time.time() + timeout
    progress_interval = max(0.25, progress_interval)
    last_progress = 0.0

    if progress_cb is not None:
      progress_cb()
      last_progress = time.time()

    try:
      while True:
        retcode = proc.poll()
        now = time.time()
        if retcode is not None:
          break

        if now >= deadline:
          raise subprocess.TimeoutExpired(proc.args, timeout)

        if progress_cb is not None and (now - last_progress) >= progress_interval:
          progress_cb()
          last_progress = now

        sleep_window = min(progress_interval, 0.5)
        remaining = deadline - now
        if remaining < sleep_window:
          sleep_window = max(0.1, remaining)
        time.sleep(sleep_window)
    except subprocess.TimeoutExpired:
      cloudlog.warning("forkswap.sh timed out; attempting graceful termination")
      proc.terminate()
      try:
        proc.wait(timeout=2)
      except subprocess.TimeoutExpired:
        cloudlog.warning("forkswap.sh did not terminate after SIGTERM; killing")
        proc.kill()
      raise

    exit_code = proc.returncode
    if exit_code is None:
      exit_code = proc.wait()

    if progress_cb is not None:
      progress_cb()

    stdout = ""
    stderr = ""
    try:
      if proc.stdout:
        stdout = proc.stdout.read()
    except OSError:
      stdout = ""
    try:
      if proc.stderr:
        stderr = proc.stderr.read()
    except OSError:
      stderr = ""

    return stdout.strip(), stderr.strip(), exit_code

  def _build_input_sequence(
    self,
    request: ForkSwapRequest,
    env: Dict[str, str],
  ) -> List[str]:
    reboot_choice = "y" if request.options.get("reboot") else "n"
    forks_dir = env.get("FORKS_DIR", DEFAULT_FORKS_DIR)
    fork_name = (request.fork or "").strip()
    lines: List[str] = []

    if request.action == "clone":
      if not request.url:
        raise ValueError("Clone request requires 'url'.")

      # Auto-generate fork name from URL + branch
      username = self._extract_github_username(request.url)
      if not username:
        raise ValueError(f"Unable to extract GitHub username from URL: {request.url}")

      branch = request.branch or ""
      # If no branch specified, we'll let bash auto-detect it, but we need to know it for fork name
      # For now, use the provided branch or "main" as fallback for naming
      branch_for_name = branch if branch else "main"
      auto_fork_name = f"{username}-{branch_for_name}"

      if not self._validate_fork_name(auto_fork_name):
        raise ValueError(f"Auto-generated fork name '{auto_fork_name}' contains invalid characters.")

      existing_path = os.path.join(forks_dir, auto_fork_name)
      on_exists = request.options.get("on_exists", "abort")
      rename_to = request.options.get("rename_to")
      if os.path.isdir(existing_path):
        if on_exists not in {"overwrite", "rename"}:
          raise ValueError(f"Target fork '{auto_fork_name}' already exists; set options.on_exists to 'overwrite' or 'rename'.")
        if on_exists == "rename" and not rename_to:
          raise ValueError("options.rename_to is required when on_exists='rename'.")

      # New bash script input sequence: Clone, URL, branch, (conflict handling), reboot, Exit
      lines.append("Clone")
      lines.append(request.url or "")
      lines.append(branch)  # Can be empty for auto-detection
      if os.path.isdir(existing_path):
        if on_exists == "overwrite":
          lines.append("overwrite")
        else:
          lines.extend(["rename", rename_to])
      lines.append(reboot_choice)
      lines.append("Exit")
      return lines

    if request.action == "switch":
      if not fork_name:
        raise ValueError("Switch request requires 'fork'.")
      confirm = "y" if request.options.get("confirm", True) else "n"
      lines.extend([fork_name, confirm, reboot_choice, "Exit"])
      return lines

    if request.action == "delete":
      if not fork_name:
        raise ValueError("Delete request requires 'fork'.")
      confirm = "y" if request.options.get("confirm", True) else "n"
      lines.extend(["Delete", fork_name, confirm, "Exit"])
      return lines

    if request.action == "update":
      if not fork_name:
        raise ValueError("Update request requires 'fork'.")
      local_changes = self._has_local_changes(os.path.join(forks_dir, fork_name, "openpilot"))
      lines.append(f"update {fork_name}")
      if local_changes:
        answer = "y" if request.options.get("accept_local_changes", True) else "n"
        lines.append(answer)
      lines.append("Exit")
      return lines

    if request.action == "rename":
      if not fork_name:
        raise ValueError("Rename request requires 'fork'.")
      new_name = request.options.get("rename_to") if isinstance(request.options, dict) else None
      if not new_name:
        raise ValueError("Rename request requires options.rename_to.")
      lines.extend(["Rename", fork_name, str(new_name), "Exit"])
      return lines

    if request.action == "repair_overlay":
      return []

    raise ValueError(f"Unsupported interactive action '{request.action}'")

  # ------------------------------------------------------------------------- #
  # Utility helpers
  # ------------------------------------------------------------------------- #
  def _read_param(self, key: str) -> Optional[str]:
    try:
      raw = self.params.get(key, encoding="utf-8")
    except UnknownKeyName:
      return None
    return raw

  def _publish_status(self) -> None:
    if not isinstance(self.status.detail, dict):
      self.status.detail = {}
    if self.status.detail.get("overlay_status") != self.overlay_status:
      self.status.detail = self._detail_with_overlay(dict(self.status.detail))
    self.status.overlay_status = self.overlay_status
    try:
      self.params.put_nonblocking("ForkSwapStatus", self.status.to_json())
    except UnknownKeyName:
      # Param not registered; ignore in testing contexts.
      pass

  def _clear_action_params(self, expected_request_id: Optional[str]) -> None:
    current_token = None
    try:
      current_token = self.params.get("ForkSwapAction", encoding="utf-8")
    except UnknownKeyName:
      pass

    if expected_request_id is None or current_token == expected_request_id:
      try:
        if current_token is not None:
          self.params.remove("ForkSwapAction")
      except UnknownKeyName:
        pass

    payload_raw = None
    try:
      payload_raw = self.params.get("ForkSwapPayload", encoding="utf-8")
    except UnknownKeyName:
      pass

    if payload_raw is None:
      if expected_request_id is None:
        try:
          self.params.remove("ForkSwapPayload")
        except UnknownKeyName:
          pass
      return

    payload_request_id = None
    try:
      payload_request_id = json.loads(payload_raw).get("request_id")
    except json.JSONDecodeError:
      pass

    if expected_request_id is None or payload_request_id == expected_request_id:
      try:
        self.params.remove("ForkSwapPayload")
      except UnknownKeyName:
        pass

  def _record_outcome(self, success: bool, request: ForkSwapRequest, duration: float) -> None:
    payload = {
      "ts": time.time(),
      "success": success,
      "action": request.action,
      "fork": request.fork,
      "request_id": request.request_id,
      "duration": duration,
      "state": self.status.state,
      "message": self.status.message,
    }
    json_blob = json.dumps(payload, separators=(",", ":"))

    try:
      streak_raw = self.params.get("ForkSwapFailureStreak")
      streak = int(streak_raw.decode("utf-8")) if streak_raw else 0
    except (UnknownKeyName, ValueError, AttributeError):
      streak = 0

    if success:
      streak = 0
    else:
      streak += 1

    try:
      self.params.put_nonblocking("ForkSwapFailureStreak", str(streak))
      self.params.put_nonblocking("ForkSwapLastResult", json_blob)
    except UnknownKeyName:
      pass

  def _list_forks(self, env: Dict[str, str], request: ForkSwapRequest) -> List[ForkInfo]:
    forks_dir = env.get("FORKS_DIR", DEFAULT_FORKS_DIR)
    current = self._read_current_fork(env)
    check_updates = bool(request.options.get("check_updates"))
    forks: List[ForkInfo] = []

    if not os.path.isdir(forks_dir):
      return forks

    for entry in sorted(os.listdir(forks_dir)):
      fork_path = os.path.join(forks_dir, entry)
      if not os.path.isdir(fork_path):
        continue

      info_file = os.path.join(fork_path, "fork_info.json")
      url = None
      branch = None
      if os.path.isfile(info_file):
        try:
          with open(info_file, "r", encoding="utf-8") as handle:
            metadata = json.load(handle)
            url = metadata.get("url")
            branch = metadata.get("branch")
        except (OSError, json.JSONDecodeError):
          pass

      has_update = None
      if check_updates and branch:
        has_update = self._check_for_updates(fork_path, branch)

      forks.append(
        ForkInfo(
          name=entry,
          path=fork_path,
          branch=branch,
          url=url,
          has_update=has_update,
          is_current=(entry == current),
        )
      )
    return forks

  def _read_current_fork(self, env: Dict[str, str]) -> Optional[str]:
    current_file = env.get("CURRENT_FORK_FILE", DEFAULT_CURRENT_FORK_FILE)
    try:
      with open(current_file, "r", encoding="utf-8") as handle:
        return handle.read().strip() or None
    except OSError:
      return None

  def _check_for_updates(self, fork_path: str, branch: str) -> Optional[bool]:
    repo_path = os.path.join(fork_path, "openpilot")
    if not os.path.isdir(repo_path):
      return None
    try:
      subprocess.run(["git", "fetch", "origin", branch], cwd=repo_path, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
      local_commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo_path, check=True, capture_output=True, text=True, timeout=15).stdout.strip()
      remote_commit = subprocess.run(["git", "rev-parse", f"origin/{branch}"], cwd=repo_path, check=True, capture_output=True, text=True, timeout=15).stdout.strip()
      if not local_commit or not remote_commit:
        return None
      return local_commit != remote_commit
    except subprocess.SubprocessError:
      return None

  def _has_local_changes(self, repo_dir: str) -> bool:
    if not os.path.isdir(repo_dir):
      return False
    try:
      result = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
        check=True,
        timeout=15,
      )
      return bool(result.stdout.strip())
    except subprocess.SubprocessError:
      return False

  def _read_log_tail(self, env: Dict[str, str]) -> List[str]:
    log_file = env.get("LOG_FILE", DEFAULT_LOG_FILE)
    path = Path(log_file)
    if not path.exists():
      # If log rotated, try to read most recent rotated file
      rotated = sorted(path.parent.glob(f"{path.name}.*"), reverse=True)
      if rotated:
        path = rotated[0]
      else:
        return []
    try:
      with open(path, "r", encoding="utf-8") as handle:
        lines = handle.readlines()
      tail = [line.rstrip("\n") for line in lines[-self.log_tail_lines:]]
      return tail
    except OSError:
      return []

  # ------------------------------------------------------------------------- #
  # CLI helpers
  # ------------------------------------------------------------------------- #
  @staticmethod
  def format_status(status: ForkSwapStatus) -> str:
    data = asdict(status)
    return json.dumps(data, indent=2, sort_keys=True)


def main() -> None:
  service = ForkSwapService()
  service.run_forever()


if __name__ == "__main__":
  main()
