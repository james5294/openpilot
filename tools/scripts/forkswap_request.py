#!/usr/bin/env python3
import argparse
import json
import sys
import time
import uuid
from typing import Dict, Optional

try:
  from openpilot.common.params import Params  # type: ignore
except (ImportError, OSError):
  Params = None  # type: ignore

from openpilot.selfdrive.forkswap.types import ForkSwapRequest, ForkSwapState, ForkSwapStatus


def build_options(args: argparse.Namespace) -> Dict:
  options: Dict[str, object] = {}
  if args.reboot is not None:
    options["reboot"] = args.reboot
  if args.reboot_cmd:
    options["reboot_cmd"] = args.reboot_cmd
  if args.timeout:
    options["timeout"] = args.timeout
  if args.on_exists:
    options["on_exists"] = args.on_exists
  if args.rename_to:
    options["rename_to"] = args.rename_to
  if args.confirm is not None:
    options["confirm"] = args.confirm
  if args.accept_local_changes is not None:
    options["accept_local_changes"] = args.accept_local_changes
  if args.allow_nonroot:
    options.setdefault("env", {})
    options["allow_nonroot"] = True
  if args.paths:
    paths = {}
    for entry in args.paths:
      if "=" not in entry:
        raise ValueError(f"Invalid path override '{entry}'. Use key=value syntax.")
      key, value = entry.split("=", 1)
      paths[key] = value
    options["paths"] = paths
  if args.env:
    env = {}
    for entry in args.env:
      if "=" not in entry:
        raise ValueError(f"Invalid env override '{entry}'. Use KEY=VALUE syntax.")
      key, value = entry.split("=", 1)
      env[key] = value
    options.setdefault("env", {}).update(env)
  if args.check_updates:
    options["check_updates"] = True
  return options


def wait_for_completion(params: "Params", request_id: str, poll_interval: float) -> ForkSwapStatus:
  last_state: Optional[str] = None
  while True:
    raw = params.get("ForkSwapStatus", encoding="utf-8")
    status = ForkSwapStatus.from_raw(raw)
    if status.request_id != request_id:
      time.sleep(poll_interval)
      continue
    if status.state != last_state or status.message:
      print(f"[{status.state}] {status.message}")
      if status.detail:
        print(json.dumps(status.detail, indent=2, sort_keys=True))
      if status.log_tail:
        print("---- log tail ----")
        for line in status.log_tail[-10:]:
          print(line)
        print("------------------")
      last_state = status.state
    if status.state in (ForkSwapState.SUCCESS, ForkSwapState.ERROR):
      return status
    time.sleep(poll_interval)


def main() -> int:
  parser = argparse.ArgumentParser(description="Submit fork management requests via ForkSwapService.")
  parser.add_argument("action", choices=["clone", "switch", "delete", "update", "list", "status"], help="Action to perform")
  parser.add_argument("--fork", help="Target fork name (required for clone/switch/delete/update)")
  parser.add_argument("--url", help="Git URL for clone")
  parser.add_argument("--branch", help="Branch for clone/update")
  parser.add_argument("--request-id", help="Optional request identifier (defaults to random uuid)")
  parser.add_argument("--reboot", dest="reboot", action="store_true", help="Request reboot prompt be confirmed")
  parser.add_argument("--no-reboot", dest="reboot", action="store_false", help="Disable reboot prompt")
  parser.set_defaults(reboot=None)
  parser.add_argument("--reboot-cmd", help="Command to execute when rebooting (defaults to system reboot)")
  parser.add_argument("--timeout", type=float, help="Per-action timeout in seconds")
  parser.add_argument("--allow-nonroot", action="store_true", help="Allow running forkswap without root privileges")
  parser.add_argument("--on-exists", choices=["overwrite", "rename"], help="Clone behaviour when fork already exists")
  parser.add_argument("--rename-to", help="Rename target when on_exists=rename")
  parser.add_argument("--confirm", dest="confirm", action="store_true", help="Auto-confirm prompts when supported")
  parser.add_argument("--no-confirm", dest="confirm", action="store_false", help="Deny prompts when supported")
  parser.set_defaults(confirm=None)
  parser.add_argument("--accept-local-changes", dest="accept_local_changes", action="store_true", help="Allow update to overwrite local changes")
  parser.add_argument("--reject-local-changes", dest="accept_local_changes", action="store_false", help="Abort update if local changes exist")
  parser.set_defaults(accept_local_changes=None)
  parser.add_argument("--paths", nargs="*", help="Override paths (key=value for openpilot_dir,forks_dir,params_path,current_fork_file,log_file,lock_path)")
  parser.add_argument("--env", nargs="*", help="Extra environment variables for forkswap.sh (KEY=VALUE)")
  parser.add_argument("--check-updates", action="store_true", help="For list/status actions, perform git fetch to detect updates")
  parser.add_argument("--wait", action="store_true", help="Wait for completion and stream status logs")
  parser.add_argument("--no-wait", action="store_false", dest="wait", help="Return immediately after enqueueing request")
  parser.set_defaults(wait=True)
  parser.add_argument("--poll-interval", type=float, default=1.0, help="Polling interval when waiting for completion (seconds)")

  args = parser.parse_args()

  if Params is None:
    print("Error: openpilot.common.params is unavailable in this environment. Run this script on a device or build the params extension.", file=sys.stderr)
    return 2

  request_id = args.request_id or uuid.uuid4().hex
  options = build_options(args)

  payload = {
    "request_id": request_id,
    "action": args.action,
    "fork": args.fork,
    "url": args.url,
    "branch": args.branch,
    "options": options,
  }

  try:
    ForkSwapRequest.from_raw(payload)  # validate payload early
  except Exception as exc:  # pylint: disable=broad-exception-caught
    print(f"Invalid request: {exc}", file=sys.stderr)
    return 2

  params = Params()
  params.put("ForkSwapPayload", json.dumps(payload))
  params.put("ForkSwapAction", request_id)
  print(f"Submitted forkswap request {request_id} ({args.action}).")

  if not args.wait:
    return 0

  status = wait_for_completion(params, request_id, args.poll_interval)
  return 0 if status.state == ForkSwapState.SUCCESS else 1


if __name__ == "__main__":
  sys.exit(main())
