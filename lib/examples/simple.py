"""Simple demo of solarposition.py bindings."""

import datetime as dt

import solarposition as sp

# number of threads. Needs to be set before calling any other functions.
sp.set_num_threads(16)

# algorithm selection
ALG = sp.Algorithm.SPA
REF = sp.RefractionModel.BENNETT
print(f"Using algorithm {ALG.name} and refraction model {REF.name}")

# location and time
LATITUDE = 40.0
LONGITUDE = -105.0
print(f"Location: {LATITUDE} N, {LONGITUDE} W")

# times can be a datetime, a date, a numpy datetime64, or plain Unix seconds. A
# datetime without a tzinfo is read as UTC.
WHEN = dt.datetime(2023, 6, 21, 3, 45, tzinfo=dt.timezone.utc)

pos = sp.solar_position_single(LATITUDE, LONGITUDE, WHEN, refraction=REF, algorithm=ALG)
print(f"Solar position at {WHEN.isoformat()}:")
print(f"  Elevation: {pos.elevation:.2f} degrees")
print(f"  Azimuth: {pos.azimuth:.2f} degrees")
