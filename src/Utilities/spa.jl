"""SPA sunrise/sunset calculations."""

using Dates: Dates

# Import necessary functions from Positioning.spa module
using ..Positioning: datetime2julian, julian_ephemeris_day, julian_ephemeris_century
using ..Positioning: julian_ephemeris_millennium, heliocentric_longitude
using ..Positioning: heliocentric_latitude, heliocentric_radius_vector
using ..Positioning: nutation_longitude_obliquity, mean_ecliptic_obliquity
using ..Positioning: true_ecliptic_obliquity, aberration_correction
using ..Positioning: apparent_sun_longitude, mean_sidereal_time, apparent_sidereal_time
using ..Positioning: geocentric_sun_right_ascension, geocentric_sun_declination

"""
Helper function to compute sidereal time, right ascension, and declination
for sunrise/sunset calculations at a given datetime.
Returns (ν, α, δ) where ν is apparent sidereal time at Greenwich,
α is geocentric right ascension, δ is geocentric declination (all in degrees).
"""
function _compute_srt_parameters(dt::DateTime, δt::Float64)
    jd = datetime2julian(dt)
    jde = julian_ephemeris_day(jd, δt)
    jc = (jd - 2451545.0) / 36525.0
    jce = julian_ephemeris_century(jde)
    jme = julian_ephemeris_millennium(jce)

    # heliocentric position of Earth
    L = heliocentric_longitude(jme)
    B = heliocentric_latitude(jme)
    R = heliocentric_radius_vector(jme)

    # geocentric position (sun as seen from Earth center)
    θ = mod(L + 180.0, 360.0)  # geocentric longitude
    β = -B  # geocentric latitude

    # nutation and obliquity
    δψ, δε = nutation_longitude_obliquity(jce)
    ε0 = mean_ecliptic_obliquity(jme)
    ε = true_ecliptic_obliquity(ε0, δε)

    # aberration correction
    δτ = aberration_correction(R)

    # apparent sun longitude
    λ = apparent_sun_longitude(θ, δψ, δτ)

    # sidereal time at Greenwich
    ν0 = mean_sidereal_time(jd, jc)
    ν = apparent_sidereal_time(ν0, δψ, ε)

    # geocentric sun position
    α = geocentric_sun_right_ascension(λ, ε, β)
    δ = geocentric_sun_declination(λ, ε, β)

    return (ν, α, δ)
end

# function transit_sunrise_sunset(dates, lat, lon, delta_t, numthreads):
function _transit_sunrise_sunset(
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
) where {T<:AbstractFloat}
    """Calculate the sun transit, sunrise, and sunset
    for a given date at an Observer location using the SPA algorithm.

    Based on the NREL SPA algorithm for sunrise/sunset/transit calculation.
    The input DateTime should be at midnight UTC (00:00+00:00) on the day of interest.
    """
    δt = if alg.delta_t === nothing
        calculate_deltat(dt)
    else
        alg.delta_t
    end

    lat = obs.latitude
    lon = obs.longitude

    # Calculate corresponding terrestrial times
    # δt is in seconds, convert to a time offset
    δt_seconds = Dates.Second(round(Int, δt))

    dt_utday = dt
    dt_ttday0 = dt - δt_seconds
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
    sin_lat = sind(lat)
    cos_lat = cosd(lat)
    sin_δ0 = sind(δ0)
    cos_δ0 = cosd(δ0)

    cos_H0_arg = (sin_h0 - sin_lat * sin_δ0) / (cos_lat * cos_δ0)

    # Check if sun rises/sets on this day
    if abs(cos_H0_arg) > 1.0
        # Sun doesn't rise or set - return NaN times
        # TODO: Handle polar day/night cases properly
        zdt = ZonedDateTime(dt, tz"UTC")
        return TransitSunriseSunset(zdt, zdt, zdt)
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
    α_prime = α0 .+ (n .* (a + b .+ c .* n)) ./ 2.0
    δ_prime = δ0 .+ (n .* (a_p + b_p .+ c_p .* n)) ./ 2.0

    # Local hour angle for each event
    H_p = mod.(ν_s .+ lon .- α_prime, 360.0)
    # Normalize to [-180, 180]
    H_p[H_p .>= 180.0] .-= 360.0

    # Altitude for each event
    h = asind.(sin_lat .* sind.(δ_prime) .+ cos_lat .* cosd.(δ_prime) .* cosd.(H_p))

    # Corrections to times (in fraction of day)
    # Transit correction
    ΔT = -H_p[1] / 360.0

    # Sunrise correction
    ΔR = (h[2] + 0.8333) / (360.0 * cosd(δ_prime[2]) * cos_lat * sind(H_p[2]))

    # Sunset correction
    ΔS = (h[3] + 0.8333) / (360.0 * cosd(δ_prime[3]) * cos_lat * sind(H_p[3]))

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
    transit_dt = dt + Dates.Second(round(Int, T_frac * 86400.0))
    sunrise_dt = dt + Dates.Second(round(Int, R_frac * 86400.0))
    sunset_dt = dt + Dates.Second(round(Int, S_frac * 86400.0))

    # Convert to ZonedDateTime with UTC
    transit_zdt = ZonedDateTime(transit_dt, tz"UTC")
    sunrise_zdt = ZonedDateTime(sunrise_dt, tz"UTC")
    sunset_zdt = ZonedDateTime(sunset_dt, tz"UTC")

    return TransitSunriseSunset(transit_zdt, sunrise_zdt, sunset_zdt)
end
