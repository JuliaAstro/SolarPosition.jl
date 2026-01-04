"""Sunset, sunrise, transit, and twilight calculations."""

"""
    $(TYPEDEF)

Struct to hold the results of sun transit, sunrise, and sunset calculations.

The datetime fields are in UTC unless a TimeZone is provided, in which case they are
converted to that timezone assuming the input DateTime was in UTC.

# Constructors
```julia
TransitSunriseSunset{DateTime}(
    transit::DateTime,
    sunrise::DateTime,
    sunset::DateTime,
    ::Nothing,
)
TransitSunriseSunset{ZonedDateTime}(
    transit::DateTime,
    sunrise::DateTime,
    sunset::DateTime,
    tz::TimeZone,
)
```

# Fields
$(TYPEDFIELDS)
"""
struct TransitSunriseSunset{T<:Union{DateTime,ZonedDateTime}}
    transit::T
    sunrise::T
    sunset::T
end

# Constructor for DateTime (no timezone conversion)
function TransitSunriseSunset{DateTime}(
    transit::DateTime,
    sunrise::DateTime,
    sunset::DateTime,
    ::Nothing,
)
    return TransitSunriseSunset{DateTime}(transit, sunrise, sunset)
end

# Constructor for ZonedDateTime (with timezone conversion)
function TransitSunriseSunset{ZonedDateTime}(
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

"""Calculate the sun transit, sunrise, and sunset
for a given date at an Observer location.
"""
function transit_sunrise_sunset(
    obs::Observer{T},
    dt::DateTime,
    alg::SolarAlgorithm = SPA(),
)::TransitSunriseSunset{DateTime} where {T<:AbstractFloat}
    _transit_sunrise_sunset(DateTime, obs, dt, alg)
end

function transit_sunrise_sunset(
    obs::Observer{T},
    dt::Date,
    alg::SolarAlgorithm = SPA(),
)::TransitSunriseSunset{DateTime} where {T<:AbstractFloat}
    transit_sunrise_sunset(obs, DateTime(dt), alg)
end

function transit_sunrise_sunset(
    obs::Observer{T},
    zdt::ZonedDateTime,
    alg::SolarAlgorithm = SPA(),
)::TransitSunriseSunset{ZonedDateTime} where {T<:AbstractFloat}
    _transit_sunrise_sunset(timezone(zdt), obs, DateTime(zdt, UTC), alg)
end

# Helper function for next_* functions
function _next_event(obs::Observer, dt::DateTime, alg::SolarAlgorithm, event_field::Symbol)
    date_only = Date(dt)
    midnight_utc = DateTime(date_only)
    result = transit_sunrise_sunset(obs, midnight_utc, alg)
    event_time = getfield(result, event_field)

    if event_time > dt
        return event_time
    end

    next_day = midnight_utc + Day(1)
    result_next = transit_sunrise_sunset(obs, next_day, alg)
    return getfield(result_next, event_field)
end

# Helper function for previous_* functions
function _previous_event(
    obs::Observer,
    dt::DateTime,
    alg::SolarAlgorithm,
    event_field::Symbol,
)
    date_only = Date(dt)
    midnight_utc = DateTime(date_only)
    result = transit_sunrise_sunset(obs, midnight_utc, alg)
    event_time = getfield(result, event_field)

    # If the event has already passed (not including exact match), return it
    if event_time < dt
        return event_time
    end

    # Otherwise (future event or exact match), go back a day
    prev_day = midnight_utc - Day(1)
    result_prev = transit_sunrise_sunset(obs, prev_day, alg)
    prev_event_time = getfield(result_prev, event_field)

    # If we still got an exact match (e.g., sunset crosses midnight), go back another day
    if prev_event_time == dt
        prev_prev_day = midnight_utc - Day(2)
        result_prev_prev = transit_sunrise_sunset(obs, prev_prev_day, alg)
        return getfield(result_prev_prev, event_field)
    end

    return prev_event_time
end

"""
    $(TYPEDSIGNATURES)

Calculate the next sunrise after a given DateTime at an Observer location.

# Arguments
- `obs`: Observer location
- `dt`: DateTime to start searching from
- `alg`: Solar algorithm to use (default: SPA())

# Returns
- DateTime of the next sunrise after `dt`
"""
function next_sunrise(obs::Observer, dt::DateTime, alg::SolarAlgorithm = SPA())
    return _next_event(obs, dt, alg, :sunrise)
end

function next_sunrise(obs::Observer, dt::Date, alg::SolarAlgorithm = SPA())
    return next_sunrise(obs, DateTime(dt), alg)
end

function next_sunrise(obs::Observer, zdt::ZonedDateTime, alg::SolarAlgorithm = SPA())
    dt_utc = DateTime(zdt, UTC)
    result_utc = next_sunrise(obs, dt_utc, alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

"""
    $(TYPEDSIGNATURES)

Calculate the next sunset after a given DateTime at an Observer location.

# Arguments
- `obs`: Observer location
- `dt`: DateTime to start searching from
- `alg`: Solar algorithm to use (default: SPA())

# Returns
- DateTime of the next sunset after `dt`
"""
function next_sunset(obs::Observer, dt::DateTime, alg::SolarAlgorithm = SPA())
    return _next_event(obs, dt, alg, :sunset)
end

function next_sunset(obs::Observer, dt::Date, alg::SolarAlgorithm = SPA())
    return next_sunset(obs, DateTime(dt), alg)
end

function next_sunset(obs::Observer, zdt::ZonedDateTime, alg::SolarAlgorithm = SPA())
    dt_utc = DateTime(zdt, UTC)
    result_utc = next_sunset(obs, dt_utc, alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

"""
    $(TYPEDSIGNATURES)

Calculate the solar noon (transit) time for a given DateTime at an Observer location.
If the solar noon for the current day has already passed, returns the solar noon for the next day.

# Arguments
- `obs`: Observer location
- `dt`: DateTime to start searching from
- `alg`: Solar algorithm to use (default: SPA())

# Returns
- DateTime of the next solar noon (transit) after `dt`
"""
function next_solar_noon(obs::Observer, dt::DateTime, alg::SolarAlgorithm = SPA())
    return _next_event(obs, dt, alg, :transit)
end

function next_solar_noon(obs::Observer, dt::Date, alg::SolarAlgorithm = SPA())
    return next_solar_noon(obs, DateTime(dt), alg)
end

function next_solar_noon(obs::Observer, zdt::ZonedDateTime, alg::SolarAlgorithm = SPA())
    dt_utc = DateTime(zdt, UTC)
    result_utc = next_solar_noon(obs, dt_utc, alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

"""
    $(TYPEDSIGNATURES)

Calculate the previous sunrise before a given DateTime at an Observer location.

# Arguments
- `obs`: Observer location
- `dt`: DateTime to start searching from
- `alg`: Solar algorithm to use (default: SPA())

# Returns
- DateTime of the previous sunrise before `dt`
"""
function previous_sunrise(obs::Observer, dt::DateTime, alg::SolarAlgorithm = SPA())
    return _previous_event(obs, dt, alg, :sunrise)
end

function previous_sunrise(obs::Observer, dt::Date, alg::SolarAlgorithm = SPA())
    return previous_sunrise(obs, DateTime(dt), alg)
end

function previous_sunrise(obs::Observer, zdt::ZonedDateTime, alg::SolarAlgorithm = SPA())
    dt_utc = DateTime(zdt, UTC)
    result_utc = previous_sunrise(obs, dt_utc, alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

"""
    $(TYPEDSIGNATURES)

Calculate the previous sunset before a given DateTime at an Observer location.

# Arguments
- `obs`: Observer location
- `dt`: DateTime to start searching from
- `alg`: Solar algorithm to use (default: SPA())

# Returns
- DateTime of the previous sunset before `dt`
"""
function previous_sunset(obs::Observer, dt::DateTime, alg::SolarAlgorithm = SPA())
    return _previous_event(obs, dt, alg, :sunset)
end

function previous_sunset(obs::Observer, dt::Date, alg::SolarAlgorithm = SPA())
    return previous_sunset(obs, DateTime(dt), alg)
end

function previous_sunset(obs::Observer, zdt::ZonedDateTime, alg::SolarAlgorithm = SPA())
    dt_utc = DateTime(zdt, UTC)
    result_utc = previous_sunset(obs, dt_utc, alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end

"""
    $(TYPEDSIGNATURES)

Calculate the previous solar noon (transit) before a given DateTime at an Observer location.

# Arguments
- `obs`: Observer location
- `dt`: DateTime to start searching from
- `alg`: Solar algorithm to use (default: SPA())

# Returns
- DateTime of the previous solar noon (transit) before `dt`
"""
function previous_solar_noon(obs::Observer, dt::DateTime, alg::SolarAlgorithm = SPA())
    return _previous_event(obs, dt, alg, :transit)
end

function previous_solar_noon(obs::Observer, dt::Date, alg::SolarAlgorithm = SPA())
    return previous_solar_noon(obs, DateTime(dt), alg)
end

function previous_solar_noon(obs::Observer, zdt::ZonedDateTime, alg::SolarAlgorithm = SPA())
    dt_utc = DateTime(zdt, UTC)
    result_utc = previous_solar_noon(obs, dt_utc, alg)
    return ZonedDateTime(result_utc, timezone(zdt); from_utc = true)
end
