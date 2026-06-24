using ..Refraction: SG2Refraction

# Earth heliocentric longitude periodic terms (frequency [1/day], amplitude [rad], phase [rad]).
const _SG2_HELIO = (
    (1 / 365.261278, 3.401508e-2, 1.60078),
    (1 / 182.632412, 3.48644e-4, 1.662976),
    (1 / 29.530634, 3.136227e-5, -1.195905),
    (1 / 399.52985, 3.578979e-5, -1.042052),
    (1 / 291.956812, 2.676185e-5, 2.012613),
    (1 / 583.598201, 2.333925e-5, -2.867714),
    (1 / 4652.629372, 1.221214e-5, 1.225038),
    (1 / 1450.236684, 1.217941e-5, -0.828601),
    (1 / 199.459709, 1.343914e-5, -3.108253),
    (1 / 365.355291, 8.499475e-4, -2.353709),
)

"""
    $(TYPEDEF)

SG2 (Second Generation) solar position algorithm.

A fast, accurate algorithm tuned for multi-decadal time periods. By default the
[`SG2Refraction`](@ref) atmospheric refraction model is applied.

# Accuracy
Claimed accuracy: ±0.003° between 1980 and 2030. The algorithm is only defined within this
range; calling it for a date outside it throws an `ArgumentError`.

# Literature
Based on the algorithm of [BW12](@cite).

# Fields
$(TYPEDFIELDS)
"""
struct SG2 <: SolarAlgorithm end

function _solar_position(obs::Observer{T}, dt::DateTime, ::SG2) where {T}
    yr = year(dt)
    mo = month(dt)
    dom = day(dt)
    hour = fractional_hour(dt)

    # year in decimal form, used both for the validity range and the ΔT branch
    year_dec = yr + (mo - 0.5) / 12
    if year_dec < 1980 || year_dec > 2030
        throw(
            ArgumentError(
                "SG2 is only valid for years 1980–2030, got $(year_dec)",
            ),
        )
    end

    # ΔT [seconds] from a piecewise polynomial in the (integer) year
    (y_ref, c0, c1, c2, c3, c4, c5) = if year_dec <= 1986
        (1975, 45.45, 1.067, -1 / 260, -1 / 718, 0.0, 0.0)
    elseif year_dec <= 2005
        (2000, 63.86, 0.3345, -0.060374, 0.0017275, 6.518e-4, 2.374e-5)
    else
        (2000, 63.48, 0.204, 0.005576, 0.0, 0.0, 0.0)
    end
    Δy = yr - y_ref
    delta_t = c0 + c1 * Δy + c2 * Δy^2 + c3 * Δy^3 + c4 * Δy^4 + c5 * Δy^5

    # Julian day (UT and TT)
    (year_mod, month_mod) = (mo == 1 || mo == 2) ? (yr - 1, mo + 12) : (yr, mo)
    jd_ut =
        1721028.0 + dom + floor((153.0 * month_mod - 2.0) / 5.0) +
        365.0 * year_mod + floor(year_mod / 4.0) + hour / 24 - 0.5 -
        floor(year_mod / 100.0) + floor(year_mod / 400.0)
    jd_tt = jd_ut + delta_t / 86400

    jd_ut_mod = jd_ut - 2444239.5
    jd_tt_mod = jd_tt - 2444239.5

    # Earth heliocentric longitude [rad]
    sums = 0.0
    for (f_L, ρ_L, φ_L) in _SG2_HELIO
        sums += ρ_L * cos(2π * f_L * jd_tt_mod - φ_L)
    end
    L = mod(sums + (1 / 58.130101) * jd_tt_mod + 1.742145, 2π)

    # geocentric nutation and true obliquity [rad]
    D_t = -9.933735e-5
    ξ = 4.263521e-5
    D_ψ = 8.329092e-5 * cos(2π * (1 / 6791.164405) * jd_tt_mod - (-2.052757))
    ε =
        4.456183e-5 * cos(2π * (1 / 6791.164405) * jd_tt_mod - 2.660352) +
        (-6.216374e-9) * jd_tt_mod + 4.091383e-1

    # apparent sun geocentric longitude [rad]
    Θ = mod(L + π + D_ψ + D_t, 2π)

    # geocentric declination and right ascension [rad]
    decl_g = asin(sin(Θ) * sin(ε))
    ra = atan(sin(Θ) * cos(ε), cos(Θ))

    # mean sidereal time [rad]
    mst = mod(6.300388099 * jd_ut_mod + 1.742079, 2π)

    # observer geocentric coordinates (oblate Earth)
    a = 6378140.0
    f = 1 / 298.257282697
    u = atan((1 - f) * tan(obs.latitude_rad))
    x = cos(u) + obs.altitude / a * obs.cos_lat
    y = (1 - f) * sin(u) + obs.altitude / a * obs.sin_lat

    # topocentric correction (parallax)
    ν = mst + D_ψ * cos(ε)
    ω_g = ν + obs.longitude_rad - ra
    D_ra = -x * sin(ω_g) / cos(decl_g) * ξ
    declination = decl_g + (x * cos(ω_g) * sin(decl_g) - y * cos(decl_g)) * ξ
    ω = mst + D_ψ * cos(ε) - ra + obs.longitude_rad - D_ra

    # topocentric azimuth and elevation [rad]
    azimuth_rad =
        atan(
        sin(ω),
        cos(ω) * obs.sin_lat - tan(declination) * obs.cos_lat,
    ) + π
    elevation_rad =
        asin(obs.sin_lat * sin(declination) + obs.cos_lat * cos(declination) * cos(ω))

    elevation = rad2deg(elevation_rad)
    return SolPos{T}(mod(rad2deg(azimuth_rad), 360), elevation, 90 - elevation)
end

function _solar_position(obs, dt, alg::SG2, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, SG2Refraction())
end

# SG2 with DefaultRefraction returns ApparentSolPos (uses SG2Refraction)
result_type(::Type{SG2}, ::Type{DefaultRefraction}, ::Type{T}) where {T} = ApparentSolPos{T}
