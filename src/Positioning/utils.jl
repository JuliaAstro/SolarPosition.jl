"""Utility functions to be used across solar positioning algorithms."""

# dt.instant.periods.value = milliseconds since epoch
@inline fractional_hour(dt::DateTime) = (dt.instant.periods.value % 86_400_000) / 3_600_000

# Clamp a direction cosine / ratio into the valid asin/acos domain. Guards against low-precision
# rounding (Float16/Float32) pushing it just past ±1, which would throw a DomainError.
@inline unit_clamp(x) = clamp(x, -one(x), one(x))

# constants
const EMR = 6371.01  # Earth Mean Radius in km
const AU = 149597890.0  # Astronomical Unit in km
