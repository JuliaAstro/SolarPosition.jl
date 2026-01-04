"""
    Refraction

Atmospheric refraction models.

Refraction algorithms compute the apparent position of the sun by correcting
for atmospheric refraction effects.
"""
module Refraction

using DocStringExtensions: TYPEDFIELDS, TYPEDEF
using Reexport: @reexport


"""
    $(TYPEDEF)

Abstract base type for atmospheric refraction correction algorithms.

# Examples
```julia
struct MyRefraction <: RefractionAlgorithm end
```
"""
abstract type RefractionAlgorithm end

"""
    $(TYPEDEF)

Indicates that no atmospheric refraction correction should be applied.

This is the default refraction setting for solar position calculations.
When used, only basic solar position (azimuth, elevation, zenith) is computed.
"""
struct NoRefraction <: RefractionAlgorithm end

"""
    $(TYPEDEF)

Default refraction model used when no specific model is provided.

This will depend on the solar position algorithm being used.
"""
struct DefaultRefraction <: RefractionAlgorithm end

"""
    refraction(model::RefractionAlgorithm, elevation::T) where {T<:AbstractFloat}

Apply atmospheric refraction correction to the given elevation angle(s).

# Arguments
- `model::RefractionAlgorithm`: Refraction model to use (e.g., `HUGHES()`)
- `elevation::T`: True (unrefracted) solar elevation angle in degrees

# Returns
- Refraction correction in degrees to be added to the elevation angle

# Examples
```julia
using SolarPosition
hughes = HUGHES(101325.0, 15.0)  # 15°C temperature
elevation = 30.0  # 30 degrees
correction = refraction(hughes, elevation)
apparent_elevation = elevation + correction
```
"""
function refraction(model::RefractionAlgorithm, elevation::T) where {T<:AbstractFloat}
    return _refraction(model, elevation)
end

include("hughes.jl")
include("archer.jl")
include("bennett.jl")
include("michalsky.jl")
include("sg2.jl")
include("spa.jl")

export RefractionAlgorithm, NoRefraction, DefaultRefraction
export HUGHES, ARCHER, BENNETT, MICHALSKY, SG2, SPARefraction
export refraction

end
