module SolarPositionModelingToolkitExt

using SolarPosition: Observer, SolarAlgorithm, RefractionAlgorithm, PSA, NoRefraction
using ModelingToolkit: @parameters, @variables, System, t_nounits
using Dates: DateTime, Millisecond
import Symbolics

import SolarPosition: SolarPositionBlock, solar_position


seconds_to_datetime(t_sec, t0::DateTime) = t0 + Millisecond(round(Int, t_sec * 1e3))

# helper functions to extract fields from solar position
get_azimuth(pos) = pos.azimuth
get_elevation(pos) = pos.elevation
get_zenith(pos) = pos.zenith

Symbolics.@register_symbolic seconds_to_datetime(t_sec, t0::DateTime)
Symbolics.@register_symbolic solar_position(
    observer::Observer,
    time::DateTime,
    algorithm::SolarAlgorithm,
    refraction::RefractionAlgorithm,
)
Symbolics.@register_symbolic get_azimuth(pos)
Symbolics.@register_symbolic get_elevation(pos)
Symbolics.@register_symbolic get_zenith(pos)

function SolarPositionBlock(; name)
    @parameters t0::DateTime [tunable = false] observer::Observer [tunable = false]
    @parameters algorithm::SolarAlgorithm = PSA() [tunable = false]
    @parameters refraction::RefractionAlgorithm = NoRefraction() [tunable = false]

    @variables azimuth(t_nounits) [output = true]
    @variables elevation(t_nounits) [output = true]
    @variables zenith(t_nounits) [output = true]

    time_expr = Symbolics.term(seconds_to_datetime, t_nounits, t0; type = DateTime)
    pos = solar_position(observer, time_expr, algorithm, refraction)

    eqs = [
        azimuth ~ get_azimuth(pos),
        elevation ~ get_elevation(pos),
        zenith ~ get_zenith(pos),
    ]

    return System(eqs, t_nounits; name = name)
end

end # module SolarPositionModelingToolkitExt
