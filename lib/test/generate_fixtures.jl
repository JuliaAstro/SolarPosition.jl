#!/usr/bin/env julia
#
# Emit lib/test/fixtures.json, the reference data the pytest suite compares against.
#
#     julia --project=test lib/test/generate_fixtures.jl
#
# Two independent sets of numbers go in:
#
#   "reference" — the solposx tables from test/positioning/expected-values.jl, on the
#   84.375 s grid so the full Julian Date is exactly representable in Float64. These are
#   the authoritative cross-implementation values and are what catches a real numeric
#   regression in the compiled library.
#
#   "package" — what this checkout of SolarPosition.jl itself returns for every
#   algorithm x refraction pair at the same instants. Comparing against these catches
#   anything that `juliac --trim` changed about the numerics, at full Float64 precision.

using Dates: DateTime, datetime2unix
using TimeZones: ZonedDateTime, UTC
using SolarPosition

const REPO = dirname(dirname(@__DIR__))
include(joinpath(REPO, "test", "positioning", "expected-values.jl"))

# Minimal JSON writer. The fixture is only numbers, strings and nested containers, and
# `string(::Float64)` already emits the shortest round-tripping form, so this avoids
# adding a JSON dependency to the test project.
jsonesc(s) = replace(string(s), '\\' => "\\\\", '"' => "\\\"")
tojson(x::AbstractString) = string('"', jsonesc(x), '"')
tojson(x::Bool) = x ? "true" : "false"
tojson(::Nothing) = "null"
tojson(::Missing) = "null"
tojson(x::Integer) = string(x)
function tojson(x::AbstractFloat)
    isfinite(x) || error("non-finite value in fixture: $x")
    return string(Float64(x))
end
tojson(v::AbstractVector) = string('[', join(map(tojson, v), ','), ']')
tojson(d::AbstractDict) =
    string('{', join(("$(tojson(string(k))):$(tojson(v))" for (k, v) in d), ','), '}')

const ALGORITHMS = [
    "PSA" => PSA(),
    "NOAA" => NOAA(),
    "SPA" => SPA(),
    "WALRAVEN" => Walraven(),
    "USNO" => USNO(),
    "IQBAL" => Iqbal(),
    "MICHALSKY" => Michalsky(),
]

# Pressure, temperature, and SPARefraction's refraction limit must match the defaults the
# Python entrypoints use, or the comparison is meaningless.
const PRESSURE, TEMPERATURE, REFRACTION_LIMIT = 101325.0, 12.0, -0.5667

const REFRACTIONS = [
    "DEFAULT" => DefaultRefraction(),
    "NONE" => NoRefraction(),
    "HUGHES" => HUGHES(PRESSURE, TEMPERATURE),
    "ARCHER" => ARCHER(),
    "BENNETT" => BENNETT(PRESSURE, TEMPERATURE),
    "MICHALSKY" => MICHALSKY(),
    "SG2" => SG2(PRESSURE, TEMPERATURE),
    "SPA" => SPARefraction(PRESSURE, TEMPERATURE, REFRACTION_LIMIT),
]

apparent(p::SolPos) = (p.elevation, p.zenith)
apparent(p::ApparentSolPos) = (p.apparent_elevation, p.apparent_zenith)

function main()
    conds = test_conditions()

    times, lats, lons, alts = Float64[], Float64[], Float64[], Float64[]
    datetimes = DateTime[]
    for (t, lat, lon, alt) in zip(conds.time, conds.latitude, conds.longitude, conds.altitude)
        dt = DateTime(t, UTC)   # `test_conditions` already parsed these to ZonedDateTime
        push!(datetimes, dt)
        push!(times, datetime2unix(dt))
        push!(lats, Float64(lat))
        push!(lons, Float64(lon))
        push!(alts, ismissing(alt) ? 0.0 : Float64(alt))
    end

    # The solposx reference tables. Each carries the call that reproduces it and its own
    # column names, because the tables are not uniform: NOAA is validated against
    # HUGHES at temperature 10.0 rather than the 12.0 default, USNO has two GMST
    # variants, and SPA compares at 1e-8 with an extra column this API does not expose.
    # The specs mirror test/positioning/test-*.jl exactly.
    reference_specs = [
        (
            name = "PSA_2020", table = expected_2020, algorithm = "PSA",
            refraction = "DEFAULT", psa_coeffs = 2020, gmst_option = 1,
            temperature = TEMPERATURE, atol = 1.0e-10, skip_poles = false,
        ),
        (
            name = "PSA_2001", table = expected_2001, algorithm = "PSA",
            refraction = "DEFAULT", psa_coeffs = 2001, gmst_option = 1,
            temperature = TEMPERATURE, atol = 1.0e-10, skip_poles = false,
        ),
        (
            name = "NOAA", table = expected_noaa, algorithm = "NOAA",
            refraction = "HUGHES", psa_coeffs = 2020, gmst_option = 1,
            temperature = 10.0, atol = 1.0e-10, skip_poles = true,
        ),
        (
            name = "WALRAVEN", table = expected_walraven, algorithm = "WALRAVEN",
            refraction = "DEFAULT", psa_coeffs = 2020, gmst_option = 1,
            temperature = TEMPERATURE, atol = 1.0e-10, skip_poles = false,
        ),
        (
            name = "USNO", table = expected_usno, algorithm = "USNO",
            refraction = "DEFAULT", psa_coeffs = 2020, gmst_option = 1,
            temperature = TEMPERATURE, atol = 1.0e-10, skip_poles = false,
        ),
        (
            name = "USNO_OPTION_2", table = expected_usno_option_2, algorithm = "USNO",
            refraction = "DEFAULT", psa_coeffs = 2020, gmst_option = 2,
            temperature = TEMPERATURE, atol = 1.0e-10, skip_poles = false,
        ),
        (
            name = "SPA", table = expected_spa, algorithm = "SPA",
            refraction = "DEFAULT", psa_coeffs = 2020, gmst_option = 1,
            temperature = TEMPERATURE, atol = 1.0e-8, skip_poles = false,
        ),
        (
            name = "IQBAL", table = expected_iqbal, algorithm = "IQBAL",
            refraction = "DEFAULT", psa_coeffs = 2020, gmst_option = 1,
            temperature = TEMPERATURE, atol = 1.0e-10, skip_poles = false,
        ),
    ]

    reference = Dict{String, Any}()
    for s in reference_specs
        df = s.table()
        reference[s.name] = Dict{String, Any}(
            "algorithm" => s.algorithm,
            "refraction" => s.refraction,
            "psa_coeffs" => s.psa_coeffs,
            "gmst_option" => s.gmst_option,
            "temperature" => s.temperature,
            "atol" => s.atol,
            "skip_poles" => s.skip_poles,
            "columns" => String.(names(df)),
            "rows" => [[Float64(v) for v in r] for r in eachrow(df)],
        )
    end

    # This checkout's own output for every algorithm x refraction pair, as
    # (azimuth, elevation, zenith, apparent_elevation, apparent_zenith).
    package = Dict{String, Any}()
    for (aname, alg) in ALGORITHMS, (rname, refr) in REFRACTIONS
        rows = Vector{Vector{Float64}}(undef, length(datetimes))
        for i in eachindex(datetimes)
            obs = Observer(lats[i], lons[i], alts[i])
            p = solar_position(obs, datetimes[i], alg, refr)
            (ae, az) = apparent(p)
            rows[i] = [p.azimuth, p.elevation, p.zenith, ae, az]
        end
        package["$(aname)|$(rname)"] = rows
    end

    # Sunrise, sunset and transit. SPA only — `Utilities._transit_sunrise_sunset` has no
    # method for any other algorithm. The options match the Python entrypoint defaults.
    srt_alg = SPA(67.0, PRESSURE, TEMPERATURE, 0.5667)
    sun_events = Vector{Vector{Float64}}(undef, length(datetimes))
    for i in eachindex(datetimes)
        obs = Observer(lats[i], lons[i], alts[i])
        r = transit_sunrise_sunset_seconds(obs, datetimes[i], srt_alg)
        sun_events[i] = [r.transit, r.sunrise, r.sunset]
    end

    # next_/previous_ sunrise, sunset and solar noon, as Unix seconds.
    event_fns = [
        "SUNRISE|NEXT" => next_sunrise, "SUNSET|NEXT" => next_sunset,
        "SOLAR_NOON|NEXT" => next_solar_noon,
        "SUNRISE|PREVIOUS" => previous_sunrise, "SUNSET|PREVIOUS" => previous_sunset,
        "SOLAR_NOON|PREVIOUS" => previous_solar_noon,
    ]
    sun_event_lookup = Dict{String, Any}()
    for (key, f) in event_fns
        sun_event_lookup[key] = [
            datetime2unix(f(Observer(lats[i], lons[i], alts[i]), datetimes[i], srt_alg))
                for i in eachindex(datetimes)
        ]
    end

    fixture = Dict{String, Any}(
        "unix_seconds" => times,
        "sun_events" => sun_events,
        "sun_event" => sun_event_lookup,
        "latitude" => lats,
        "longitude" => lons,
        "altitude" => alts,
        "pressure" => PRESSURE,
        "temperature" => TEMPERATURE,
        "refraction_limit" => REFRACTION_LIMIT,
        "reference" => reference,
        "package" => package,
    )

    out = joinpath(@__DIR__, "fixtures.json")
    write(out, tojson(fixture))
    println("wrote $out")
    println("  conditions: $(length(times))")
    println("  reference tables: $(length(reference))")
    println("  algorithm x refraction pairs: $(length(package))")
    return nothing
end

main()
