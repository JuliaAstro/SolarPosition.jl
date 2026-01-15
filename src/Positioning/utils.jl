"""Utility functions to be used across solar positioning algorithms."""

# dt.instant.value = milliseconds since epoch
@inline fractional_hour(dt::DateTime) = (dt.instant.value % 86_400_000) / 3_600_000

# constants
const EMR = 6371.01  # Earth Mean Radius in km
const AU = 149597890.0  # Astronomical Unit in km
