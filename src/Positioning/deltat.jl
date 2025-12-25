"""
Utility to calculate deltat.
"""

# ΔT table as a tuple of tuples for type stability
# Each entry is (lower_bound, upper_bound, function)
# Using a tuple instead of array ensures the compiler knows all types at compile time
const DELTAT_TABLE = (
    (-Inf, -500.0, y -> -20.0 + 32.0 * ((y - 1820.0) / 100.0)^2),
    (
        -500.0,
        500.0,
        y -> begin
            u = y / 100.0
            p = (
                10583.6,
                -1014.41,
                33.78311,
                -5.952053,
                -0.1798452,
                0.022174192,
                0.0090316521,
            )
            evalpoly(u, p)
        end,
    ),
    (
        500.0,
        1600.0,
        y -> begin
            u = (y - 1000.0) / 100.0
            p = (
                1574.2,
                -556.01,
                71.23472,
                0.319781,
                -0.8503463,
                -0.005050998,
                0.0083572073,
            )
            evalpoly(u, p)
        end,
    ),
    (1600.0, 1700.0, y -> begin
        t = y - 1600.0
        p = (120.0, -0.9808, -0.01532, inv(7129))
        evalpoly(t, p)
    end),
    (1700.0, 1800.0, y -> begin
            t = y - 1700.0
            p = (8.83, 0.1603, -0.0059285, 0.00013336, inv(-1174000))
            evalpoly(t, p)
        end),
    (
        1800.0,
        1860.0,
        y -> begin
            t = y - 1800.0
            p = (
                13.72,
                -0.332447,
                0.0068612,
                0.0041116,
                -0.00037436,
                0.0000121272,
                -0.0000001699,
                0.000000000875,
            )
            evalpoly(t, p)
        end,
    ),
    (
        1860.0,
        1900.0,
        y -> begin
            t = y - 1860.0
            p = (7.62, 0.5737, -0.251754, 0.01680668, -0.0004473624, inv(233174))
            evalpoly(t, p)
        end,
    ),
    (1900.0, 1920.0, y -> begin
        t = y - 1900.0
        p = (-2.79, 1.494119, -0.0598939, 0.0061966, -0.000197)
        evalpoly(t, p)
    end),
    (1920.0, 1941.0, y -> begin
        t = y - 1920.0
        p = (21.20, 0.84493, -0.076100, 0.0020936)
        evalpoly(t, p)
    end),
    (1941.0, 1961.0, y -> begin
        t = y - 1950.0
        p = (29.07, 0.407, inv(-233), inv(2547))
        evalpoly(t, p)
    end),
    (1961.0, 1986.0, y -> begin
        t = y - 1975.0
        p = (45.45, 1.067, inv(-260), inv(-718))
        evalpoly(t, p)
    end),
    (
        1986.0,
        2005.0,
        y -> begin
            t = y - 2000.0
            p = (63.86, 0.3345, -0.060374, 0.0017275, 0.000651814, 0.00002373599)
            evalpoly(t, p)
        end,
    ),
    (2005.0, 2050.0, y -> begin
        t = y - 2000.0
        p = (62.92, 0.32217, 0.005589)
        evalpoly(t, p)
    end),
    (2050.0, 2150.0, y -> -20.0 + 32.0 * ((y - 1820.0) / 100.0)^2 - 0.5628 * (2150.0 - y)),
    (2150.0, Inf, y -> -20.0 + 32.0 * ((y - 1820.0) / 100.0)^2),
)

# Recursive lookup for type-stable iteration over heterogeneous tuple
@inline _deltat_lookup(::Tuple{}, year::Real, y::Float64) =
    error("No ΔT function defined for year = $year")

@inline function _deltat_lookup(table::Tuple, year::Real, y::Float64)
    (lower, upper, f) = first(table)
    if lower <= year < upper
        return f(y)
    else
        return _deltat_lookup(Base.tail(table), year, y)
    end
end

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
```julia-repl
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
function calculate_deltat(year::Real, month::Real)::Float64
    if year < -1999 || year > 3000
        @warn "ΔT is undefined for years before -1999 or after 3000." maxlog = 1
    end

    y = Float64(year + (month - 0.5) / 12)

    return _deltat_lookup(DELTAT_TABLE, year, y)
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
