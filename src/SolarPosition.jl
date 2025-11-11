module SolarPosition

include("Refraction/Refraction.jl")
include("Positioning/Positioning.jl")

using .Positioning:
    Observer, PSA, NOAA, Walraven, USNO, SPA, solar_position, solar_position!
using .Positioning:
    SolPos,
    ApparentSolPos,
    SPASolPos,
    SolarAlgorithm,
    AbstractApparentSolPos,
    AbstractSolPos
using .Refraction: RefractionAlgorithm, NoRefraction
using .Refraction: HUGHES, ARCHER, BENNETT, MICHALSKY, SG2, SPARefraction

export solar_position, solar_position!, SolarAlgorithm, Observer
export PSA, NOAA, Walraven, USNO, SPA

export RefractionAlgorithm, NoRefraction
export HUGHES, ARCHER, BENNETT, MICHALSKY, SG2, SPARefraction

export SolPos, ApparentSolPos, SPASolPos
export AbstractSolPos, AbstractApparentSolPos

# to make the makie extension work
export sunpathplot
export sunpathplot!
export sunpathpolarplot
export sunpathpolarplot!

function sunpathplot end
function sunpathplot! end
function sunpathpolarplot end
function sunpathpolarplot! end

# to make the ModelingToolkit extension work
export SolarPositionBlock

function SolarPositionBlock end

end # module
