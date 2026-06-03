"""
    $(TYPEDEF)

Iqbal solar position algorithm.

A lightweight algorithm that obtains the solar declination and equation of time from a
truncated Fourier series in the day angle, then derives the zenith and azimuth from the
standard spherical-trigonometry relations. No atmospheric refraction is applied by default.

# Accuracy
The truncated Fourier expansion gives a declination accurate to about ±0.01°, which makes
this algorithm a good choice when speed matters more than sub-arcminute precision.

# Literature
Based on the formulation compiled by [Iqb83](@cite), which builds on the Fourier-series
representation of [Spe71](@cite).

# Fields
$(TYPEDFIELDS)
"""
struct Iqbal <: SolarAlgorithm end

function _solar_position(obs::Observer{T}, dt::DateTime, ::Iqbal) where {T}
    # day angle [radians]
    day_angle = 2π * (dayofyear(dt) - 1) / 365

    (sin_Γ, cos_Γ) = sincos(day_angle)
    (sin_2Γ, cos_2Γ) = sincos(2 * day_angle)
    (sin_3Γ, cos_3Γ) = sincos(3 * day_angle)

    # solar declination [degrees]
    declination = rad2deg(
        0.006918 - 0.399912 * cos_Γ + 0.070257 * sin_Γ -
            0.006758 * cos_2Γ + 0.000907 * sin_2Γ -
            0.002697 * cos_3Γ + 0.00148 * sin_3Γ,
    )

    # equation of time [minutes]
    eot =
        (
        0.0000075 + 0.001868 * cos_Γ - 0.032077 * sin_Γ -
            0.014615 * cos_2Γ - 0.040849 * sin_2Γ
    ) * 1440 / (2π)

    # hour angle [degrees]
    hour_angle = (fractional_hour(dt) - 12) * 15 + obs.longitude + eot / 4

    (sin_δ, cos_δ) = sincosd(declination)
    (sin_ω, cos_ω) = sincosd(hour_angle)

    # zenith angle [degrees]
    zenith = acosd(sin_δ * obs.sin_lat + cos_δ * obs.cos_lat * cos_ω)

    # azimuth [degrees], measured eastward from north. The arctan form selects the correct
    # quadrant where the closed-form expression would be ambiguous.
    azimuth = mod(
        atand(
            sin_ω * cos_δ,
            cos_ω * obs.sin_lat * cos_δ - obs.cos_lat * sin_δ,
        ) + 180,
        360,
    )

    return SolPos{T}(azimuth, 90 - zenith, zenith)
end

function _solar_position(obs, dt, alg::Iqbal, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, NoRefraction())
end

# Iqbal with DefaultRefraction returns SolPos (no refraction by default)
result_type(::Type{Iqbal}, ::Type{DefaultRefraction}, ::Type{T}) where {T} = SolPos{T}
