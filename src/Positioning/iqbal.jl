"""
    $(TYPEDEF)

Iqbal solar position algorithm.

A lightweight algorithm that obtains the solar declination and equation of time from a
truncated Fourier series in the day angle, then derives the zenith and azimuth from
the standard spherical trigonometry relations. No atmospheric refraction is applied by
default.

# Accuracy
The truncated Fourier expansion gives a declination accurate to about ±0.01°, which
makes this algorithm a good choice when speed matters more than sub arcminute
precision.

# Literature
Based on the formulation compiled by [Iqb83](@cite), which builds on the Fourier
series representation of [Spe71](@cite).
"""
struct Iqbal <: SolarAlgorithm end

function _solar_position(obs::Observer{T}, dt::DateTime, ::Iqbal) where {T <: Real}
    # day angle in radians
    Γ = 2 * T(π) * (dayofyear(dt) - 1) / T(365)

    (sin_Γ, cos_Γ) = sincos(Γ)
    (sin_2Γ, cos_2Γ) = sincos(2 * Γ)
    (sin_3Γ, cos_3Γ) = sincos(3 * Γ)

    # solar declination in degrees
    declination = rad2deg(
        T(0.006918) - T(0.399912) * cos_Γ + T(0.070257) * sin_Γ -
            T(0.006758) * cos_2Γ + T(0.000907) * sin_2Γ -
            T(0.002697) * cos_3Γ + T(0.00148) * sin_3Γ,
    )

    # equation of time in minutes
    eot = (
        T(0.0000075) + T(0.001868) * cos_Γ - T(0.032077) * sin_Γ -
            T(0.014615) * cos_2Γ - T(0.040849) * sin_2Γ
    ) * T(1440) / 2 / T(π)

    # hour angle in degrees
    ω = (fractional_hour(T, dt) - 12) * 15 + obs.longitude + eot / 4

    (sin_δ, cos_δ) = sincosd(declination)
    (sin_ω, cos_ω) = sincosd(ω)

    # zenith angle in degrees
    zenith = acosd(unit_clamp(sin_δ * obs.sin_lat + cos_δ * obs.cos_lat * cos_ω))

    # azimuth in degrees east of north. The two argument arctangent selects the
    # correct quadrant where the closed form expression is ambiguous.
    azimuth = mod(
        atand(
            sin_ω * cos_δ,
            cos_ω * obs.sin_lat * cos_δ - obs.cos_lat * sin_δ,
        ) + 180,
        360,
    )

    return SolPos{T}(azimuth, 90 - zenith, zenith)
end

function _solar_position(obs::AbstractObserver, dt, alg::Iqbal, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, NoRefraction())
end

# Iqbal applies no refraction by default, so DefaultRefraction returns SolPos
result_type(::Type{Iqbal}, ::Type{DefaultRefraction}, ::Type{T}) where {T} = SolPos{T}
