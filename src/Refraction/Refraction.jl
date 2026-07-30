"""
    Refraction

Atmospheric refraction models.

Refraction algorithms compute the apparent position of the sun by correcting
for atmospheric refraction effects.
"""
module Refraction

using DocStringExtensions: TYPEDFIELDS, TYPEDEF


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
    refraction(model::RefractionAlgorithm, elevation::T) where {T<:Real}

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
function refraction(model::RefractionAlgorithm, elevation::T) where {T <: Real}
    return _refraction(model, elevation)
end

_real_or_bottom(::Type{T}) where {T} = T <: Real ? T : Union{}

# Promotion of a refraction model's numeric parameter types. Differentiating with respect
# to a parameter such as pressure makes that field a dual number, and promoting an
# observer's element type with this keeps the dual alive through the code paths that
# preallocate a result container from the observer's precision alone. promote_type of no
# arguments is Union{}, so a model without numeric fields lands there and leaves the
# observer's element type untouched.
refraction_eltype(::Type{R}) where {R <: RefractionAlgorithm} =
    promote_type(map(_real_or_bottom, fieldtypes(R))...)

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
