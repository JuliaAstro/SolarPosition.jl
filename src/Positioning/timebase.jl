"""
Type-generic, magnitude-safe time base for the positioning algorithms.

A Julian Date (~2.45e6) cannot be represented usefully below `Float64`, so we never
materialise it at precision `T`. Instead we extract an **exact integer day count** since
the J2000.0 epoch plus the **milliseconds into that day** (also an exact integer), and only
the small intra-day fraction (in `[0, 1)`) is carried in `T`. The integer day part is exact
in any `T` that can hold it (`Float32` is exact up to `2^24` days ≈ 46 000 yr), so precision
is preserved for `BigFloat` while the magnitude stays small enough for `Float32`/`Float16`.

`J2000_EPOCH_MS` is anchored at **noon** (JD 2451545.0 == 2000-01-01T12:00), so the day count
returned here equals `jd - 2451545.0` (days since J2000 noon) with no half-day offset.
"""

# J2000.0 epoch (noon) expressed in the same millisecond scale as `dt.instant.periods.value`.
const J2000_EPOCH_MS = Dates.value(DateTime(2000, 1, 1, 12, 0, 0))

# Exact integer (days since J2000 noon, milliseconds into that day). No floating point.
@inline function _j2000_day_and_ms(dt::DateTime)
    return fldmod(dt.instant.periods.value - J2000_EPOCH_MS, 86_400_000)
end

"""
    julian_day_j2000(T, dt) -> T

Days since the J2000.0 epoch (noon), i.e. `jd - 2451545.0`, at precision `T`. The integer
day part is exact; only the `[0, 1)` intra-day fraction carries `T` rounding.
"""
@inline function julian_day_j2000(::Type{T}, dt::DateTime) where {T <: AbstractFloat}
    (day, msofday) = _j2000_day_and_ms(dt)
    return T(day) + T(msofday) / T(86_400_000)
end

"""
    julian_century(T, dt) -> T

Julian centuries since J2000.0 (magnitude ~0.2 for dates near 2000), at precision `T`.
"""
@inline function julian_century(::Type{T}, dt::DateTime) where {T <: AbstractFloat}
    return julian_day_j2000(T, dt) / T(36525)
end

"""
    fractional_hour(T, dt) -> T

Hours elapsed since civil midnight (range `[0, 24)`), at precision `T`. Type-generic
counterpart of [`fractional_hour(::DateTime)`](@ref).
"""
@inline function fractional_hour(::Type{T}, dt::DateTime) where {T <: AbstractFloat}
    return T(dt.instant.periods.value % 86_400_000) / T(3_600_000)
end
