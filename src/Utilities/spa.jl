"""SPA sunrise/sunset calculations."""

using Dates: Dates
using TimeZones: TimeZone

using ..Positioning: _compute_spa_srt_parameters

const SECONDS_PER_DAY = 86400.0

_frac_to_dt(frac) = dt_midnight + Dates.Second(round(Int, frac * SECONDS_PER_DAY))

"""
Helper function to compute sidereal time, right ascension, and declination
for sunrise/sunset calculations at a given datetime.
Returns (ν, α, δ) where ν is apparent sidereal time at Greenwich,
α is geocentric right ascension, δ is geocentric declination (all in degrees).
"""
function _compute_srt_parameters(dt::DateTime, δt::Float64)
    srt = _compute_spa_srt_parameters(dt, δt)
    return (srt.ν, srt.α, srt.δ)
end

function _transit_sunrise_sunset(
    ::Type{R},
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
) where {T<:AbstractFloat,R<:DateTime}
    return _transit_sunrise_sunset_impl(R, obs, dt, alg, nothing)
end

function _transit_sunrise_sunset(
    tz::TimeZone,
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
) where {T<:AbstractFloat}
    return _transit_sunrise_sunset_impl(ZonedDateTime, obs, dt, alg, tz)
end

function _transit_sunrise_sunset_impl(
    ::Type{R},
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
    tz::Union{Nothing,TimeZone},
) where {T<:AbstractFloat,R<:Union{DateTime,ZonedDateTime}}
    """Calculate the sun transit, sunrise, and sunset
    for a given date at an Observer location using the SPA algorithm.

    Based on the NREL SPA algorithm for sunrise/sunset/transit calculation.
    The input DateTime is automatically normalized to midnight UTC (00:00+00:00)
    for the day of interest.
    """
    # Normalize the input datetime to midnight UTC
    # This creates a new DateTime at midnight
    dt_midnight = DateTime(Date(dt))

    δt = if alg.delta_t === nothing
        calculate_deltat(dt_midnight)
    else
        alg.delta_t
    end

    lon = obs.longitude

    # Calculate corresponding terrestrial times
    # δt is in seconds, convert to a time offset
    δt_seconds = Dates.Second(round(Int, δt))

    dt_utday = dt_midnight
    dt_ttday0 = dt_midnight - δt_seconds
    dt_ttdayn1 = dt_ttday0 - Dates.Day(1)
    dt_ttdayp1 = dt_ttday0 + Dates.Day(1)

    # Calculate sidereal time and sun position at different times
    # For UT day: get apparent sidereal time ν
    ν, α_ut, δ_ut = _compute_srt_parameters(dt_utday, δt)

    # For TT days: get right ascension and declination
    ν_tt0, α0, δ0 = _compute_srt_parameters(dt_ttday0, δt)
    ν_ttn1, α_n1, δ_n1 = _compute_srt_parameters(dt_ttdayn1, δt)
    ν_ttp1, α_p1, δ_p1 = _compute_srt_parameters(dt_ttdayp1, δt)

    # Approximate sun transit time (fraction of day)
    m0 = (α0 - lon - ν) / 360.0

    # Hour angle at sunrise/sunset (accounting for atmospheric refraction)
    # -0.8333 degrees is the standard altitude for sunrise/sunset
    h0 = -0.8333
    sin_h0 = sind(h0)
    sin_lat = obs.sin_lat
    cos_lat = obs.cos_lat
    sin_δ0, cos_δ0 = sincosd(δ0)

    cos_H0_arg = (sin_h0 - sin_lat * sin_δ0) / (cos_lat * cos_δ0)

    # check if sun rises/sets on this day
    if abs(cos_H0_arg) > 1.0
        polar_condition =
            cos_H0_arg > 1.0 ? "polar night (sun below horizon)" :
            "polar day (sun above horizon)"
        @warn "Sun does not rise or set on this date at the given location: $polar_condition. Returning midnight UTC for all events." _group =
            :polar_day_night maxlog = 1
        return TransitSunriseSunset{R}(dt_midnight, dt_midnight, dt_midnight, tz)
    end

    H0 = acosd(cos_H0_arg)

    # Initial approximations (fraction of day)
    m = zeros(T, 3)
    m[1] = mod(m0, 1.0)  # transit
    m[2] = mod(m[1] - H0 / 360.0, 1.0)  # sunrise
    m[3] = mod(m[1] + H0 / 360.0, 1.0)  # sunset

    # Track if we need to add/subtract a day
    add_a_day = (m[1] + H0 / 360.0) >= 1.0
    sub_a_day = (m[1] - H0 / 360.0) < 0.0

    # Sidereal time at Greenwich for each event
    ν_s = ν .+ 360.985647 .* m

    # Interpolation parameter (fraction of day in TT)
    δt_days = δt / 86400.0
    n = m .+ δt_days

    # Calculate differences for interpolation
    a = α0 - α_n1
    a = abs(a) > 2.0 ? mod(a, 1.0) : a

    a_p = δ0 - δ_n1
    a_p = abs(a_p) > 2.0 ? mod(a_p, 1.0) : a_p

    b = α_p1 - α0
    b = abs(b) > 2.0 ? mod(b, 1.0) : b

    b_p = δ_p1 - δ0
    b_p = abs(b_p) > 2.0 ? mod(b_p, 1.0) : b_p

    c = b - a
    c_p = b_p - a_p

    # Interpolated right ascension and declination at each event
    α_prime = α0 .+ (n .* (a .+ b .+ c .* n)) ./ 2.0
    δ_prime = δ0 .+ (n .* (a_p .+ b_p .+ c_p .* n)) ./ 2.0

    # Local hour angle for each event
    H_p = mod.(ν_s .+ lon .- α_prime, 360.0)
    # Normalize to [-180, 180]
    H_p[H_p .>= 180.0] .-= 360.0

    # Precompute sin/cos for reuse using sincosd for efficiency
    sincos_δ_prime = sincosd.(δ_prime)
    sin_δ_prime = first.(sincos_δ_prime)
    cos_δ_prime = last.(sincos_δ_prime)

    sincos_H_p = sincosd.(H_p)
    sin_H_p = first.(sincos_H_p)
    cos_H_p = last.(sincos_H_p)

    # Altitude for each event
    h = asind.(sin_lat .* sin_δ_prime .+ cos_lat .* cos_δ_prime .* cos_H_p)

    # Corrections to times (in fraction of day)
    # Transit correction
    ΔT = -H_p[1] / 360.0

    # Sunrise correction
    ΔR = (h[2] + 0.8333) / (360.0 * cos_δ_prime[2] * cos_lat * sin_H_p[2])

    # Sunset correction
    ΔS = (h[3] + 0.8333) / (360.0 * cos_δ_prime[3] * cos_lat * sin_H_p[3])

    # Final times (in fraction of day)
    T_frac = m[1] + ΔT
    R_frac = m[2] + ΔR
    S_frac = m[3] + ΔS

    # Adjust for day boundaries
    if sub_a_day
        R_frac -= 1.0
    end
    if add_a_day
        S_frac += 1.0
    end

    # Convert fractions of day to DateTime
    # Each fraction represents seconds into the day from midnight UTC
    return TransitSunriseSunset{R}(
        _frac_to_dt(T_frac),
        _frac_to_dt(R_frac),
        _frac_to_dt(S_frac),
        tz,
    )
end
