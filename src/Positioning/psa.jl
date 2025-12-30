"""
    $(TYPEDEF)

PSA (Plataforma Solar de Almería) solar position algorithm. This algorithm computes
the solar position with high accuracy using empirical coefficients. Two coefficient sets
are available: 2001 (range 1999-2015) and 2020 (range 2020-2050).

# Accuracy
Claimed accuracy: ±0.004° for 2020 coefficients, ±0.01° for 2001 coefficients.

# Literature
This algorithm is based on the work by [BALL01](@cite) and was updated for 2020
coefficients in [BMB20](@cite).

# Fields
$(TYPEDFIELDS)
"""
struct PSA <: SolarAlgorithm
    "Coefficient set year (2001 or 2020)"
    coeffs::Int
end

PSA() = PSA(2020)

@inline function get_psa_params(coeffs::Int)
    if coeffs == 2020
        return (
            2.267127827,
            -9.300339267e-4,
            4.895036035,
            1.720279602e-2,
            6.239468336,
            1.720200135e-2,
            3.338320972e-2,
            3.497596876e-4,
            -1.544353226e-4,
            -8.689729360e-6,
            4.090904909e-1,
            -6.213605399e-9,
            4.418094944e-5,
            6.697096103,
            6.570984737e-2,
        )
    elseif coeffs == 2001
        return (
            2.1429,
            -0.0010394594,
            4.8950630,
            0.017202791698,
            6.2400600,
            0.0172019699,
            0.03341607,
            0.00034894,
            -0.0001134,
            -0.0000203,
            0.4090928,
            -6.2140e-09,
            0.0000396,
            6.6974243242,
            0.0657098283,
        )
    else
        error("Unknown PSA coefficient set: $coeffs. Valid options are 2001 or 2020.")
    end
end

function _solar_position(obs::Observer{T}, dt::DateTime, alg::PSA) where {T}
    # Get parameters as tuple (allocation-free)
    p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15 =
        get_psa_params(alg.coeffs)

    # elapsed julian days (n) since J2000.0
    jd = datetime2julian(dt)
    n = jd - 2451545.0                                                  # Eq. 2

    # ecliptic coordinates of the sun
    # ecliptic longitude (λₑ), and obliquity of the ecliptic (ϵ)
    Ω = p1 + p2 * n                                                     # Eq. 3
    L = p3 + p4 * n                                                     # Eq. 4
    g = p5 + p6 * n                                                     # Eq. 5
    (sin_Ω, cos_Ω) = sincos(Ω)
    λₑ = L + p7 * sin(g) + p8 * sin(2 * g) + p9 + p10 * sin_Ω           # Eq. 6
    ϵ = p11 + p12 * n + p13 * cos_Ω                                     # Eq. 7

    # celestial right ascension (ra) and declination (d)
    (sin_ϵ, cos_ϵ) = sincos(ϵ)
    (sin_λₑ, cos_λₑ) = sincos(λₑ)
    ra = atan(cos_ϵ * sin_λₑ, cos_λₑ)                                   # Eq. 8
    ra = mod(ra, 2π)
    δ = asin(sin_ϵ * sin_λₑ)                                            # Eq. 9

    # computes the local coordinates: azimuth (γ) and zenith angle (θz)
    λt = rad2deg(obs.longitude_rad)
    cos_lat = obs.cos_lat
    sin_lat = obs.sin_lat

    hour = fractional_hour(dt)
    gmst = p14 + p15 * n + hour                                         # Eq. 10
    lmst = deg2rad(gmst * 15 + λt)                                      # Eq. 11
    ω = lmst - ra                                                       # Eq. 12
    (sin_δ, cos_δ) = sincos(δ)
    (sin_ω, cos_ω) = sincos(ω)
    θz = acos(cos_lat * cos_ω * cos_δ + sin_δ * sin_lat)                # Eq. 13
    γ = atan(-sin_ω, (tan(δ) * cos_lat - sin_lat * cos_ω))              # Eq. 14

    # parallax correction
    θz = θz + (EMR / AU) * sin(θz)                                      # Eq. 15,16

    return SolPos{T}(mod(rad2deg(γ), 360.0), rad2deg(π / 2 - θz), rad2deg(θz))
end

function _solar_position(obs, dt, alg::PSA, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, NoRefraction())
end

# PSA with DefaultRefraction returns SolPos (no refraction by default)
result_type(::Type{PSA}, ::Type{DefaultRefraction}, ::Type{T}) where {T} = SolPos{T}
