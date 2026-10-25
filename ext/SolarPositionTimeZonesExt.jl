"""
TimeZones support for SolarPosition.jl.

This module adds support for `ZonedDateTime` inputs and timezone aware sunrise/sunset.
"""
module SolarPositionTimeZonesExt

using Dates: DateTime
using SolarPosition: Positioning, Utilities
using StructArrays: StructArrays
using TimeZones: TimeZone, ZonedDateTime, UTC, timezone

using SolarPosition.Positioning: AbstractObserver, AbstractSolPos, Interpolated, Observer,
    PSA, SolarAlgorithm, _result_eltype, calculate_deltat, result_type, solar_position,
    solar_position!, solar_rate
using SolarPosition.Refraction: DefaultRefraction, RefractionAlgorithm
using SolarPosition.Utilities: SPA, TransitSunriseSunset, _transit_sunrise_sunset,
    _transit_sunrise_sunset_impl, next_solar_noon, next_sunrise, next_sunset,
    previous_solar_noon, previous_sunrise, previous_sunset, transit_sunrise_sunset

const ZonedVector = Union{
    AbstractVector{ZonedDateTime}, AbstractVector{Union{DateTime, ZonedDateTime}},
}

function Positioning.solar_position(
        obs::AbstractObserver{T},
        dt::ZonedDateTime,
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: Real}
    return solar_position(obs, DateTime(dt, UTC), alg, refraction)
end

function Positioning.solar_position!(
        pos::StructArrays.StructVector{T},
        obs::AbstractObserver,
        dts::ZonedVector,
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: AbstractSolPos}
    @inbounds for i in eachindex(dts, pos)
        pos[i] = solar_position(obs, dts[i], alg, refraction)
    end
    return pos
end

function Positioning.solar_position(
        obs::AbstractObserver{T},
        dts::ZonedVector,
        alg::SolarAlgorithm = PSA(),
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {T <: Real}
    RetType = result_type(
        typeof(alg), typeof(refraction), _result_eltype(T, refraction),
    )
    pos = StructArrays.StructVector{RetType}(undef, length(dts))
    solar_position!(pos, obs, dts, alg, refraction)
    return pos
end

Positioning.solar_rate(obs::AbstractObserver, dt::ZonedDateTime, alg::Interpolated) =
    solar_rate(obs, DateTime(dt, UTC), alg)

# --------------------------------------------------------------------------- delta T

Positioning.calculate_deltat(datetime::ZonedDateTime) =
    calculate_deltat(DateTime(datetime, UTC))

Positioning.calculate_deltat(::Type{T}, datetime::ZonedDateTime) where {T <: Real} =
    T(calculate_deltat(datetime))

Positioning._as_utc(zdt::ZonedDateTime) = DateTime(zdt, UTC)

# --------------------------------------------------------- sunrise, sunset, transit

function Utilities.TransitSunriseSunset{ZonedDateTime}(
        transit::DateTime,
        sunrise::DateTime,
        sunset::DateTime,
        tz::TimeZone,
    )
    return TransitSunriseSunset{ZonedDateTime}(
        ZonedDateTime(transit, tz; from_utc = true),
        ZonedDateTime(sunrise, tz; from_utc = true),
        ZonedDateTime(sunset, tz; from_utc = true),
    )
end

function Utilities._transit_sunrise_sunset(
        tz::TimeZone,
        obs::Observer{T},
        dt::DateTime,
        alg::SPA,
    ) where {T <: Real}
    return _transit_sunrise_sunset_impl(ZonedDateTime, obs, dt, alg, tz)
end

function Utilities.transit_sunrise_sunset(
        obs::Observer{T},
        zdt::ZonedDateTime,
        alg::SolarAlgorithm = SPA(),
    )::TransitSunriseSunset{ZonedDateTime} where {T <: Real}
    return _transit_sunrise_sunset(timezone(zdt), obs, DateTime(zdt, UTC), alg)
end

function Utilities.next_sunrise(
        obs::Observer,
        zdt::ZonedDateTime,
        alg::SolarAlgorithm = SPA(),
    )
    result_utc = next_sunrise(obs, DateTime(zdt, UTC), alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

function Utilities.next_sunset(
        obs::Observer,
        zdt::ZonedDateTime,
        alg::SolarAlgorithm = SPA(),
    )
    result_utc = next_sunset(obs, DateTime(zdt, UTC), alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

function Utilities.next_solar_noon(
        obs::Observer,
        zdt::ZonedDateTime,
        alg::SolarAlgorithm = SPA(),
    )
    result_utc = next_solar_noon(obs, DateTime(zdt, UTC), alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

function Utilities.previous_sunrise(
        obs::Observer,
        zdt::ZonedDateTime,
        alg::SolarAlgorithm = SPA(),
    )
    result_utc = previous_sunrise(obs, DateTime(zdt, UTC), alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

function Utilities.previous_sunset(
        obs::Observer,
        zdt::ZonedDateTime,
        alg::SolarAlgorithm = SPA(),
    )
    result_utc = previous_sunset(obs, DateTime(zdt, UTC), alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

function Utilities.previous_solar_noon(
        obs::Observer,
        zdt::ZonedDateTime,
        alg::SolarAlgorithm = SPA(),
    )
    result_utc = previous_solar_noon(obs, DateTime(zdt, UTC), alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

end # module SolarPositionTimeZonesExt
