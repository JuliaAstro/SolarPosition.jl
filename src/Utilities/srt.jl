"""Sunset, sunrise, transit, and twilight calculations."""

struct TransitSunriseSunset{T<:Union{DateTime,ZonedDateTime}}
    transit::T
    sunrise::T
    sunset::T
end

"""Calculate the sun transit, sunrise, and sunset
for a given date at an Observer location.
"""
function transit_sunrise_sunset(
    obs::Observer{T},
    dt::DateTime,
    alg::SolarAlgorithm = SPA(),
)::TransitSunriseSunset where {T<:AbstractFloat}
    _transit_sunrise_sunset(obs, dt, alg)
end

function transit_sunrise_sunset(
    obs::Observer{T},
    dt::Date,
    alg::SolarAlgorithm = SPA(),
) where {T<:AbstractFloat}
    transit_sunrise_sunset(obs, DateTime(dt), alg)
end

function transit_sunrise_sunset(
    obs::Observer{T},
    zdt::ZonedDateTime,
    alg::SolarAlgorithm = SPA(),
) where {T<:AbstractFloat}
    transit_sunrise_sunset(obs, DateTime(zdt), alg)
end

"""Calculate the next sunrise after a given DateTime at an Observer location."""
function next_sunrise(obs::Observer, dt::DateTime)
    # TODO: Implement
end

"""Calculate the next sunset after a given DateTime at an Observer location."""
function next_sunset(obs::Observer, dt::DateTime)
    # TODO: Implement
end

"""Calculate the solar noon time for a given DateTime at an Observer location."""
function solar_noon(obs::Observer, dt::DateTime)
    # TODO: Implement
end
