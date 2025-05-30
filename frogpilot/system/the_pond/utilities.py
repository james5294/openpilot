#!/usr/bin/env python3
import json
import subprocess

from pathlib import Path

from openpilot.common.conversions import Conversions as CV
from openpilot.common.params import Params
from openpilot.system.hardware import HARDWARE
from openpilot.system.loggerd.config import get_available_bytes, get_used_bytes

from openpilot.frogpilot.common.frogpilot_variables import params

def get_available_cameras(segment_path) -> list:
  segment_path = Path(segment_path)

  available_cameras = []
  if (segment_path / "dcamera.hevc").exists():
    available_cameras.append("driver")
  if (segment_path / "qcamera.ts").exists():
    available_cameras.append("forward")
  if (segment_path / "ecamera.hevc").exists():
    available_cameras.append("wide")
  return available_cameras

def get_disk_usage():
  free = get_available_bytes()
  used = get_used_bytes()
  total = used + free

  results = [{
    "mount": HARDWARE.get_device_type(),
    "size": f"{total // (2**30)} GB",
    "used": f"{used // (2**30)} GB",
    "free": f"{free // (2**30)} GB",
    "usedPercentage": f"{(used / total) * 100:.2f}%"
  }]

  return results

def get_drive_stats():
  stats = json.loads(params.get("ApiCache_DriveStats", encoding="utf-8") or "{}")

  is_metric = params.get_bool("IsMetric")
  conversion_factor = 1 if is_metric else CV.KPH_TO_MPH
  unit = "kilometers" if is_metric else "miles"

  def process_stats(timeframe):
    return {
      "distance": stats.get(timeframe).get("distance", 0) * conversion_factor,
      "drives": stats.get(timeframe).get("routes", 0),
      "hours": stats.get(timeframe).get("minutes", 0) / 60,
      "unit": unit
    }

  stats["all"] = process_stats("all")
  stats["week"] = process_stats("week")

  params_tracking = Params("/cache/tracking")

  stats["frogpilot"] = {
    "distance": params_tracking.get_int("FrogPilotKilometers") * conversion_factor,
    "hours": params_tracking.get_int("FrogPilotMinutes") / 60,
    "drives": params_tracking.get_int("FrogPilotDrives"),
    "unit": unit
  }

  return stats

def get_video_duration(input_path) -> float:
  result = subprocess.run([
    "ffprobe", "-v", "error", "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1", str(input_path)
  ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
  return float(result.stdout)

def run_ffmpeg(args) -> None:
  subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + args)

def video_to_gif(input_path, output_path) -> None:
  output_path = Path(output_path)
  if output_path.exists():
    return

  sped_up_path = output_path.with_suffix(".mp4")
  run_ffmpeg(["-i", str(input_path), "-an", "-vf", "setpts=PTS/35", str(sped_up_path)])
  run_ffmpeg(["-i", str(sped_up_path), "-loop", "0", str(output_path)])
  sped_up_path.unlink()

def video_to_png(input_path, output_path) -> None:
  output_path = Path(output_path)
  if output_path.exists():
    return

  run_ffmpeg(["-i", str(input_path), "-ss", "2", "-vframes", "1", str(output_path)])
