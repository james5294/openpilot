from cereal import car
from openpilot.selfdrive.car import dbc_dict
from openpilot.selfdrive.car.docs_definitions import CarInfo, Column, TierLazy
from openpilot.selfdrive.car.fw_query_definitions import FwQueryConfig, Request, StdQueries

# Example CAR definition - this will need to be populated with actual CCNC models
class CAR:
  CCNC_MODEL_EXAMPLE = "CCNC MODEL EXAMPLE"

CAR_INFO: dict[str, CarInfo | None] = {
  CAR.CCNC_MODEL_EXAMPLE: None, # To be filled
}

# Example DBC - replace with actual CCNC DBC file reference
DBC = {
  CAR.CCNC_MODEL_EXAMPLE: dbc_dict('somedbc_generated', None), # Replace 'somedbc_generated'
}

# Example FW query - replace or remove if not applicable
FW_QUERY_CONFIG = FwQueryConfig(
  requests=[
    Request(
      [StdQueries.TESTER_PRESENT_REQUEST, StdQueries.ROUTING_REQUEST],
      [StdQueries.TESTER_PRESENT_RESPONSE, StdQueries.ROUTING_RESPONSE],
      whitelist_ecus=[0x700], # Example ECU
      bus=0,
      logging=True
    ),
  ],
  extra_ecus=[],
)
