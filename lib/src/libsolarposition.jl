"""
C and Python facing surface over SolarPosition.jl, compiled with `juliac --trim`.

Every positioning algorithm and every refraction model is reachable. Algorithm and
refraction are selected by enum, which JuliaLibWrapping renders as a Python `IntEnum` and
validates on the way in, and their options ride along as keyword arguments.

Two conventions keep the compiled path narrow. Time crosses the boundary as Unix seconds
rather than a `DateTime`, so nothing here touches TimeZones.jl. Every entrypoint returns
all five angles, with `apparent_*` equal to the true values when no refraction applies, so
the return type does not vary with the `SolPos`/`ApparentSolPos` split that
`SolarPosition.result_type` produces — that uniformity is what lets each dispatch arm stay
inferable under `--trim`.
"""
module libsolarposition

using Dates: datetime2unix, unix2datetime
using JLWInterop: @api, @export_release_entrypoints, JLWInterop
import SolarPosition as SP
import SolarPosition.Refraction as SPR

# The two enums live in nested modules because `@enum` binds its members in the enclosing
# module, and `MICHALSKY` and `SPA` each name both an algorithm and a refraction model.
# Only the types and the two default members are imported, which is enough for `@api` to
# resolve a bare member name as a keyword default.
module AlgorithmEnums
    @enum Algorithm::Int32 PSA NOAA SPA WALRAVEN USNO IQBAL MICHALSKY
end

module RefractionEnums
    @enum RefractionModel::Int32 DEFAULT NONE HUGHES ARCHER BENNETT MICHALSKY SG2 SPA
end

using .AlgorithmEnums: Algorithm, PSA
using .RefractionEnums: DEFAULT, RefractionModel

"Julian date formulation for the Michalsky algorithm."
@enum JulianDateMode::Int32 ORIGINAL STANDARD

"""
Solar angles in degrees. `apparent_elevation` and `apparent_zenith` equal `elevation` and
`zenith` when the selected refraction model applies no correction.
"""
struct SolarAngles
    azimuth::Float64
    elevation::Float64
    zenith::Float64
    apparent_elevation::Float64
    apparent_zenith::Float64
end

# An isbits struct is its own carrier, so all three hooks are the identity.
JLWInterop.carrier_type(::Type{SolarAngles}) = SolarAngles
JLWInterop.to_carrier(a::SolarAngles) = a
JLWInterop.from_carrier(::Type{SolarAngles}, a::SolarAngles) = a

# Algorithm and refraction options, bundled so the dispatch helpers take one argument
# instead of a dozen. Never crosses the ABI.
struct Opts
    pressure::Float64
    temperature::Float64
    delta_t::Union{Float64, Nothing}
    atmos_refract::Float64
    refraction_limit::Float64
    psa_coeffs::Int64
    gmst_option::Int64
    spencer_correction::Bool
    julian_date::JulianDateMode
end

_angles(p::SP.SolPos) =
    SolarAngles(p.azimuth, p.elevation, p.zenith, p.elevation, p.zenith)
_angles(p::SP.ApparentSolPos) = SolarAngles(
    p.azimuth, p.elevation, p.zenith, p.apparent_elevation, p.apparent_zenith,
)

# Geometric position, refraction deliberately switched off. One arm per algorithm; each
# arm constructs a concrete algorithm type, so the branch is on a value and every call is
# statically dispatched. All arms return `SolPos{Float64}`.
@inline function _geometric(a::Algorithm, o::Opts, obs::SP.Observer{Float64}, dt)
    return if a === AlgorithmEnums.PSA
        SP.solar_position(obs, dt, SP.PSA(o.psa_coeffs), SPR.NoRefraction())
    elseif a === AlgorithmEnums.NOAA
        SP.solar_position(obs, dt, SP.NOAA(o.delta_t), SPR.NoRefraction())
    elseif a === AlgorithmEnums.SPA
        SP.solar_position(
            obs, dt,
            SP.SPA(o.delta_t, o.pressure, o.temperature, o.atmos_refract),
            SPR.NoRefraction(),
        )
    elseif a === AlgorithmEnums.WALRAVEN
        SP.solar_position(obs, dt, SP.Walraven(), SPR.NoRefraction())
    elseif a === AlgorithmEnums.USNO
        SP.solar_position(obs, dt, SP.USNO(o.delta_t, o.gmst_option), SPR.NoRefraction())
    elseif a === AlgorithmEnums.IQBAL
        SP.solar_position(obs, dt, SP.Iqbal(), SPR.NoRefraction())
    else
        jd = o.julian_date === ORIGINAL ? :original : :standard
        SP.solar_position(
            obs, dt, SP.Michalsky(o.spencer_correction, jd), SPR.NoRefraction(),
        )
    end
end

# Refraction correction in degrees, to be added to the true elevation. This mirrors what
# `Positioning._solar_position(obs, dt, alg, refraction)` does internally, which is why
# the algorithm and refraction branches can be separate rather than a 7x8 cross product.
@inline function _refraction_correction(r::RefractionModel, o::Opts, elevation::Float64)
    return if r === RefractionEnums.HUGHES
        SPR.refraction(SPR.HUGHES(o.pressure, o.temperature), elevation)
    elseif r === RefractionEnums.ARCHER
        SPR.refraction(SPR.ARCHER(), elevation)
    elseif r === RefractionEnums.BENNETT
        SPR.refraction(SPR.BENNETT(o.pressure, o.temperature), elevation)
    elseif r === RefractionEnums.MICHALSKY
        SPR.refraction(SPR.MICHALSKY(), elevation)
    elseif r === RefractionEnums.SG2
        SPR.refraction(SPR.SG2(o.pressure, o.temperature), elevation)
    else
        SPR.refraction(
            SPR.SPARefraction(o.pressure, o.temperature, o.refraction_limit), elevation,
        )
    end
end

# `DefaultRefraction` resolves per algorithm inside the package, and SPA's default path
# feeds the SPA struct's own pressure, temperature and atmos_refract fields, so it cannot
# be rebuilt from the decoupled form above. Delegate to the package instead.
@inline function _default_refraction(a::Algorithm, o::Opts, obs::SP.Observer{Float64}, dt)
    return if a === AlgorithmEnums.PSA
        _angles(SP.solar_position(obs, dt, SP.PSA(o.psa_coeffs)))
    elseif a === AlgorithmEnums.NOAA
        _angles(SP.solar_position(obs, dt, SP.NOAA(o.delta_t)))
    elseif a === AlgorithmEnums.SPA
        _angles(
            SP.solar_position(
                obs, dt, SP.SPA(o.delta_t, o.pressure, o.temperature, o.atmos_refract),
            ),
        )
    elseif a === AlgorithmEnums.WALRAVEN
        _angles(SP.solar_position(obs, dt, SP.Walraven()))
    elseif a === AlgorithmEnums.USNO
        _angles(SP.solar_position(obs, dt, SP.USNO(o.delta_t, o.gmst_option)))
    elseif a === AlgorithmEnums.IQBAL
        _angles(SP.solar_position(obs, dt, SP.Iqbal()))
    else
        jd = o.julian_date === ORIGINAL ? :original : :standard
        _angles(SP.solar_position(obs, dt, SP.Michalsky(o.spencer_correction, jd)))
    end
end

@inline function _compute(
        obs::SP.Observer{Float64}, dt, a::Algorithm, r::RefractionModel, o::Opts,
    )
    r === DEFAULT && return _default_refraction(a, o, obs, dt)
    pos = _geometric(a, o, obs, dt)
    # With no refraction there is no correction, and the package returns a plain `SolPos`.
    # Pass its own zenith through rather than recomputing `90 - elevation`, which differs
    # in the last bit for the algorithms that derive elevation from zenith.
    r === RefractionEnums.NONE && return _angles(pos)
    apparent_elevation = pos.elevation + _refraction_correction(r, o, pos.elevation)
    return SolarAngles(
        pos.azimuth, pos.elevation, pos.zenith,
        apparent_elevation, 90.0 - apparent_elevation,
    )
end

"""
Solar position for one instant.

`unix_seconds` is seconds since the Unix epoch, UTC. `latitude` is positive north and
`longitude` positive east, both in degrees, and `altitude` is metres above mean sea level.

`pressure` [Pa] and `temperature` [°C] feed the refraction models that take them, and the
SPA algorithm. `delta_t` [s] is the difference between terrestrial time and UT1; pass
`None` to have it computed from the date. The remaining keywords are algorithm options:
`atmos_refract` and `psa_coeffs` for SPA and PSA, `gmst_option` for USNO, and
`spencer_correction` and `julian_date` for Michalsky. `refraction_limit` is
SPARefraction's own refraction limit.
"""
function solar_position_single(
        latitude::Float64,
        longitude::Float64,
        unix_seconds::Float64;
        altitude::Float64 = 0.0,
        algorithm::Algorithm = PSA,
        refraction::RefractionModel = DEFAULT,
        pressure::Float64 = 101325.0,
        temperature::Float64 = 12.0,
        delta_t::Union{Float64, Nothing} = 67.0,
        atmos_refract::Float64 = 0.5667,
        refraction_limit::Float64 = -0.5667,
        psa_coeffs::Int64 = 2020,
        gmst_option::Int64 = 1,
        spencer_correction::Bool = true,
        julian_date::JulianDateMode = ORIGINAL,
    )
    obs = SP.Observer(latitude, longitude, altitude)
    o = Opts(
        pressure, temperature, delta_t, atmos_refract, refraction_limit,
        psa_coeffs, gmst_option, spencer_correction, julian_date,
    )
    return _compute(obs, unix2datetime(unix_seconds), algorithm, refraction, o)
end

@api solar_position_single(
    latitude::Float64,
    longitude::Float64,
    unix_seconds::Float64;
    altitude::Float64 = 0.0,
    algorithm::Algorithm = PSA,
    refraction::RefractionModel = DEFAULT,
    pressure::Float64 = 101325.0,
    temperature::Float64 = 12.0,
    delta_t::Union{Float64, Nothing} = 67.0,
    atmos_refract::Float64 = 0.5667,
    refraction_limit::Float64 = -0.5667,
    psa_coeffs::Int64 = 2020,
    gmst_option::Int64 = 1,
    spencer_correction::Bool = true,
    julian_date::JulianDateMode = ORIGINAL,
)::SolarAngles

"""
Solar position for many instants, written into caller-allocated output buffers.

The five output arrays must each hold at least `length(unix_seconds)` elements. They are
borrowed, so the writes land directly in the caller's numpy arrays and nothing is
allocated. The observer is built once and only read, so this is also the form the threaded
entrypoint parallelises. See `solar_position_single` for the keyword arguments.
"""
function solar_position_inplace(
        latitude::Float64,
        longitude::Float64,
        unix_seconds::Vector{Float64},
        azimuth::Vector{Float64},
        elevation::Vector{Float64},
        zenith::Vector{Float64},
        apparent_elevation::Vector{Float64},
        apparent_zenith::Vector{Float64};
        altitude::Float64 = 0.0,
        algorithm::Algorithm = PSA,
        refraction::RefractionModel = DEFAULT,
        pressure::Float64 = 101325.0,
        temperature::Float64 = 12.0,
        delta_t::Union{Float64, Nothing} = 67.0,
        atmos_refract::Float64 = 0.5667,
        refraction_limit::Float64 = -0.5667,
        psa_coeffs::Int64 = 2020,
        gmst_option::Int64 = 1,
        spencer_correction::Bool = true,
        julian_date::JulianDateMode = ORIGINAL,
    )
    n = length(unix_seconds)
    if length(azimuth) < n || length(elevation) < n || length(zenith) < n ||
            length(apparent_elevation) < n || length(apparent_zenith) < n
        throw(DimensionMismatch("output buffers are shorter than the input"))
    end
    obs = SP.Observer(latitude, longitude, altitude)
    o = Opts(
        pressure, temperature, delta_t, atmos_refract, refraction_limit,
        psa_coeffs, gmst_option, spencer_correction, julian_date,
    )
    for i in 1:n
        a = _compute(obs, unix2datetime(unix_seconds[i]), algorithm, refraction, o)
        azimuth[i] = a.azimuth
        elevation[i] = a.elevation
        zenith[i] = a.zenith
        apparent_elevation[i] = a.apparent_elevation
        apparent_zenith[i] = a.apparent_zenith
    end
    return nothing
end

@api solar_position_inplace(
    latitude::Float64,
    longitude::Float64,
    unix_seconds::Vector{Float64},
    azimuth::Vector{Float64},
    elevation::Vector{Float64},
    zenith::Vector{Float64},
    apparent_elevation::Vector{Float64},
    apparent_zenith::Vector{Float64};
    altitude::Float64 = 0.0,
    algorithm::Algorithm = PSA,
    refraction::RefractionModel = DEFAULT,
    pressure::Float64 = 101325.0,
    temperature::Float64 = 12.0,
    delta_t::Union{Float64, Nothing} = 67.0,
    atmos_refract::Float64 = 0.5667,
    refraction_limit::Float64 = -0.5667,
    psa_coeffs::Int64 = 2020,
    gmst_option::Int64 = 1,
    spencer_correction::Bool = true,
    julian_date::JulianDateMode = ORIGINAL,
)::Nothing

"""
Solar position for many instants, returned as a freshly allocated `n x 5` matrix.

The columns are azimuth, elevation, zenith, apparent elevation and apparent zenith. An
owning array return transfers the allocation to the caller, so this is the convenient form
rather than the fast one; use `solar_position_inplace` to write into buffers you
already hold. See `solar_position_single` for the keyword arguments.
"""
function solar_position(
        latitude::Float64,
        longitude::Float64,
        unix_seconds::Vector{Float64};
        altitude::Float64 = 0.0,
        algorithm::Algorithm = PSA,
        refraction::RefractionModel = DEFAULT,
        pressure::Float64 = 101325.0,
        temperature::Float64 = 12.0,
        delta_t::Union{Float64, Nothing} = 67.0,
        atmos_refract::Float64 = 0.5667,
        refraction_limit::Float64 = -0.5667,
        psa_coeffs::Int64 = 2020,
        gmst_option::Int64 = 1,
        spencer_correction::Bool = true,
        julian_date::JulianDateMode = ORIGINAL,
    )
    n = length(unix_seconds)
    obs = SP.Observer(latitude, longitude, altitude)
    o = Opts(
        pressure, temperature, delta_t, atmos_refract, refraction_limit,
        psa_coeffs, gmst_option, spencer_correction, julian_date,
    )
    out = Matrix{Float64}(undef, n, 5)
    for i in 1:n
        a = _compute(obs, unix2datetime(unix_seconds[i]), algorithm, refraction, o)
        out[i, 1] = a.azimuth
        out[i, 2] = a.elevation
        out[i, 3] = a.zenith
        out[i, 4] = a.apparent_elevation
        out[i, 5] = a.apparent_zenith
    end
    return out
end

@api solar_position(
    latitude::Float64,
    longitude::Float64,
    unix_seconds::Vector{Float64};
    altitude::Float64 = 0.0,
    algorithm::Algorithm = PSA,
    refraction::RefractionModel = DEFAULT,
    pressure::Float64 = 101325.0,
    temperature::Float64 = 12.0,
    delta_t::Union{Float64, Nothing} = 67.0,
    atmos_refract::Float64 = 0.5667,
    refraction_limit::Float64 = -0.5667,
    psa_coeffs::Int64 = 2020,
    gmst_option::Int64 = 1,
    spencer_correction::Bool = true,
    julian_date::JulianDateMode = ORIGINAL,
)::Matrix{Float64}

# ----------------------------------------------------------- sunrise, sunset, transit
#
# These take no algorithm selector. `Utilities._transit_sunrise_sunset` is only defined
# for `alg::SPA` — the wider `SolarAlgorithm` bound on the public signature has no other
# implementation — so the SPA options are exposed directly instead.

"Which solar event to locate."
@enum SunEvent::Int32 SUNRISE SUNSET SOLAR_NOON

"Search forwards or backwards in time."
@enum EventDirection::Int32 NEXT PREVIOUS

"""
Solar transit, sunrise and sunset as seconds since midnight UTC.

All three can exceed 86400 or go negative when the event falls outside the UTC day that
contains the requested instant.
"""
struct SunEvents
    transit::Float64
    sunrise::Float64
    sunset::Float64
end

JLWInterop.carrier_type(::Type{SunEvents}) = SunEvents
JLWInterop.to_carrier(e::SunEvents) = e
JLWInterop.from_carrier(::Type{SunEvents}, e::SunEvents) = e

"""
Solar transit, sunrise and sunset for the UTC day containing `unix_seconds`.

Declared with positional arguments: reached through `@api`'s keyword-argument wrapper the
`juliac --trim` verifier cannot resolve the call ("unresolved call from statement
Core.kwcall(...)"). `sun_event` keeps its keywords because it goes through the package's
`DateTime` path, which takes a different `_frac_to_event` specialisation. The keyword-only
Python signature is restored by hand in `lib/python/_extras.py`.

Returned as seconds since midnight UTC of that day, which is the form that keeps full
precision — the `DateTime` variant in the Julia package rounds to a whole second.

Computed with SPA, so `delta_t`, `pressure`, `temperature` and `atmos_refract` are SPA's
own options.

There is deliberately no `horizon` parameter. `src/Utilities/spa.jl` hardcodes the
horizon depression to -0.8333 degrees and never reads `Observer.horizon`, so a parameter
here would be silently ignored — which matters most for exactly the case someone would
reach for it, such as civil twilight. Add one once the package honours the field.

At latitudes in polar day or polar night there is no sunrise or sunset. The underlying
package warns on stderr and returns zero for all three fields in that case.
"""
function transit_sunrise_sunset(
        latitude::Float64,
        longitude::Float64,
        unix_seconds::Float64,
        altitude::Float64,
        pressure::Float64,
        temperature::Float64,
        delta_t::Union{Float64, Nothing},
        atmos_refract::Float64,
    )
    obs = SP.Observer(latitude, longitude, altitude)
    alg = SP.SPA(delta_t, pressure, temperature, atmos_refract)
    r = SP.transit_sunrise_sunset_seconds(obs, unix2datetime(unix_seconds), alg)
    return SunEvents(r.transit, r.sunrise, r.sunset)
end

@api transit_sunrise_sunset(
    latitude::Float64,
    longitude::Float64,
    unix_seconds::Float64,
    altitude::Float64,
    pressure::Float64,
    temperature::Float64,
    delta_t::Union{Float64, Nothing},
    atmos_refract::Float64,
)::SunEvents

"""
The next or previous sunrise, sunset or solar noon, as Unix seconds.

`event` selects sunrise, sunset or solar noon and `direction` selects whether to search
forward or backward from `unix_seconds`. The result is rounded to a whole second, because
the underlying package returns a `DateTime`; use `transit_sunrise_sunset` when the
sub-second part matters. See `transit_sunrise_sunset` for the keyword arguments.
"""
function sun_event(
        latitude::Float64,
        longitude::Float64,
        unix_seconds::Float64,
        event::SunEvent,
        direction::EventDirection;
        altitude::Float64 = 0.0,
        pressure::Float64 = 101325.0,
        temperature::Float64 = 12.0,
        delta_t::Union{Float64, Nothing} = 67.0,
        atmos_refract::Float64 = 0.5667,
    )
    obs = SP.Observer(latitude, longitude, altitude)
    alg = SP.SPA(delta_t, pressure, temperature, atmos_refract)
    dt = unix2datetime(unix_seconds)
    # Each arm calls a package function that passes a constant field symbol down to
    # `_next_event`/`_previous_event`, so nothing dispatches on a runtime Symbol.
    result = if direction === NEXT
        if event === SUNRISE
            SP.next_sunrise(obs, dt, alg)
        elseif event === SUNSET
            SP.next_sunset(obs, dt, alg)
        else
            SP.next_solar_noon(obs, dt, alg)
        end
    else
        if event === SUNRISE
            SP.previous_sunrise(obs, dt, alg)
        elseif event === SUNSET
            SP.previous_sunset(obs, dt, alg)
        else
            SP.previous_solar_noon(obs, dt, alg)
        end
    end
    return datetime2unix(result)
end

@api sun_event(
    latitude::Float64,
    longitude::Float64,
    unix_seconds::Float64,
    event::SunEvent,
    direction::EventDirection;
    altitude::Float64 = 0.0,
    pressure::Float64 = 101325.0,
    temperature::Float64 = 12.0,
    delta_t::Union{Float64, Nothing} = 67.0,
    atmos_refract::Float64 = 0.5667,
)::Float64

"""
The number of Julia threads this library was compiled with.

The thread count is fixed when the library is built and cannot be changed at load time, so
this is how a caller finds out whether it has a threaded build. A value of 1 means
`solar_position_inplace_threaded` runs serially.
"""
julia_nthreads() = Int64(Threads.nthreads())

@api julia_nthreads()::Int64

# A function barrier for the parallel loop. `Threads.@threads` builds a closure, and
# through `@api`'s keyword-argument wrapper the trim verifier cannot resolve the resulting
# `kwcall` ("unresolved call from statement Core.kwcall(...)"). Taking every value as a
# positional argument of concrete type keeps the loop inferable and the entrypoint
# trimmable.
function _fill_threaded!(
        obs::SP.Observer{Float64},
        n::Int,
        unix_seconds::Vector{Float64},
        azimuth::Vector{Float64},
        elevation::Vector{Float64},
        zenith::Vector{Float64},
        apparent_elevation::Vector{Float64},
        apparent_zenith::Vector{Float64},
        algorithm::Algorithm,
        refraction::RefractionModel,
        o::Opts,
    )
    Threads.@threads for i in 1:n
        a = _compute(obs, unix2datetime(unix_seconds[i]), algorithm, refraction, o)
        azimuth[i] = a.azimuth
        elevation[i] = a.elevation
        zenith[i] = a.zenith
        apparent_elevation[i] = a.apparent_elevation
        apparent_zenith[i] = a.apparent_zenith
    end
    return nothing
end

"""
Threaded `solar_position_inplace`, using the threads the library was compiled with.

The work is embarrassingly parallel: the observer is built once and only read, and each
iteration writes its own index in the caller's buffers. With a single-threaded build this
is just the serial loop. See `solar_position_single` for the keyword arguments.
"""
function solar_position_inplace_threaded(
        latitude::Float64,
        longitude::Float64,
        unix_seconds::Vector{Float64},
        azimuth::Vector{Float64},
        elevation::Vector{Float64},
        zenith::Vector{Float64},
        apparent_elevation::Vector{Float64},
        apparent_zenith::Vector{Float64},
        altitude::Float64,
        algorithm::Algorithm,
        refraction::RefractionModel,
        pressure::Float64,
        temperature::Float64,
        delta_t::Union{Float64, Nothing},
        atmos_refract::Float64,
        refraction_limit::Float64,
        psa_coeffs::Int64,
        gmst_option::Int64,
        spencer_correction::Bool,
        julian_date::JulianDateMode,
    )
    n = length(unix_seconds)
    if length(azimuth) < n || length(elevation) < n || length(zenith) < n ||
            length(apparent_elevation) < n || length(apparent_zenith) < n
        throw(DimensionMismatch("output buffers are shorter than the input"))
    end
    obs = SP.Observer(latitude, longitude, altitude)
    o = Opts(
        pressure, temperature, delta_t, atmos_refract, refraction_limit,
        psa_coeffs, gmst_option, spencer_correction, julian_date,
    )
    _fill_threaded!(
        obs, n, unix_seconds, azimuth, elevation, zenith,
        apparent_elevation, apparent_zenith, algorithm, refraction, o,
    )
    return nothing
end

@api solar_position_inplace_threaded(
    latitude::Float64,
    longitude::Float64,
    unix_seconds::Vector{Float64},
    azimuth::Vector{Float64},
    elevation::Vector{Float64},
    zenith::Vector{Float64},
    apparent_elevation::Vector{Float64},
    apparent_zenith::Vector{Float64},
    altitude::Float64,
    algorithm::Algorithm,
    refraction::RefractionModel,
    pressure::Float64,
    temperature::Float64,
    delta_t::Union{Float64, Nothing},
    atmos_refract::Float64,
    refraction_limit::Float64,
    psa_coeffs::Int64,
    gmst_option::Int64,
    spencer_correction::Bool,
    julian_date::JulianDateMode,
)::Nothing

# `solar_position` hands an owned array to the caller, so the generated bindings
# need the release entrypoints to give it back.
@export_release_entrypoints

end # module
