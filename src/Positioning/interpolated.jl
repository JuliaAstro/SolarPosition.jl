"""
    $(TYPEDEF)

Fast solar position from cubic B-spline interpolation of the geocentric solar
coordinates of a wrapped exact algorithm, currently [`SPA`](@ref).

The interpolant samples four observer independent quantities on a uniform time grid:
geocentric right ascension, geocentric declination, the Earth-Sun radius vector, and
the equation of the equinoxes. Sidereal time and the topocentric reconstruction stay
closed form and run through the exact same code as the wrapped algorithm, so the only
error is the spline interpolation error of the four smooth geocentric series. At the
default one hour grid spacing this error is far below the wrapped algorithm's own
accuracy.

One interpolant serves every observer, so a single instance can be shared across a
whole grid of sites and across threads.

Construction requires Interpolations.jl to be loaded:

    using Interpolations
    alg = Interpolated(SPA(); tspan = (DateTime(2024, 1, 1), DateTime(2025, 1, 1)))
    solar_position(obs, dt, alg)

# Arguments

- `algorithm::SPA = SPA()`: the exact algorithm to sample. Its `delta_t` setting is
  used during sampling. The default constant ΔT keeps the sampled series smooth; with
  `delta_t = nothing` the piecewise ΔT model introduces slope kinks that are far below
  the interpolation tolerance.
- `tspan::Tuple`: the valid query span as a pair of `DateTime` or `ZonedDateTime`.
  Zoned times are converted to UTC.
- `step::Period = Hour(1)`: the sampling grid spacing. Must be positive and at most 30
  days so that right ascension advances much less than half a turn per step. Steps
  above 3 days warn, because the interpolation error then exceeds the wrapped
  algorithm's own accuracy: measured against direct SPA the maximum error is about
  1e-10 degrees at `Hour(1)`, 4e-7 at `Day(1)`, 2e-4 at `Day(3)`, and 3e-2 at
  `Day(30)`.
- `out_of_range::Symbol = :error`: behaviour for queries outside `tspan`. `:error`
  throws an `ArgumentError`, `:fallback` silently calls the wrapped exact algorithm.

# Fields
$(TYPEDFIELDS)
"""
struct Interpolated{A <: SolarAlgorithm, ITP} <: SolarAlgorithm
    "Wrapped exact algorithm, used for sampling and the `:fallback` path"
    algorithm::A
    "Cubic B-spline of unwrapped geocentric right ascension in degrees vs days since J2000"
    itp_α::ITP
    "Cubic B-spline of geocentric declination in degrees"
    itp_δ::ITP
    "Cubic B-spline of the Earth-Sun radius vector in astronomical units"
    itp_R::ITP
    "Cubic B-spline of the equation of the equinoxes in degrees"
    itp_eqeq::ITP
    "Valid query span as UTC datetimes"
    tspan::Tuple{DateTime, DateTime}
    "Sampling grid spacing"
    step::Dates.Millisecond
    "Span start in days since J2000"
    t_min::Float64
    "Span end in days since J2000"
    t_max::Float64
    "Out of range behaviour, `:error` or `:fallback`"
    out_of_range::Symbol
end

function Interpolated(
        algorithm::SPA = SPA();
        tspan::Tuple{<:Union{DateTime, ZonedDateTime}, <:Union{DateTime, ZonedDateTime}},
        step::Dates.Period = Dates.Hour(1),
        out_of_range::Symbol = :error,
    )
    out_of_range in (:error, :fallback) || throw(
        ArgumentError("out_of_range must be :error or :fallback, got :$out_of_range"),
    )
    t0 = _as_utc(tspan[1])
    t1 = _as_utc(tspan[2])
    t0 < t1 || throw(ArgumentError("tspan must be increasing, got $t0 to $t1"))
    stepms = Dates.Millisecond(step)
    # the cap keeps the per step advance of right ascension far below half a turn,
    # which the unwrap during construction relies on
    Dates.Millisecond(0) < stepms <= Dates.Millisecond(Dates.Day(30)) ||
        throw(ArgumentError("step must be positive and at most 30 days, got $step"))
    # beyond 3 days the 13.7 day nutation ripple is sampled too coarsely and the
    # interpolation error exceeds the wrapped algorithm's own accuracy
    stepms > Dates.Millisecond(Dates.Day(3)) && @warn(
        "Interpolated with step = $step has an interpolation error above the wrapped " *
            "algorithm's own accuracy. Use a step of 3 days or less to stay below it.",
    )
    (itp_α, itp_δ, itp_R, itp_eqeq) = _build_interpolants(algorithm, t0, t1, stepms)
    return Interpolated(
        algorithm, itp_α, itp_δ, itp_R, itp_eqeq, (t0, t1), stepms,
        julian_day_j2000(Float64, t0), julian_day_j2000(Float64, t1), out_of_range,
    )
end

_as_utc(dt::DateTime) = dt
_as_utc(zdt::ZonedDateTime) = DateTime(zdt, UTC)

# Extension hook. SolarPositionInterpolationsExt defines the working method for SPA;
# this fallback exists so construction without the extension fails with a clear message.
function _build_interpolants(
        ::SolarAlgorithm, ::DateTime, ::DateTime, ::Dates.Millisecond,
    )
    throw(
        ArgumentError(
            "constructing Interpolated requires Interpolations.jl. " *
                "Run `using Interpolations` and try again.",
        ),
    )
end

function Base.show(io::IO, alg::Interpolated)
    print(
        io, "Interpolated(", alg.algorithm, "; tspan = ", alg.tspan,
        ", step = ", Dates.canonicalize(alg.step),
        ", out_of_range = :", alg.out_of_range, ")",
    )
    return nothing
end

function _solar_position(
        obs::SPAObserver{T},
        dt::DateTime,
        alg::Interpolated,
    ) where {T <: Real}
    t = julian_day_j2000(Float64, dt)
    if !(alg.t_min <= t <= alg.t_max)
        alg.out_of_range === :fallback && return _solar_position(obs, dt, alg.algorithm)
        throw(
            ArgumentError(
                "$dt is outside the interpolated span $(alg.tspan[1]) to " *
                    "$(alg.tspan[2]). Widen tspan or use out_of_range = :fallback.",
            ),
        )
    end

    # interpolated geocentric state, right ascension rewrapped to [0, 360)
    α = mod(alg.itp_α(t), 360.0)
    δ = alg.itp_δ(t)
    R = alg.itp_R(t)
    eqeq = alg.itp_eqeq(t)

    # apparent sidereal time stays closed form and magnitude safe
    (n_int, n_frac) = julian_day_j2000_split(Float64, dt)
    jc = (n_int + n_frac) / 36525.0
    ν = mean_sidereal_time(n_int, n_frac, jc) + eqeq

    return _spa_topocentric(obs, T(ν), T(α), T(δ), T(R))
end

function _solar_position(obs::Observer{T}, dt::DateTime, alg::Interpolated) where {T <: Real}
    spa_obs = SPAObserver{T}(obs.latitude, obs.longitude, obs.altitude)
    return _solar_position(spa_obs, dt, alg)
end

# DefaultRefraction resolves exactly as it does for the wrapped SPA
function _solar_position(
        obs::AbstractObserver{T},
        dt,
        alg::Interpolated,
        ::DefaultRefraction,
    ) where {T <: Real}
    spa = alg.algorithm
    return _solar_position(
        obs,
        dt,
        alg,
        SPARefraction{T}(
            pressure = T(spa.pressure),
            temperature = T(spa.temperature),
            atmos_refract = T(spa.atmos_refract),
        ),
    )
end

function solar_position!(
        pos::StructArrays.StructVector{S},
        obs::AbstractObserver{T},
        dts::AbstractVector{DateTime},
        alg::Interpolated,
        refraction::RefractionAlgorithm = DefaultRefraction(),
    ) where {S <: AbstractSolPos, T <: Real}
    spa_obs = SPAObserver{T}(obs.latitude, obs.longitude, obs.altitude)
    @inbounds for i in eachindex(dts, pos)
        pos[i] = solar_position(spa_obs, dts[i], alg, refraction)
    end
    return pos
end

# Interpolated mirrors SPA: SolPos with NoRefraction, ApparentSolPos with any refraction
result_type(::Type{<:Interpolated}, ::Type{NoRefraction}, ::Type{T}) where {T} = SolPos{T}
result_type(::Type{<:Interpolated}, ::Type{<:RefractionAlgorithm}, ::Type{T}) where {T} =
    ApparentSolPos{T}

"""
    $(TYPEDSIGNATURES)

Rate of change of solar azimuth and elevation in degrees per hour at `dt`, computed
with a central finite difference of one second half width over the interpolated
position. Returns a named tuple `(dazimuth_dt, delevation_dt)`. The azimuth difference
is wrap aware, so the rate is continuous across the 0/360 degree crossing.

`dt` must be at least one second inside the interpolated span, unless the algorithm
was constructed with `out_of_range = :fallback`.
"""
function solar_rate(
        obs::AbstractObserver{T},
        dt::DateTime,
        alg::Interpolated,
    ) where {T <: Real}
    spa_obs = SPAObserver{T}(obs.latitude, obs.longitude, obs.altitude)
    p1 = _solar_position(spa_obs, dt - Dates.Second(1), alg)
    p2 = _solar_position(spa_obs, dt + Dates.Second(1), alg)
    # 1800 converts the difference over a two second baseline to degrees per hour
    daz = mod(p2.azimuth - p1.azimuth + 180, 360) - 180
    return (dazimuth_dt = daz * 1800, delevation_dt = (p2.elevation - p1.elevation) * 1800)
end

function solar_rate(obs::AbstractObserver, dt::ZonedDateTime, alg::Interpolated)
    return solar_rate(obs, DateTime(dt, UTC), alg)
end
