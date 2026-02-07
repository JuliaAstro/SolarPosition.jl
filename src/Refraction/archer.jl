"""
    $(TYPEDEF)

Archer refraction model.

Atmospheric refraction correction based on the Archer algorithm.

This function calculates the atmospheric refraction correction of the solar
elevation angle using the method described by Archer [1]. The method was
originally developed to be used with the Walraven solar position algorithm [2].

# Fields
$(TYPEDFIELDS)

# Constructor
- `ARCHER()`: Creates an Archer refraction model instance

# Notes
The equation to calculate the refraction correction is given by:

```math
\\begin{aligned}
C &= \\cos(Z) + 0.0083 \\cdot \\left(\\frac{1}{0.955 + (20.267 \\cdot \\cos(Z))} - 0.047121 \\right)\\\\
Z_a &= \\arccos(C)\\\\
\\text{refraction} &= Z - Z_a
\\end{aligned}
```

where ``Z`` is the true solar zenith angle and ``Z_a`` is the apparent zenith angle.

# Literature
This method was described by [Arc80](@cite) and was originally developed
to be used with the Walraven solar position algorithm [Wal78](@cite).

# Example
```julia
using SolarPosition

# Create Archer refraction model
archer = ARCHER()

# Apply refraction correction to elevation angle
elevation = 30.0  # degrees
refraction_correction = refraction(archer, elevation)
apparent_elevation = elevation + refraction_correction
```
"""
struct ARCHER <: RefractionAlgorithm end

function _refraction(::ARCHER, elevation_deg::T) where {T <: AbstractFloat}
    zenith = T(90.0) - elevation_deg

    # calculate cosine of zenith angle
    C1 = cosd(zenith)
    D = T(1.0) / (T(0.955) + (T(20.267) * C1)) - T(0.047121)
    C = C1 + T(0.0083) * D

    return zenith - acosd(C)
end
