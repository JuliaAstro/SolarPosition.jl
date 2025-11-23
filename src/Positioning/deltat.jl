"""
Utility to calculate deltat.
"""


const DELTAT_TABLE = [
    (-Inf, -500) => (y -> -20 + 32 * ((y - 1820) / 100)^2),
    (-500, 500) => (
        y ->
            10583.6 - 1014.41 * (y / 100) + 33.78311 * (y / 100)^2 -
            5.952053 * (y / 100)^3 - 0.1798452 * (y / 100)^4 +
            0.022174192 * (y / 100)^5 +
            0.0090316521 * (y / 100)^6
    ),
    (500, 1600) => (
        y ->
            1574.2 - 556.01 * ((y - 1000) / 100) +
            71.23472 * ((y - 1000) / 100)^2 +
            0.319781 * ((y - 1000) / 100)^3 - 0.8503463 * ((y - 1000) / 100)^4 -
            0.005050998 * ((y - 1000) / 100)^5 +
            0.0083572073 * ((y - 1000) / 100)^6
    ),
    (1600, 1700) =>
        (y -> 120 - 0.9808 * (y - 1600) - 0.01532 * (y - 1600)^2 + (y - 1600)^3 / 7129),
    (1700, 1800) => (
        y ->
            8.83 + 0.1603 * (y - 1700) - 0.0059285 * (y - 1700)^2 +
            0.00013336 * (y - 1700)^3 - (y - 1700)^4 / 1174000
    ),
    (1800, 1860) => (
        y ->
            13.72 - 0.332447 * (y - 1800) +
            0.0068612 * (y - 1800)^2 +
            0.0041116 * (y - 1800)^3 - 0.00037436 * (y - 1800)^4 +
            0.0000121272 * (y - 1800)^5 - 0.0000001699 * (y - 1800)^6 +
            0.000000000875 * (y - 1800)^7
    ),
    (1860, 1900) => (
        y ->
            7.62 + 0.5737 * (y - 1860) - 0.251754 * (y - 1860)^2 +
            0.01680668 * (y - 1860)^3 - 0.0004473624 * (y - 1860)^4 +
            (y - 1860)^5 / 233174
    ),
    (1900, 1920) => (
        y ->
            -2.79 + 1.494119 * (y - 1900) - 0.0598939 * (y - 1900)^2 +
            0.0061966 * (y - 1900)^3 - 0.000197 * (y - 1900)^4
    ),
    (1920, 1941) => (
        y ->
            21.20 + 0.84493 * (y - 1920) - 0.076100 * (y - 1920)^2 +
            0.0020936 * (y - 1920)^3
    ),
    (1941, 1961) =>
        (y -> 29.07 + 0.407 * (y - 1950) - (y - 1950)^2 / 233 + (y - 1950)^3 / 2547),
    (1961, 1986) =>
        (y -> 45.45 + 1.067 * (y - 1975) - (y - 1975)^2 / 260 - (y - 1975)^3 / 718),
    (1986, 2005) => (
        y ->
            63.86 + 0.3345 * (y - 2000) - 0.060374 * (y - 2000)^2 +
            0.0017275 * (y - 2000)^3 +
            0.000651814 * (y - 2000)^4 +
            0.00002373599 * (y - 2000)^5
    ),
    (2005, 2050) => (y -> 62.92 + 0.32217 * (y - 2000) + 0.005589 * (y - 2000)^2),
    (2050, 2150) => (y -> -20 + 32 * ((y - 1820) / 100)^2 - 0.5628 * (2150 - y)),
    (2150, Inf) => (y -> -20 + 32 * ((y - 1820) / 100)^2),
]

"""
    $(TYPEDSIGNATURES)

Compute ΔT (Delta T), the difference between Terrestrial Dynamical Time (TD) and Universal Time (UT).

ΔT = TD - UT

This value is needed to convert between civil time (UT) and the uniform time scale used
in astronomical calculations (TD). The value changes over time due to variations in
Earth's rotation rate caused by tidal braking and other factors.

# Arguments
- `year::Real`: Calendar year (supports -1999 to 3000, with warnings outside this range)
- `month::Real`: Month as a real number (1-12, fractional values supported for interpolation)

# Returns
- `Float64`: ΔT in seconds

# Examples
```jldoctest
julia> using SolarPosition.Positioning: calculate_deltat

julia> calculate_deltat(2020, 6)
71.85030032812497

julia> using Dates

julia> calculate_deltat(Date(2020, 6, 15))
71.87173085145835

julia> calculate_deltat(DateTime(2020, 6, 15, 12, 30))
71.87173085145835
```

# Literature
The polynomial expressions for ΔT are from [NASADeltaT](@cite), based on the work by [MS04](@cite).
"""
function calculate_deltat(year::Real, month::Real)
    if year < -1999 || year > 3000
        @warn "ΔT is undefined for years before -1999 or after 3000." maxlog = 1
    end

    y = year + (month - 0.5) / 12

    for (range, f) in DELTAT_TABLE
        if first(range) <= year < last(range)
            return f(y)
        end
    end

    error("No ΔT function defined for year = $year")
end

function calculate_deltat(date::Union{DateTime,Date})
    y = year(date)
    m = month(date)
    d = day(date)
    days_in_month = daysinmonth(date)
    frac_month = m + (d - 1) / days_in_month
    return calculate_deltat(y, frac_month)
end

function calculate_deltat(datetime::ZonedDateTime)
    return calculate_deltat(DateTime(datetime, UTC))
end
