"""
    $(TYPEDEF)

Michalsky refraction model.

Atmospheric refraction correction based on the Michalsky algorithm.

This function calculates the atmospheric refraction correction of the solar
elevation angle using the method described by Michalsky [1].

# Fields
$(TYPEDFIELDS)

# Constructor
- `MICHALSKY()`: Creates a Michalsky refraction model instance

# Notes
The equation to calculate the refraction correction is given by:

```math
\\text{ref} = \\frac{3.51561 \\cdot (0.1594 + 0.0196 \\cdot el + 0.00002 \\cdot el^2)}{1 + 0.505 \\cdot el + 0.0845 \\cdot el^2}
```

where ``el`` is the true (uncorrected) solar elevation angle.

Note that 3.51561 = 1013.2 mb / 288.2 °C.

For elevation angles below -0.56°, the refraction correction is clamped to 0.56°.

# Literature
This method was described by [Mic88](@cite).

# Example
```julia
using SolarPosition

# Create Michalsky refraction model
michalsky = MICHALSKY()

# Apply refraction correction to elevation angle
elevation = 30.0  # degrees
refraction_correction = refraction(michalsky, elevation)
apparent_elevation = elevation + refraction_correction
```
"""
struct MICHALSKY <: RefractionAlgorithm end

function _refraction(::MICHALSKY, elevation_deg::T) where {T<:AbstractFloat}
    # ref = 3.51561 * (0.1594 + 0.0196 * el + 0.00002 * el^2) / (1 + 0.505 * el + 0.0845 * el^2)
    numerator = let p = (0.1594, 0.0196, 0.00002),
        q = map(T, p)
        T(3.51561) * evalpoly(elevation_deg, q)
    end
    denominator = let p = (1.0, 0.505, 0.0845),
        q = map(T, p)
        evalpoly(elevation_deg, q)
    end

    refraction_correction = numerator / denominator

    # for elevation below -0.56 degrees, clamp to 0.56
    if elevation_deg < T(-0.56)
        refraction_correction = T(0.56)
    end

    return refraction_correction
end
