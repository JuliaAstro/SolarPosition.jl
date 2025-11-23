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

# default constructor with typical values
SPA() = SPA(67.0, 101325.0, 12.0, 0.5667)


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
        # apply pole corrections to avoid numerical issues
        if lat == 90.0
            lat -= 1e-6
            @warn "Latitude is 90°. Adjusted to $(lat)° to avoid singularities." maxlog = 1
        elseif lat == -90.0
            lat += 1e-6
            @warn "Latitude is -90°. Adjusted to $(lat)° to avoid singularities." maxlog = 1
        end

        lat_rad = deg2rad(lat)
        lon_rad = deg2rad(lon)
        sin_lat = sin(lat_rad)
        cos_lat = cos(lat_rad)

        # pre-compute parallax terms
        u = atan(0.99664719 * tan(lat_rad))
        x = cos(u) + alt / 6378140.0 * cos_lat
        y = 0.99664719 * sin(u) + alt / 6378140.0 * sin_lat

        new{T}(lat, lon, alt, lat_rad, lon_rad, sin_lat, cos_lat, u, x, y)
    end
end

SPAObserver(lat::T, lon::T; altitude = 0.0) where {T} = SPAObserver{T}(lat, lon, altitude)
SPAObserver(lat::T, lon::T, alt::T) where {T} = SPAObserver{T}(lat, lon, alt)


# heliocentric longitude coefficients (L0-L5)
include("spa_coefficients.jl")


# helper functions for SPA calculations
@inline function julian_ephemeris_day(jd::T, δt::T) where {T}
    return jd + δt / 86400.0
end

@inline function julian_ephemeris_century(jde::T) where {T}
    return (jde - 2451545.0) / 36525.0
end

@inline function julian_ephemeris_millennium(jce::T) where {T}
    return jce / 10.0
end

# calculate sum of A * cos(B + C*x) for coefficient array
@inline function sum_periodic_terms(coeffs::Matrix{T}, x::T) where {T}
    s = zero(T)
    for i in axes(coeffs, 1)
        s += coeffs[i, 1] * cos(coeffs[i, 2] + coeffs[i, 3] * x)
    end
    return s
end

function heliocentric_longitude(jme::T) where {T}
    l0 = sum_periodic_terms(L0, jme)
    l1 = sum_periodic_terms(L1, jme)
    l2 = sum_periodic_terms(L2, jme)
    l3 = sum_periodic_terms(L3, jme)
    l4 = sum_periodic_terms(L4, jme)
    l5 = sum_periodic_terms(L5, jme)

    l_rad = (l0 + l1 * jme + l2 * jme^2 + l3 * jme^3 + l4 * jme^4 + l5 * jme^5) / 1e8
    return mod(rad2deg(l_rad), 360.0)
end

function heliocentric_latitude(jme::T) where {T}
    b0 = sum_periodic_terms(B0, jme)
    b1 = sum_periodic_terms(B1, jme)

    b_rad = (b0 + b1 * jme) / 1e8
    return rad2deg(b_rad)
end

function heliocentric_radius_vector(jme::T) where {T}
    r0 = sum_periodic_terms(R0, jme)
    r1 = sum_periodic_terms(R1, jme)
    r2 = sum_periodic_terms(R2, jme)
    r3 = sum_periodic_terms(R3, jme)
    r4 = sum_periodic_terms(R4, jme)

    return (r0 + r1 * jme + r2 * jme^2 + r3 * jme^3 + r4 * jme^4) / 1e8
end

# nutation calculations
function mean_elongation(jce::T) where {T}
    return 297.85036 + 445267.111480 * jce - 0.0019142 * jce^2 + jce^3 / 189474.0
end

function mean_anomaly_sun(jce::T) where {T}
    return 357.52772 + 35999.050340 * jce - 0.0001603 * jce^2 - jce^3 / 300000.0
end

function mean_anomaly_moon(jce::T) where {T}
    return 134.96298 + 477198.867398 * jce + 0.0086972 * jce^2 + jce^3 / 56250.0
end

function moon_argument_latitude(jce::T) where {T}
    return 93.27191 + 483202.017538 * jce - 0.0036825 * jce^2 + jce^3 / 327270.0
end

function moon_ascending_longitude(jce::T) where {T}
    return 125.04452 - 1934.136261 * jce + 0.0020708 * jce^2 + jce^3 / 450000.0
end

function nutation_longitude_obliquity(jce::T) where {T}
    x0 = mean_elongation(jce)
    x1 = mean_anomaly_sun(jce)
    x2 = mean_anomaly_moon(jce)
    x3 = moon_argument_latitude(jce)
    x4 = moon_ascending_longitude(jce)

    δψ_sum = zero(T)
    δε_sum = zero(T)

    for i in axes(NUTATION_YTERM, 1)
        arg_deg =
            NUTATION_YTERM[i, 1] * x0 +
            NUTATION_YTERM[i, 2] * x1 +
            NUTATION_YTERM[i, 3] * x2 +
            NUTATION_YTERM[i, 4] * x3 +
            NUTATION_YTERM[i, 5] * x4

        arg_rad = deg2rad(arg_deg)
        δψ_sum += (NUTATION_ABCD[i, 1] + NUTATION_ABCD[i, 2] * jce) * sin(arg_rad)
        δε_sum += (NUTATION_ABCD[i, 3] + NUTATION_ABCD[i, 4] * jce) * cos(arg_rad)
    end

    δψ = δψ_sum / 36000000.0  # convert to degrees
    δε = δε_sum / 36000000.0  # convert to degrees

    return δψ, δε
end

function mean_ecliptic_obliquity(jme::T) where {T}
    u = jme / 10.0
    ε0 = (
        84381.448 - 4680.93 * u - 1.55 * u^2 + 1999.25 * u^3 - 51.38 * u^4 - 249.67 * u^5 - 39.05 * u^6 +
        7.12 * u^7 +
        27.87 * u^8 +
        5.79 * u^9 +
        2.45 * u^10
    )
    return ε0  # arcseconds
end

@inline function true_ecliptic_obliquity(ε0::T, δε::T) where {T}
    return ε0 / 3600.0 + δε  # convert arcseconds to degrees
end

@inline function aberration_correction(R::T) where {T}
    return -20.4898 / (3600.0 * R)  # degrees
end

@inline function apparent_sun_longitude(θ::T, δψ::T, δτ::T) where {T}
    return θ + δψ + δτ
end

function mean_sidereal_time(jd::T, jc::T) where {T}
    ν0 =
        280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * jc^2 -
        jc^3 / 38710000.0
    return mod(ν0, 360.0)
end

function apparent_sidereal_time(ν0::T, δψ::T, ε::T) where {T}
    return ν0 + δψ * cosd(ε)
end

function geocentric_sun_right_ascension(λ::T, ε::T, β::T) where {T}
    λ_rad = deg2rad(λ)
    ε_rad = deg2rad(ε)
    β_rad = deg2rad(β)

    num = sind(λ) * cosd(ε) - tand(β) * sind(ε)
    α = rad2deg(atan(num, cosd(λ)))
    return mod(α, 360.0)
end

function geocentric_sun_declination(λ::T, ε::T, β::T) where {T}
    β_rad = deg2rad(β)
    ε_rad = deg2rad(ε)
    λ_rad = deg2rad(λ)

    δ = rad2deg(asin(sin(β_rad) * cos(ε_rad) + cos(β_rad) * sin(ε_rad) * sin(λ_rad)))
    return δ
end

@inline function local_hour_angle(ν::T, lon::T, α::T) where {T}
    H = ν + lon - α
    return mod(H, 360.0)
end

@inline function equatorial_horizontal_parallax(R::T) where {T}
    return 8.794 / (3600.0 * R)  # degrees
end

# observer-dependent terms
@inline function u_term(lat::T) where {T}
    return atan(0.99664719 * tand(lat))
end

function x_term(u::T, lat::T, elev::T) where {T}
    return cos(u) + elev / 6378140.0 * cosd(lat)
end

function y_term(u::T, lat::T, elev::T) where {T}
    return 0.99664719 * sin(u) + elev / 6378140.0 * sind(lat)
end

function parallax_sun_right_ascension(x::T, ξ::T, H::T, δ::T) where {T}
    ξ_rad = deg2rad(ξ)
    H_rad = deg2rad(H)
    δ_rad = deg2rad(δ)

    num = -x * sin(ξ_rad) * sin(H_rad)
    denom = cos(δ_rad) - x * sin(ξ_rad) * cos(H_rad)
    Δα = rad2deg(atan(num, denom))
    return Δα
end

function topocentric_sun_declination(δ::T, x::T, y::T, ξ::T, Δα::T, H::T) where {T}
    δ_rad = deg2rad(δ)
    ξ_rad = deg2rad(ξ)
    Δα_rad = deg2rad(Δα)
    H_rad = deg2rad(H)

    num = (sin(δ_rad) - y * sin(ξ_rad)) * cos(Δα_rad)
    denom = cos(δ_rad) - x * sin(ξ_rad) * cos(H_rad)
    δ′ = rad2deg(atan(num, denom))
    return δ′
end

function topocentric_elevation_angle_without_atmosphere(lat::T, δ′::T, H′::T) where {T}
    lat_rad = deg2rad(lat)
    δ′_rad = deg2rad(δ′)
    H′_rad = deg2rad(H′)

    e0 =
        rad2deg(asin(sin(lat_rad) * sin(δ′_rad) + cos(lat_rad) * cos(δ′_rad) * cos(H′_rad)))
    return e0
end

function atmospheric_refraction_correction(
    pressure::T,
    temp::T,
    e0::T,
    atmos_refract::T,
) where {T}
    # only apply correction when sun is above horizon accounting for refraction
    if e0 < -(0.26667 + atmos_refract)
        return zero(T)
    end

    # convert pressure from Pa to hPa/mbar
    pressure_hPa = pressure / 100.0

    Δe =
        (pressure_hPa / 1010.0) * (283.0 / (273.0 + temp)) * 1.02 /
        (60.0 * tand(e0 + 10.3 / (e0 + 5.11)))
    return Δe  # already in degrees
end

function topocentric_azimuth_angle(H′::T, δ′::T, lat::T) where {T}
    H′_rad = deg2rad(H′)
    δ′_rad = deg2rad(δ′)
    lat_rad = deg2rad(lat)

    num = sin(H′_rad)
    denom = cos(H′_rad) * sin(lat_rad) - tan(δ′_rad) * cos(lat_rad)
    γ = rad2deg(atan(num, denom))

    # convert from astronomers azimuth (0=south) to standard (0=north)
    ϕ = mod(γ + 180.0, 360.0)
    return ϕ
end

function sun_mean_longitude(jme::T) where {T}
    M =
        280.4664567 + 360007.6982779 * jme + 0.03032028 * jme^2 + jme^3 / 49931.0 -
        jme^4 / 15300.0 - jme^5 / 2000000.0
    return M
end

function equation_of_time(M::T, α::T, δψ::T, ε::T) where {T}
    E = M - 0.0057183 - α + δψ * cosd(ε)
    E = mod(E, 360.0)
    # convert to minutes
    E *= 4.0

    # limit to ±20 minutes
    if E > 20.0
        E -= 1440.0
    elseif E < -20.0
        E += 1440.0
    end

    return E
end

function _solar_position(obs::Observer{T}, dt::DateTime, alg::SPA) where {T}
    spa_obs = SPAObserver{T}(obs.latitude, obs.longitude, obs.altitude)
    return _solar_position(spa_obs, dt, alg)
end

function _solar_position(obs::SPAObserver{T}, dt::DateTime, alg::SPA) where {T}
    δt = if alg.delta_t === nothing
        calculate_deltat(dt)
    else
        alg.delta_t
    end

    # julian date calculations
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

    # sidereal time
    ν0 = mean_sidereal_time(jd, jc)
    ν = apparent_sidereal_time(ν0, δψ, ε)

    # geocentric sun position
    α = geocentric_sun_right_ascension(λ, ε, β)
    δ = geocentric_sun_declination(λ, ε, β)

    # equation of time
    M = sun_mean_longitude(jme)
    eot = equation_of_time(M, α, δψ, ε)

    # observer local hour angle
    H = local_hour_angle(ν, obs.longitude, α)

    # parallax correction - use pre-computed values from SPAObserver
    ξ = equatorial_horizontal_parallax(R)
    # Note: obs.u, obs.x, obs.y are already computed in SPAObserver constructor

    # topocentric sun position
    Δα = parallax_sun_right_ascension(obs.x, ξ, H, δ)
    δ′ = topocentric_sun_declination(δ, obs.x, obs.y, ξ, Δα, H)
    H′ = mod(H - Δα, 360.0)  # topocentric local hour angle

    # topocentric elevation (without atmosphere)
    e0 = topocentric_elevation_angle_without_atmosphere(obs.latitude, δ′, H′)

    # atmospheric refraction correction
    Δe = atmospheric_refraction_correction(
        alg.pressure,
        alg.temperature,
        e0,
        alg.atmos_refract,
    )

    # final positions
    e = e0 + Δe  # apparent elevation
    θz = 90.0 - e  # apparent zenith
    θz0 = 90.0 - e0  # zenith without refraction

    # azimuth (same for both apparent and non-apparent)
    az = topocentric_azimuth_angle(H′, δ′, obs.latitude)

    return SPASolPos{T}(az, e0, θz0, e, θz, eot)
end

# SPA-specific method for NoRefraction to avoid ambiguity
function _solar_position(
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
    ::Refraction.NoRefraction,
) where {T}
    return _solar_position(obs, dt, alg)
end

# SPA has its own internal refraction handling, so when a refraction algorithm is provided,
# we ignore it and use SPA's built-in refraction
function _solar_position(
    obs::Observer{T},
    dt::DateTime,
    alg::SPA,
    refraction::Refraction.RefractionAlgorithm,
) where {T}
    @warn "SPA algorithm has its own refraction correction. The provided refraction algorithm will be ignored." maxlog =
        1
    return _solar_position(obs, dt, alg)
end

# SPA always returns SPASolPos (includes equation of time)
result_type(::Type{SPA}, ::Type{NoRefraction}, ::Type{T}) where {T} = SPASolPos{T}
result_type(::Type{SPA}, ::Type{<:RefractionAlgorithm}, ::Type{T}) where {T} = SPASolPos{T}
