from __future__ import annotations

import json
import uuid
from typing import Optional, Tuple

from openpilot.selfdrive.forkswap.types import ForkSwapRequest, ForkSwapStatus

try:
  from openpilot.common.params import Params  # type: ignore
except (ImportError, OSError):
  Params = None  # type: ignore


def get_params(params: Optional["Params"] = None) -> "Params":
  if params is not None:
    return params
  if Params is None:
    raise RuntimeError("Params module unavailable; forkswap_client requires openpilot.common.params.")
  return Params()


def read_status(params: Optional["Params"] = None) -> ForkSwapStatus:
  store = get_params(params)
  raw = store.get("ForkSwapStatus", encoding="utf-8")
  return ForkSwapStatus.from_raw(raw)


def queue_request(
  action: str,
  *,
  fork: Optional[str] = None,
  url: Optional[str] = None,
  branch: Optional[str] = None,
  options: Optional[dict] = None,
  params: Optional["Params"] = None,
) -> Tuple[str, ForkSwapRequest]:
  store = get_params(params)
  payload = {
    "action": action,
    "fork": fork,
    "url": url,
    "branch": branch,
    "options": options or {},
  }
  request = ForkSwapRequest.from_raw(payload)
  # ensure unique ID after validation
  request.request_id = uuid.uuid4().hex
  store.put("ForkSwapPayload", request.to_json())
  store.put("ForkSwapAction", request.request_id)
  return request.request_id, request


def clear_pending(params: Optional["Params"] = None) -> None:
  store = get_params(params)
  store.remove("ForkSwapAction")
  store.remove("ForkSwapPayload")
