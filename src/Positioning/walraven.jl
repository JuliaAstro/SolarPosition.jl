"""
    $(TYPEDEF)

Walraven solar position algorithm. The implementation accounts for the 1979 Erratum and
correct azimuth quadrant selection.

# Accuracy
Claimed accuracy is ±0.0100°.

# Literature
This algorithm is based on [Wal78](@cite) with corrections from the 1979 Erratum
[Wal79](@cite) and azimuth quadrant correction from [Spe89](@cite).
"""
struct Walraven <: SolarAlgorithm end


function _solar_position(obs::Observer{T}, dt::DateTime, ::Walraven) where {T}
    # use negative longitude (outdated convention used by Walraven)
    longitude = -obs.longitude

    # calculate fractional hour
    hour_frac = fractional_hour(dt)
    δ = year(dt) - 1980

    # leap year calculation (round towards zero)
    leap = div(δ, 4)
    time = δ * 365 + leap + dayofyear(dt) - 1 + hour_frac / 24

    if δ == (leap * 4)
        time -= 1
    end
    if (δ < 0) && (δ != (leap * 4))
        time -= 1
    end

    # angular position in orbit [rad]
    θ = 2 * T(π) * time / 365.25

    # mean anomaly [rad]
    g = -0.031271 - 4.53963e-7 * time + θ

    # longitude of the sun [rad]
    lon_sun = (
        4.900968 +
        3.67474e-7 * time +
        (0.033434 - 2.3e-9 * time) * sin(g) +
        0.000349 * sin(2 * g) +
        θ
    )

    # obliquity of ecliptic [rad]
    ϵ = deg2rad(T(23.4420)) - deg2rad(T(3.56e-7)) * time
    sel = sin(lon_sun)

    # right ascension [rad]
    ra = atan(sel * cos(ϵ), cos(lon_sun))
    if ra < 0
        ra += 2 * T(π)
    end

    # declination [rad]
    d = asin(sel * sin(ϵ))

    # sidereal time [rad]
    side_t = 1.759335 + 2 * T(π) * (time / 365.25 - δ) + 3.694e-7 * time
    if side_t >= 2 * T(π)
        side_t -= 2 * T(π)
    end

    # local sidereal time [rad]
    loc_s = side_t - deg2rad(T(longitude)) + deg2rad(T(hour_frac * 15))
    if loc_s >= 2 * T(π)
        loc_s -= 2 * T(π)
    end

    # hour angle [rad]
    ha = ra - loc_s

    # elevation [rad]
    el = asin(obs.sin_lat * sin(d) + obs.cos_lat * cos(d) * cos(ha))

    # azimuth [deg] - initial calculation
    az = rad2deg(asin(cos(d) * sin(ha) / cos(el)))

    # azimuth quadrant assignment - Spencer (1989) correction for all longitudes
    cos_az = sin(d) - sin(el) * obs.sin_lat

    if (cos_az >= 0) && (sin(deg2rad(az)) < 0)
        az = 360 + az
    end

    if cos_az < 0
        az = 180 - az
    end

    elevation_deg = rad2deg(el)
    return SolPos{T}(az, elevation_deg, 90 - elevation_deg)
end
