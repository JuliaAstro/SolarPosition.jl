"""
    $(TYPEDEF)

NOAA (National Oceanic and Atmospheric Administration) solar position algorithm.

This algorithm is based on NOAA's Solar Position Calculator implementation.
The algorithm is from "Astronomical Algorithms" by Jean Meeus.

# Accuracy
Claimed accuracy: ±0.0167° from years -2000 to +3000 for latitudes within ±72°.
For latitudes outside this range, the accuracy is ±0.167°.

# Literature
Based on the NOAA solar position calculator [NOAA](@cite) and the work by [MEEUS91](@cite).

# Fields
$(TYPEDFIELDS)

# Example
```jldoctest
julia> using Dates, TimeZones

julia> obs = Observer(52.52, 13.41);  # Berlin

julia> dt = ZonedDateTime(2024, 6, 21, 12, 0, 0, tz"UTC");

julia> pos = solar_position(obs, dt, NOAA());

julia> typeof(pos)
SolPos{Float64}
```
"""
struct NOAA <: SolarAlgorithm
    "Difference between terrestrial time and UT1 [seconds]. If `nothing`, uses automatic calculation."
    delta_t::Union{Float64,Nothing}
end

NOAA() = NOAA(67.0)  # default delta_t value (2020 default from pvlib)


function _solar_position(obs::Observer{T}, dt::DateTime, alg::NOAA) where {T}
    δt = if alg.delta_t === nothing
        calculate_deltat(dt)
    else
        alg.delta_t
    end

    # convert to Julian date and Julian century
    jd = datetime2julian(dt)
    jc = (jd - 2451545.0) / 36525.0

    # mean longitude of the sun [degrees]
    mean_long = mod(280.46646 + jc * (36000.76983 + jc * 0.0003032), 360.0)

    # mean anomaly [degrees]
    mean_anom = 357.52911 + jc * (35999.05029 - 0.0001537 * jc)

    # cccentricity of Earth's orbit
    eccent = 0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)

    # sun equation of center [degrees]
    sun_eq_ctr = (
        sind(mean_anom) * (1.914602 - jc * (0.004817 + 0.000014 * jc)) +
        sind(2 * mean_anom) * (0.019993 - 0.000101 * jc) +
        sind(3 * mean_anom) * 0.000289
    )

    # sun true/apparent longitude [degrees]
    sun_true_long = mean_long + sun_eq_ctr
    sun_app_long = sun_true_long - 0.00569 - 0.00478 * sind(125.04 - 1934.136 * jc)

    # mean obliquity of ecliptic [degrees]
    mean_obliq =
        23.0 +
        (26.0 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60.0) / 60.0

    # obliquity correction [degrees]
    obliq_corr = mean_obliq + 0.00256 * cosd(125.04 - 1934.136 * jc)
    sun_declin = asind(sind(obliq_corr) * sind(sun_app_long))

    # equation of time [minutes]
    var_y = tand(obliq_corr / 2.0)^2
    eot =
        4.0 * rad2deg(
            var_y * sind(2.0 * mean_long) - 2.0 * eccent * sind(mean_anom) +
            4.0 * eccent * var_y * sind(mean_anom) * cosd(2.0 * mean_long) -
            0.5 * var_y^2 * sind(4.0 * mean_long) - 1.25 * eccent^2 * sind(2.0 * mean_anom),
        )

    # true solar time [minutes]
    hour_frac = fractional_hour(dt)
    minutes = hour_frac * 60.0
    longitude_deg = rad2deg(obs.longitude_rad)
    true_solar_time = mod(minutes + eot + 4.0 * longitude_deg, 1440.0)

    # hour angle [degrees]
    hour_angle = if true_solar_time / 4.0 < 0.0
        true_solar_time / 4.0 + 180.0
    else
        true_solar_time / 4.0 - 180.0
    end

    # latitude adjustments for poles (match Python implementation)
    latitude_deg = rad2deg(obs.latitude_rad)
    if latitude_deg == 90.0
        latitude_deg -= 1e-6
    elseif latitude_deg == -90.0
        latitude_deg += 1e-6
    end

    # zenith angle [degrees]
    zenith = acosd(
        sind(latitude_deg) * sind(sun_declin) +
        cosd(latitude_deg) * cosd(sun_declin) * cosd(hour_angle),
    )

    # azimuth angle [degrees]
    azimuth_numerator = sind(latitude_deg) * cosd(zenith) - sind(sun_declin)
    azimuth_denominator = cosd(latitude_deg) * sind(zenith)

    azimuth = if hour_angle > 0.0
        mod(acosd(azimuth_numerator / azimuth_denominator) + 180.0, 360.0)
    else
        mod(540.0 - acosd(azimuth_numerator / azimuth_denominator), 360.0)
    end

    return SolPos{T}(azimuth, 90.0 - zenith, zenith)
end
