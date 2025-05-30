#!/usr/bin/env python3
from datetime import datetime
from flask import Flask, Response, render_template, request, send_from_directory

import json
import os
import re
import secrets

from openpilot.system.hardware import PC
from openpilot.system.hardware.hw import Paths

from openpilot.frogpilot.common.frogpilot_variables import ERROR_LOGS_PATH, params
from openpilot.frogpilot.system.the_pond import helpers
from openpilot.frogpilot.system.the_pond import utilities

FOOTAGE_PATHS = [Paths.log_root(konik=True), Paths.log_root(raw=True)]

def setup(app):
  @app.errorhandler(404)
  def not_found(_):
    return render_template("index.html")

  @app.route("/")
  def index():
    return render_template("index.html")

  @app.route("/api/navigation", methods=["DELETE"])
  def clear_navigation():
    params.remove("NavDestination")
    return {"message": "Destination cleared"}

  @app.route("/api/navigation", methods=["POST"])
  def set_navigation():
    params.put("NavDestination", json.dumps(request.json))
    return {"message": "Destination set"}

  @app.route("/api/routes")
  def list_routes():
    routes = []
    for footage_path in FOOTAGE_PATHS:
      for name in helpers.get_routes_names(footage_path):
        path = f"{footage_path}{name}--0"

        gif = f"{path}/preview.gif"
        png = f"{path}/preview.png"
        qcamera = f"{path}/qcamera.ts"

        utilities.video_to_gif(qcamera, gif)
        utilities.video_to_png(qcamera, png)

        routes.append({
          "name": name,
          "gif": f"/thumbnails/{name}--0/preview.gif",
          "png": f"/thumbnails/{name}--0/preview.png"
        })
    return routes, 200

  @app.route("/api/error-logs/<filename>")
  def get_error_log(filename):
    with open(f"{ERROR_LOGS_PATH}{filename}") as file:
      return file.read(), 200

  @app.route("/api/error-logs")
  def get_error_logs():
    if request.accept_mimetypes['text/html']:
      return render_template("v2/error-logs.jinja", active="error_logs")

    if request.accept_mimetypes['application/json']:
      logs = helpers.list_file(ERROR_LOGS_PATH)
      return logs, 200

  @app.route("/api/routes/<name>")
  def get_route(name):
    available_cameras = []
    segment_urls = []

    total_duration = 0

    for footage_path in FOOTAGE_PATHS:
      base_path = f"{footage_path}{name}--0"
      if os.path.exists(base_path):
        segments = helpers.get_segments_in_route(name, footage_path)
        segment_urls = [f"/video/{segment}" for segment in segments]

        if segment_urls:
          last_segment_path = f"{footage_path}{name}--{len(segment_urls)-1}/qcamera.ts"
          last_duration = utilities.get_video_duration(last_segment_path)
          total_duration = round(last_duration + ((len(segment_urls) - 1) * 60))

        available_cameras = utilities.get_available_cameras(base_path)
        break

    if not segment_urls:
      return {"error": "Route not found"}, 404

    route_date = datetime.strptime(name, '%Y-%m-%d--%H-%M-%S')

    return {
      "name": name,
      "segment_urls": segment_urls,
      "total_duration": total_duration,
      "date": route_date,
      "available_cameras": available_cameras
    }, 200

  @app.route("/api/stats")
  def get_stats():
    disk = utilities.get_disk_usage()
    drives = utilities.get_drive_stats()

    return {"driveStats": drives, "diskUsage": disk}

  @app.route("/thumbnails/<path:file_path>", methods=["GET"])
  def get_thumbnail(file_path):
    for footage_path in FOOTAGE_PATHS:
      try:
        return send_from_directory(footage_path, file_path, as_attachment=True)
      except FileNotFoundError:
        continue
    return {"error": "Thumbnail not found"}, 404

  @app.route("/video/<path>")
  def get_video(path):
    camera = request.args.get("camera")

    video_file = {
      "driver": "dcamera.hevc",
      "wide": "ecamera.hevc"
    }.get(camera, "qcamera.ts")

    for footage_path in FOOTAGE_PATHS:
      filepath = f"{footage_path}{path}/{video_file}"
      if os.path.exists(filepath):
        process = helpers.ffmpeg_mp4_wrap_process_builder(filepath)
        return Response(process.stdout.read(), status=200, mimetype="video/mp4")

    return {"error": "Video not found"}, 404

  @app.route("/playground")
  def playground():
    return render_template("playground.html")

def main():
  app = Flask(__name__, static_folder="assets", static_url_path="/assets")
  setup(app)

  if PC or __package__ == "the_pond":
    print("\"The Pond\" is not running on a comma device, enabling debug mode")
    debug = True
    port = 8084
  else:
    debug = False
    port = 8083

  app.secret_key = secrets.token_hex(32)
  app.run(host="0.0.0.0", port=port, debug=debug)

if __name__ == "__main__":
  main()
