"""Utility functions to be used across solar positioning algorithms."""

# degree helpers
deg2rad(x::Real) = float(x) * (π / 180)
rad2deg(x::Real) = float(x) * (180 / π)

# fractional hour helper
fractional_hour(dt::DateTime) =
    (hour(dt) + minute(dt) / 60.0 + second(dt) / 3600.0 + millisecond(dt) / 3.6e6)

# constants
const EMR = 6371.01  # Earth Mean Radius in km
const AU = 149597890.0  # Astronomical Unit in km
