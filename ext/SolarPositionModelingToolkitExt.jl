module SolarPositionModelingToolkitExt

using SolarPosition: Observer, SolarAlgorithm, RefractionAlgorithm, PSA, NoRefraction
using SolarPosition: SolPos, ApparentSolPos, SPASolPos, AbstractApparentSolPos
using ModelingToolkit: @parameters, @variables, System
using ModelingToolkit: t_nounits as t
using Dates: Dates, DateTime, Millisecond
using DocStringExtensions: TYPEDSIGNATURES
import Symbolics

import SolarPosition: SolarPositionBlock, solar_position


seconds_to_datetime(t_sec, t0::DateTime) = t0 + Millisecond(round(Int, t_sec * 1e3))

# helper functions to extract fields from solar position
get_azimuth(pos) = pos.azimuth

# for SolPos: use elevation and zenith
get_elevation(pos::SolPos) = pos.elevation
get_zenith(pos::SolPos) = pos.zenith

# for ApparentSolPos and SPASolPos: use apparent_elevation and apparent_zenith
get_elevation(pos::AbstractApparentSolPos) = pos.apparent_elevation
get_zenith(pos::AbstractApparentSolPos) = pos.apparent_zenith

Symbolics.@register_symbolic seconds_to_datetime(t_sec, t0::DateTime)::DateTime
Symbolics.@register_symbolic solar_position(
    observer::Observer,
    time::DateTime,
    algorithm::SolarAlgorithm,
    refraction::RefractionAlgorithm,
)

Symbolics.@register_symbolic get_azimuth(pos)::Real
Symbolics.@register_symbolic get_elevation(pos)::Real
Symbolics.@register_symbolic get_zenith(pos)::Real

function SolarPositionBlock(;
    name,
    t0 = Dates.now(),
    observer = Observer(0.0, 0.0, 0.0),
    algorithm = PSA(),
    refraction = NoRefraction(),
)
    @parameters t0::DateTime = t0 [tunable = false]
    @parameters observer::typeof(observer) = observer [tunable = false]
    @parameters algorithm::SolarAlgorithm = algorithm [tunable = false]
    @parameters refraction::RefractionAlgorithm = refraction [tunable = false]

    @variables azimuth(t) [output = true]
    @variables elevation(t) [output = true]
    @variables zenith(t) [output = true]

    # Ideally this should be expressed by a symbolic equation
    # but because it would involve some amount of type manipulation,
    # we can keep it this way for now.
    # But this might cause the position to be recalculated thrice (I think)
    time_expr = seconds_to_datetime(t, t0)
    pos = solar_position(observer, time_expr, algorithm, refraction)

    eqs = [
        azimuth ~ get_azimuth(pos),
        elevation ~ get_elevation(pos),
        zenith ~ get_zenith(pos),
    ]

    return System(
        eqs,
        t,
        [azimuth, elevation, zenith],
        [t0, observer, algorithm, refraction];
        #=vars=#name = name,#=params=#
    )
end

end # module SolarPositionModelingToolkitExt
