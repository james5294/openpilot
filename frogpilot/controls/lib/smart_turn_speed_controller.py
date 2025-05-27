#!/usr/bin/env python3
import bisect
import json
import numpy as np

from openpilot.common.conversions import Conversions as CV
from openpilot.common.realtime import DT_MDL
from openpilot.selfdrive.controls.lib.drive_helpers import V_CRUISE_MAX

from openpilot.frogpilot.common.frogpilot_utilities import calculate_predicted_lateral_acceleration
from openpilot.frogpilot.common.frogpilot_variables import CRUISING_SPEED, PLANNER_TIME, params

LATERAL_ACCELERATION_MAX = 10.0
LATERAL_ACCELERATION_MIN = 1.0
ROUNDING_PRECISION = 2
TARGET_LATERAL_ACCELERATION = 2.0
V_CRUISE_MAX_CONVERTED = V_CRUISE_MAX * CV.KPH_TO_MS

class SmartTurnSpeedController:
  def __init__(self, FrogPilotVCruise):
    self.frogpilot_planner = FrogPilotVCruise.frogpilot_planner

    self.controlling_curve = False
    self.training_active = False

    self.manual_long_timer = 0
    self.target = 0

    self.lateral_acceleration_data = [tuple(item) for item in json.loads(params.get("UserLateralAccelerationData") or "[]")]
    self.lateral_acceleration_data.sort()

  def log_lateral_acceleration_data(self, v_ego, sm):
    predicted_lateral_acceleration = round(abs(calculate_predicted_lateral_acceleration(sm["modelV2"])), ROUNDING_PRECISION)
    print(f"Predicted lateral acceleration: {predicted_lateral_acceleration}g")

    if not (LATERAL_ACCELERATION_MIN <= predicted_lateral_acceleration <= LATERAL_ACCELERATION_MAX):
      print("Predicted lateral acceleration out of bounds, skipping")
      return

    speed = round(v_ego, ROUNDING_PRECISION)
    print(f"Rounded speed: {speed} m/s")

    index = bisect.bisect_left(self.lateral_acceleration_data, (predicted_lateral_acceleration, -float('inf'), -float('inf')))
    if index < len(self.lateral_acceleration_data) and self.lateral_acceleration_data[index][0] == predicted_lateral_acceleration:
      _, current_average, current_count = self.lateral_acceleration_data[index]

      new_count = current_count + 1
      new_average = round((current_average * current_count + speed) / new_count)

      self.lateral_acceleration_data[index] = (predicted_lateral_acceleration, new_average, new_count)
      print(f"Updated existing entry: {predicted_lateral_acceleration}g → avg {new_average} m/s over {new_count} samples")
    else:
      bisect.insort(self.lateral_acceleration_data, (predicted_lateral_acceleration, speed, 1))
      print(f"Inserted new entry: {predicted_lateral_acceleration}g → {speed} m/s")

  def log_data(self, v_ego, sm):
    print("Checking whether to log data")
    print(f"v_ego: {v_ego}, longActive: {sm['carControl'].longActive}, tracking_lead: {self.frogpilot_planner.tracking_lead}, blinkers: {sm['carState'].leftBlinker or sm['carState'].rightBlinker}, timer: {self.manual_long_timer}")

    if not sm["carControl"].longActive and V_CRUISE_MAX_CONVERTED >= v_ego > CRUISING_SPEED and not self.frogpilot_planner.tracking_lead and not (sm["carState"].leftBlinker or sm["carState"].rightBlinker):
      print("Passed gating conditions for logging")
      self.training_active = self.manual_long_timer >= PLANNER_TIME
      self.training_active &= self.frogpilot_planner.road_curvature_detected
      self.training_active &= not self.frogpilot_planner.cem.stop_light_detected

      if self.training_active:
        print("Conditions met for lateral logging")
        self.log_lateral_acceleration_data(v_ego, sm)
      else:
        print("Waiting for planner time or other detection conditions")

      self.manual_long_timer += DT_MDL
      print(f"Incremented timer: {self.manual_long_timer}")

    elif self.manual_long_timer >= PLANNER_TIME:
      params.put_nonblocking("UserLateralAccelerationData", json.dumps([list(data) for data in self.lateral_acceleration_data]))

      self.training_active = False

      self.manual_long_timer = 0
    else:
      print("Resetting timer")
      self.training_active = False

      self.manual_long_timer = 0

  def update_target(self, v_cruise, v_ego, sm):
    print("Updating target speed")
    if not self.lateral_acceleration_data:
      vtsc_speed = (TARGET_LATERAL_ACCELERATION / abs(self.frogpilot_planner.road_curvature))**0.5
      self.target = max(CRUISING_SPEED, vtsc_speed)
      print(f"No data available, calculated target: {self.target}")
      return

    predicted_lateral_acceleration = round(abs(calculate_predicted_lateral_acceleration(sm["modelV2"])), ROUNDING_PRECISION)
    print(f"Predicted lateral acceleration: {predicted_lateral_acceleration}")

    lateral_accelerations, speeds = zip(*[(a, s) for a, s, _ in self.lateral_acceleration_data])

    if predicted_lateral_acceleration < lateral_accelerations[0] or predicted_lateral_acceleration > lateral_accelerations[-1]:
      vtsc_speed = (TARGET_LATERAL_ACCELERATION / abs(self.frogpilot_planner.road_curvature))**0.5
      self.target = max(CRUISING_SPEED, vtsc_speed)
      print(f"Predicted value out of range, fallback target: {self.target}")
      return

    self.target = float(np.interp(predicted_lateral_acceleration, lateral_accelerations, speeds))
    print(f"Interpolated target speed: {self.target}")
