using ..Refraction: HUGHES, DefaultRefraction

"""
    $(TYPEDEF)

NREL SOLPOS solar position algorithm.

Port of the solar geometry of NREL's `S_solpos` C routine, version `solpos00`. SOLPOS
evaluates the approximate almanac series of [Mic88](@cite), with the solar zenith and
azimuth angles of [Iqb83](@cite). The default refraction model is the Zimmerman correction
SOLPOS applies, so `solar_position` returns an [`ApparentSolPos`](@ref) unless another
model is given.

The Zimmerman correction is the [`HUGHES`](@ref) model. SOLPOS scales it by a pressure
relative to 1013 mbar where `HUGHES` uses 101325 Pa, so the SOLPOS defaults of 1013 mbar
and 15 °C are `HUGHES(101325.0, 15.0)`, and a pressure of `p` mbar corresponds to
`HUGHES(p * 101325 / 1013, temperature)`.

# Accuracy
±0.01° between 1950 and 2050.

# Notes
The port reproduces SOLPOS, including its limitations:
- The Julian date uses the naive leap year count of the original code, so the stated
  accuracy only holds between 1950 and 2050. SOLPOS rejects other years, this port
  evaluates them without warning.
- The zenith angle is capped at 99°, so the elevation never drops below -9°. The azimuth is
  computed from this capped elevation, which makes it invalid once the sun is more than
  9° below the horizon.
- The azimuth is 180° when the sun is at the zenith or the observer at a pole.

The irradiance outputs of SOLPOS, such as the extraterrestrial irradiance, the airmass and
the shadow band correction factor, are not part of this port.

# Literature
NREL's SOLPOS 2.0 [SOLPOS](@cite), based on [Mic88](@cite) and [Iqb83](@cite), with the
refraction correction of [Zim81](@cite).

# Example
The benchmark case of NREL's test program, Atlanta at 9:45:37 local standard time on 22 July
1999, at 1006 mbar and 27 °C:
```julia
obs = Observer(33.65, -84.43)
refraction = HUGHES(1006 * 101325 / 1013, 27.0)
solar_position(obs, DateTime(1999, 7, 22, 14, 45, 37), SOLPOS(), refraction)
```
"""
struct SOLPOS <: SolarAlgorithm end

# Days since J2000.0 noon from the original Julian date, whose leap year count truncates
# towards zero. The J2000 epoch is subtracted in integer arithmetic, so only the small day
# count is converted to T and the large Julian date never is.
@inline function _solpos_days(::Type{T}, dt::DateTime) where {T <: Real}
    Δyear = year(dt) - 1949
    days = Δyear * 365 + div(Δyear, 4) + dayofyear(dt) - 18629
    return T(days) + T(0.5) + fractional_hour(T, dt) / 24
end

function _solar_position(obs::Observer{T}, dt::DateTime, ::SOLPOS) where {T <: Real}
    n = _solpos_days(T, dt)

    # mean longitude, mean anomaly and ecliptic longitude in degrees
    mean_longitude = mod(T(280.46) + T(0.9856474) * n, 360)
    mean_anomaly = mod(T(357.528) + T(0.9856003) * n, 360)
    ecliptic_longitude = mod(
        mean_longitude + T(1.915) * sind(mean_anomaly) +
            T(0.02) * sind(2 * mean_anomaly),
        360,
    )

    # obliquity of the ecliptic in degrees
    obliquity = T(23.439) - T(4.0e-7) * n

    (sin_λ, cos_λ) = sincosd(ecliptic_longitude)
    (sin_ε, cos_ε) = sincosd(obliquity)

    # declination and right ascension in degrees
    declination = asind(unit_clamp(sin_ε * sin_λ))
    right_ascension = mod(atand(cos_ε * sin_λ, cos_λ), 360)

    # Greenwich mean sidereal time in hours, local mean sidereal time in degrees
    gmst = mod(T(6.697375) + T(0.0657098242) * n + fractional_hour(T, dt), 24)
    lmst = mod(15 * gmst + obs.longitude, 360)

    # hour angle in degrees, wrapped once into [-180, 180] like the original code
    hour_angle = lmst - right_ascension
    if hour_angle < -180
        hour_angle += 360
    elseif hour_angle > 180
        hour_angle -= 360
    end

    (sin_δ, cos_δ) = sincosd(declination)

    # zenith angle, capped at 99 degrees
    cos_zenith = unit_clamp(sin_δ * obs.sin_lat + cos_δ * obs.cos_lat * cosd(hour_angle))
    zenith = min(acosd(cos_zenith), T(99))
    elevation = 90 - zenith

    # azimuth from the capped elevation, 180 degrees where it is undefined
    azimuth = T(180)
    (sin_e, cos_e) = sincosd(elevation)
    cos_e_cos_lat = cos_e * obs.cos_lat
    if abs(cos_e_cos_lat) >= T(0.001)
        cos_azimuth = unit_clamp((sin_e * obs.sin_lat - sin_δ) / cos_e_cos_lat)
        azimuth = 180 - acosd(cos_azimuth)
        if hour_angle > 0
            azimuth = 360 - azimuth
        end
    end

    return SolPos{T}(mod(azimuth, 360), elevation, zenith)
end

function _solar_position(obs::Observer{T}, dt, alg::SOLPOS, ::DefaultRefraction) where {T}
    return _solar_position(obs, dt, alg, HUGHES{T}(T(101325), T(15)))
end

# SOLPOS applies its Zimmerman refraction correction by default (which is Hughes)
result_type(::Type{SOLPOS}, ::Type{DefaultRefraction}, ::Type{T}) where {T} =
    ApparentSolPos{T}
