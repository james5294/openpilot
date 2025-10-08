from __future__ import annotations

import json
import time
import uuid
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional


SUPPORTED_ACTIONS = {"clone", "switch", "delete", "update", "list", "status"}


class ForkSwapState:
  IDLE = "idle"
  RUNNING = "running"
  SUCCESS = "success"
  ERROR = "error"


def _now() -> float:
  return time.time()


def _ensure_request_id(request_id: Optional[str]) -> str:
  return request_id or uuid.uuid4().hex


@dataclass
class ForkSwapRequest:
  request_id: str
  action: str
  fork: Optional[str] = None
  url: Optional[str] = None
  branch: Optional[str] = None
  options: Dict[str, Any] = field(default_factory=dict)

  @staticmethod
  def from_raw(raw: Any) -> "ForkSwapRequest":
    if raw is None:
      raise ValueError("ForkSwapPayload is empty")
    if isinstance(raw, (bytes, bytearray)):
      raw = raw.decode("utf-8")
    if isinstance(raw, str):
      raw = raw.strip()
      if not raw:
        raise ValueError("ForkSwapPayload is empty")
      try:
        data = json.loads(raw)
      except json.JSONDecodeError as err:
        raise ValueError(f"ForkSwapPayload is not valid JSON: {err}") from err
    elif isinstance(raw, dict):
      data = raw
    else:
      raise TypeError(f"Unsupported payload type: {type(raw)}")

    action = str(data.get("action", "")).strip().lower()
    if not action:
      raise ValueError("ForkSwapPayload.action is required")
    if action not in SUPPORTED_ACTIONS:
      raise ValueError(f"Unsupported action '{action}'")

    request_id = _ensure_request_id(str(data.get("request_id", "")).strip())
    fork = data.get("fork")
    url = data.get("url")
    branch = data.get("branch")
    options = data.get("options") or {}

    if not isinstance(options, dict):
      raise ValueError("ForkSwapPayload.options must be an object")

    return ForkSwapRequest(
      request_id=request_id,
      action=action,
      fork=fork,
      url=url,
      branch=branch,
      options=options,
    )

  def to_json(self) -> str:
    return json.dumps(asdict(self), separators=(",", ":"))


@dataclass
class ForkInfo:
  name: str
  path: str
  branch: Optional[str] = None
  url: Optional[str] = None
  has_update: Optional[bool] = None
  is_current: bool = False

  def to_dict(self) -> Dict[str, Any]:
    return asdict(self)


@dataclass
class ForkSwapStatus:
  state: str = ForkSwapState.IDLE
  action: Optional[str] = None
  request_id: Optional[str] = None
  message: str = ""
  detail: Dict[str, Any] = field(default_factory=dict)
  log_tail: List[str] = field(default_factory=list)
  started_at: Optional[float] = None
  duration: Optional[float] = None
  updated_at: float = field(default_factory=_now)

  def update(
    self,
    *,
    state: Optional[str] = None,
    action: Optional[str] = None,
    request_id: Optional[str] = None,
    message: Optional[str] = None,
    detail: Optional[Dict[str, Any]] = None,
    log_tail: Optional[List[str]] = None,
    started_at: Optional[float] = None,
    duration: Optional[float] = None,
  ) -> None:
    if state is not None:
      self.state = state
      if state == ForkSwapState.RUNNING and self.started_at is None:
        self.started_at = _now()
    if action is not None:
      self.action = action
    if request_id is not None:
      self.request_id = request_id
    if message is not None:
      self.message = message
    if detail is not None:
      self.detail = detail
    if log_tail is not None:
      self.log_tail = log_tail
    if started_at is not None:
      self.started_at = started_at
    if duration is not None:
      self.duration = duration
    self.updated_at = _now()

  def to_json(self) -> str:
    data = asdict(self)
    data["updated_at"] = self.updated_at
    return json.dumps(data, separators=(",", ":"))

  @staticmethod
  def from_raw(raw: Any) -> "ForkSwapStatus":
    if raw is None:
      return ForkSwapStatus()
    if isinstance(raw, (bytes, bytearray)):
      raw = raw.decode("utf-8")
    if isinstance(raw, str):
      raw = raw.strip()
      if not raw:
        return ForkSwapStatus()
      try:
        data = json.loads(raw)
      except json.JSONDecodeError:
        return ForkSwapStatus(message="Failed to decode existing status payload")
    elif isinstance(raw, dict):
      data = raw
    else:
      raise TypeError(f"Unsupported status payload type: {type(raw)}")

    status = ForkSwapStatus()
    status.state = data.get("state", ForkSwapState.IDLE)
    status.action = data.get("action")
    status.request_id = data.get("request_id")
    status.message = data.get("message", "")
    status.detail = data.get("detail") or {}
    status.log_tail = data.get("log_tail") or []
    status.updated_at = float(data.get("updated_at", _now()))
    status.started_at = data.get("started_at")
    status.duration = data.get("duration")
    return status
