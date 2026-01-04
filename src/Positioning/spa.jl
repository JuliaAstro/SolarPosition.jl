"""
    $(TYPEDEF)

SPA (Solar Position Algorithm) from NREL. This is the most accurate algorithm for
solar position calculation, suitable for high-precision applications.

The algorithm implements the complete NREL Solar Position Algorithm as described in
Reda and Andreas (2004, 2007). It accounts for:
- Heliocentric position of Earth
- Nutation and aberration
- Geocentric and topocentric corrections
- Atmospheric refraction
- Parallax effects

# Accuracy
Claimed accuracy: ±0.0003° (±1 arcsecond) for years -2000 to 6000.

# Literature
This algorithm is based on [RA04](@cite) with corrections from the 2007 corrigendum.

# Fields
$(TYPEDFIELDS)
"""
struct SPA <: SolarAlgorithm
    "Difference between terrestrial time and UT1 [seconds]. If `nothing`, uses automatic calculation."
    delta_t::Union{Float64,Nothing}
    "Annual average air pressure [Pa]"
    pressure::Float64
    "Annual average air temperature [°C]"
    temperature::Float64
    "Approximate atmospheric refraction at sunrise/sunset [degrees]"
    atmos_refract::Float64

    function SPA(
        delta_t::Union{Float64,Nothing},
        pressure::Float64,
        temperature::Float64,
        atmos_refract::Float64,
    )
        new(delta_t, pressure, temperature, atmos_refract)
    end
end

# keyword argument constructor with default values
function SPA(;
    delta_t::Union{Float64,Nothing} = 67.0,
    pressure::Float64 = 101325.0,
    temperature::Float64 = 12.0,
    atmos_refract::Float64 = 0.5667,
)
    return SPA(delta_t, pressure, temperature, atmos_refract)
end


"""
    $(TYPEDEF)

!!! note "Internal Implementation"
    This is an internal optimization type not exported to users. Use `Observer` instead.

Optimized observer type for SPA algorithm with pre-computed location-dependent values.
Will cache terms that depend only on observer location to speed up calculations for
multiple times at the same location.

# Internal Fields
$(TYPEDFIELDS)
"""
struct SPAObserver{T<:AbstractFloat}
    "Geodetic latitude (+N)"
    latitude::T
    "Longitude (+E)"
    longitude::T
    "Altitude above mean sea level (meters)"
    altitude::T
    "Latitude in radians"
    latitude_rad::T
    "Longitude in radians"
    longitude_rad::T
    "sin(latitude)"
    sin_lat::T
    "cos(latitude)"
    cos_lat::T
    "Cached u term for parallax (reduced latitude)"
    u::T
    "Cached x term for parallax correction"
    x::T
    "Cached y term for parallax correction"
    y::T

    function SPAObserver{T}(lat::T, lon::T, alt::T = zero(T)) where {T<:AbstractFloat}
        lat_rad = deg2rad(lat)
        lon_rad = deg2rad(lon)
        (sin_lat, cos_lat) = sincos(lat_rad)

        # pre-compute parallax terms using helper functions
        u = u_term(lat_rad)
        (sin_u, cos_u) = sincos(u)
        x = x_term(sin_u, cos_u, alt, cos_lat)
        y = y_term(sin_u, cos_u, alt, sin_lat)

        new{T}(lat, lon, alt, lat_rad, lon_rad, sin_lat, cos_lat, u, x, y)
    end
end

SPAObserver(lat::T, lon::T; altitude = 0.0) where {T<:AbstractFloat} =
    SPAObserver{T}(lat, lon, altitude)
SPAObserver(lat::T, lon::T, alt::T) where {T<:AbstractFloat} = SPAObserver{T}(lat, lon, alt)


# heliocentric longitude coefficients (L0-L5)
include("spa_coefficients.jl")


# helper functions for SPA calculations
@inline function julian_ephemeris_day(jd, δt)
    return jd + δt / 86400.0
end

@inline function julian_ephemeris_century(jde)
    return (jde - 2451545.0) / 36525.0
end

@inline function julian_ephemeris_millennium(jce)
    return jce / 10.0
end

# calculate sum of A * cos(B + C*x) for coefficient array
@inline function sum_periodic_terms(coeffs::Matrix{T}, x) where {T<:AbstractFloat}
    s = zero(T)
    for i in axes(coeffs, 1)
        s += coeffs[i, 1] * cos(coeffs[i, 2] + coeffs[i, 3] * x)
    end
    return s
end

function heliocentric_longitude(jme)
    l0 = sum_periodic_terms(L0, jme)
    l1 = sum_periodic_terms(L1, jme)
    l2 = sum_periodic_terms(L2, jme)
    l3 = sum_periodic_terms(L3, jme)
    l4 = sum_periodic_terms(L4, jme)
    l5 = sum_periodic_terms(L5, jme)

    l_rad = evalpoly(jme, (l0, l1, l2, l3, l4, l5)) / 1e8
    return mod(rad2deg(l_rad), 360.0)
end

function heliocentric_latitude(jme)
    b0 = sum_periodic_terms(B0, jme)
    b1 = sum_periodic_terms(B1, jme)

    b_rad = (b0 + b1 * jme) / 1e8
    return rad2deg(b_rad)
end

function heliocentric_radius_vector(jme)
    r0 = sum_periodic_terms(R0, jme)
    r1 = sum_periodic_terms(R1, jme)
    r2 = sum_periodic_terms(R2, jme)
    r3 = sum_periodic_terms(R3, jme)
    r4 = sum_periodic_terms(R4, jme)

    return evalpoly(jme, (r0, r1, r2, r3, r4)) / 1e8
end

# nutation calculations
function mean_elongation(jce)
    return evalpoly(jce, (297.85036, 445267.111480, -0.0019142, 1.0 / 189474.0))
end

function mean_anomaly_sun(jce)
    return evalpoly(jce, (357.52772, 35999.050340, -0.0001603, -1.0 / 300000.0))
end

function mean_anomaly_moon(jce)
    return evalpoly(jce, (134.96298, 477198.867398, 0.0086972, 1.0 / 56250.0))
end

function moon_argument_latitude(jce)
    return evalpoly(jce, (93.27191, 483202.017538, -0.0036825, 1.0 / 327270.0))
end

function moon_ascending_longitude(jce)
    return evalpoly(jce, (125.04452, -1934.136261, 0.0020708, 1.0 / 450000.0))
end

function nutation_longitude_obliquity(jce)
    x0 = mean_elongation(jce)
    x1 = mean_anomaly_sun(jce)
    x2 = mean_anomaly_moon(jce)
    x3 = moon_argument_latitude(jce)
    x4 = moon_ascending_longitude(jce)

    δψ_sum = 0.0
    δε_sum = 0.0

    for i in axes(NUTATION_YTERM, 1)
        arg_deg =
            NUTATION_YTERM[i, 1] * x0 +
            NUTATION_YTERM[i, 2] * x1 +
            NUTATION_YTERM[i, 3] * x2 +
            NUTATION_YTERM[i, 4] * x3 +
            NUTATION_YTERM[i, 5] * x4

        arg_rad = deg2rad(arg_deg)
        (sin_arg, cos_arg) = sincos(arg_rad)
        δψ_sum += (NUTATION_ABCD[i, 1] + NUTATION_ABCD[i, 2] * jce) * sin_arg
        δε_sum += (NUTATION_ABCD[i, 3] + NUTATION_ABCD[i, 4] * jce) * cos_arg
    end

    δψ = δψ_sum / 36000000.0  # convert to degrees
    δε = δε_sum / 36000000.0  # convert to degrees

    return δψ, δε
end

function mean_ecliptic_obliquity(jme)
    u = jme / 10.0
    ε0 =
        let p = (
                84381.448,
                -4680.93,
                -1.55,
                1999.25,
                -51.38,
                -249.67,
                -39.05,
                7.12,
                27.87,
                5.79,
                2.45,
            )
            evalpoly(u, p)
        end
    return ε0  # arcseconds
end

@inline function true_ecliptic_obliquity(ε0, δε)
    return ε0 / 3600.0 + δε  # convert arcseconds to degrees
end

@inline function aberration_correction(R)
    return -20.4898 / (3600.0 * R)  # degrees
end

@inline function apparent_sun_longitude(θ, δψ, δτ)
    return θ + δψ + δτ
end

function mean_sidereal_time(jd, jc)
    ν0 =
        280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * jc^2 -
        jc^3 / 38710000.0
    return mod(ν0, 360.0)
end

function apparent_sidereal_time(ν0, δψ, ε)
    return ν0 + δψ * cosd(ε)
end

function geocentric_sun_right_ascension(λ, ε, β)
    (sin_λ, cos_λ) = sincos(deg2rad(λ))
    (sin_ε, cos_ε) = sincos(deg2rad(ε))
    (sin_β, cos_β) = sincos(deg2rad(β))

    num = sin_λ * cos_ε - (sin_β / cos_β) * sin_ε
    α = rad2deg(atan(num, cos_λ))
    return mod(α, 360.0)
end

function geocentric_sun_declination(λ, ε, β)
    (sin_β, cos_β) = sincos(deg2rad(β))
    (sin_ε, cos_ε) = sincos(deg2rad(ε))
    sin_λ = sin(deg2rad(λ))

    δ = rad2deg(asin(sin_β * cos_ε + cos_β * sin_ε * sin_λ))
    return δ
end

@inline function local_hour_angle(ν, lon, α)
    H = ν + lon - α
    return mod(H, 360.0)
end

@inline function equatorial_horizontal_parallax_rad(R)
    return deg2rad(8.794 / (3600.0 * R))  # radians
end

# observer-dependent terms (used for parallax correction caching in SPAObserver)
@inline function u_term(lat_rad)
    return atan(0.99664719 * tan(lat_rad))
end

@inline function x_term(sin_u, cos_u, alt, cos_lat)
    return cos_u + alt / 6378140.0 * cos_lat
end

@inline function y_term(sin_u, cos_u, alt, sin_lat)
    return 0.99664719 * sin_u + alt / 6378140.0 * sin_lat
end

function parallax_sun_right_ascension_rad(x, sin_ξ, sin_H, cos_H, cos_δ)
    num = -x * sin_ξ * sin_H
    denom = cos_δ - x * sin_ξ * cos_H
    Δα_rad = atan(num, denom)
    return Δα_rad
end

function topocentric_sun_declination_rad(sin_δ, cos_δ, x, y, sin_ξ, Δα_rad, cos_H)
    cos_Δα = cos(Δα_rad)

    num = (sin_δ - y * sin_ξ) * cos_Δα
    denom = cos_δ - x * sin_ξ * cos_H
    δ′_rad = atan(num, denom)
    return δ′_rad
end

function topocentric_elevation_angle_without_atmosphere(sin_lat, cos_lat, δ′_rad, H′_rad)
    (sin_δ′, cos_δ′) = sincos(δ′_rad)
    cos_H′ = cos(H′_rad)

    e0 = rad2deg(asin(sin_lat * sin_δ′ + cos_lat * cos_δ′ * cos_H′))
    return e0
end

function atmospheric_refraction_correction(pressure, temp, e0, atmos_refract)
    # only apply correction when sun is above horizon accounting for refraction
    if e0 < -(0.26667 + atmos_refract)
        return 0.0
    end

    # convert pressure from Pa to hPa/mbar
    pressure_hPa = pressure / 100.0

    Δe =
        (pressure_hPa / 1010.0) * (283.0 / (273.0 + temp)) * 1.02 /
        (60.0 * tand(e0 + 10.3 / (e0 + 5.11)))
    return Δe  # already in degrees
end

function topocentric_azimuth_angle(H′_rad, δ′_rad, sin_lat, cos_lat)
    (sin_H′, cos_H′) = sincos(H′_rad)
    tan_δ′ = tan(δ′_rad)

    num = sin_H′
    denom = cos_H′ * sin_lat - tan_δ′ * cos_lat
    γ = rad2deg(atan(num, denom))

    # convert from astronomers azimuth (0=south) to standard (0=north)
    φ = mod(γ + 180.0, 360.0)
    return φ
end

"""
Helper function to compute sidereal time, right ascension, declination, and related
parameters for SPA calculations at a given datetime.

Returns a named tuple with:
- `ν`: apparent sidereal time at Greenwich (degrees)
- `α`: geocentric right ascension (degrees)
- `δ`: geocentric declination (degrees)
- `R`: heliocentric radius vector (AU)
- `ε`: true ecliptic obliquity (degrees)
- `δψ`: nutation in longitude (degrees)
- `jme`: Julian Ephemeris Millennium
"""
function _compute_spa_srt_parameters(dt::DateTime, δt::Float64)
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

    return (; ν, α, δ, R, ε, δψ, jme)
end

function _solar_position(
    obs::SPAObserver{T},
    dt::DateTime,
    alg::SPA,
) where {T<:AbstractFloat}
    δt::Float64 = if alg.delta_t === nothing
        calculate_deltat(dt)
    else
        alg.delta_t
    end

    # Compute sidereal time, right ascension, declination, and related parameters
    ν, α, δ, R, ε, δψ, jme = _compute_spa_srt_parameters(dt, δt)

    # observer local hour angle
    H = local_hour_angle(ν, obs.longitude, α)
    H_rad = deg2rad(H)

    # parallax correction - use pre-computed values from SPAObserver
    ξ_rad = equatorial_horizontal_parallax_rad(R)
    sin_ξ = sin(ξ_rad)

    # topocentric sun position (work in radians internally)
    δ_rad = deg2rad(δ)
    (sin_δ, cos_δ) = sincos(δ_rad)
    (sin_H, cos_H) = sincos(H_rad)
    Δα_rad = parallax_sun_right_ascension_rad(obs.x, sin_ξ, sin_H, cos_H, cos_δ)
    δ′_rad =
        topocentric_sun_declination_rad(sin_δ, cos_δ, obs.x, obs.y, sin_ξ, Δα_rad, cos_H)
    H′_rad = H_rad - Δα_rad  # topocentric local hour angle (radians)

    # topocentric elevation (without atmosphere)
    e0 = topocentric_elevation_angle_without_atmosphere(
        obs.sin_lat,
        obs.cos_lat,
        δ′_rad,
        H′_rad,
    )

    # zenith without refraction
    θz0 = 90.0 - e0

    # azimuth (same for both apparent and non-apparent)
    az = topocentric_azimuth_angle(H′_rad, δ′_rad, obs.sin_lat, obs.cos_lat)

    return SolPos{T}(az, e0, θz0)
end

# SPA with DefaultRefraction applies SPA's built-in atmospheric refraction model
function _solar_position(
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
    ::Refraction.DefaultRefraction,
) where {T<:AbstractFloat}
    spa_obs = SPAObserver{T}(obs.latitude, obs.longitude, obs.altitude)

    # Get base position without refraction
    base_pos = _solar_position(spa_obs, dt, alg)

    # Apply SPA's atmospheric refraction correction
    Δe = atmospheric_refraction_correction(
        alg.pressure,
        alg.temperature,
        base_pos.elevation,
        alg.atmos_refract,
    )

    # Calculate apparent positions
    e = base_pos.elevation + Δe  # apparent elevation
    θz = 90.0 - e  # apparent zenith

    return ApparentSolPos{T}(base_pos.azimuth, base_pos.elevation, base_pos.zenith, e, θz)
end

# SPA with NoRefraction returns SolPos (no refraction applied)
function _solar_position(
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
    ::Refraction.NoRefraction,
) where {T<:AbstractFloat}
    spa_obs = SPAObserver{T}(obs.latitude, obs.longitude, obs.altitude)
    return _solar_position(spa_obs, dt, alg)
end

# SPA with external refraction algorithm: apply the external refraction to base position
function _solar_position(
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
    refraction::Refraction.RefractionAlgorithm,
) where {T<:AbstractFloat}
    spa_obs = SPAObserver{T}(obs.latitude, obs.longitude, obs.altitude)

    # Get base position without refraction
    base_pos = _solar_position(spa_obs, dt, alg)

    # Apply external refraction correction
    refraction_correction_deg = Refraction.refraction(refraction, base_pos.elevation)
    apparent_elevation_deg = base_pos.elevation + refraction_correction_deg
    apparent_zenith_deg = 90.0 - apparent_elevation_deg

    return ApparentSolPos{T}(
        base_pos.azimuth,
        base_pos.elevation,
        base_pos.zenith,
        apparent_elevation_deg,
        apparent_zenith_deg,
    )
end

# SPA returns SolPos with NoRefraction, ApparentSolPos with any refraction
result_type(::Type{SPA}, ::Type{NoRefraction}, ::Type{T}) where {T} = SolPos{T}
result_type(::Type{SPA}, ::Type{<:Refraction.RefractionAlgorithm}, ::Type{T}) where {T} =
    ApparentSolPos{T}
