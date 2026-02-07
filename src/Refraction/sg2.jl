"""
    $(TYPEDEF)

SG2 refraction model.

Atmospheric refraction correction based on the algorithm in SG2.

This function calculates the atmospheric refraction correction of the solar
elevation angle using the method developed by Ph. Blanc and L. Wald [1].

# Fields
$(TYPEDFIELDS)

# Constructor
- `SG2()`: Uses default parameters: pressure = 101325 Pa, temperature = 12 °C
- `SG2(pressure, temperature)`: Specify custom pressure [Pa] and temperature [°C]

# Notes
The equation to calculate the refraction correction is given by:

For ``el > -0.01`` radians:
```math
\\frac{P}{1010} \\cdot \\frac{283}{273+T} \\cdot \\frac{2.96706 \\times 10^{-4}}{\\tan(el+0.0031376 \\cdot (el+0.089186)^{-1})}
```

For ``el \\leq -0.01`` radians:
```math
-\\frac{P}{1010} \\cdot \\frac{283}{273+T} \\cdot \\frac{1.005516 \\times 10^{-4}}{\\tan(el)}
```

where ``el`` is the true solar elevation angle, ``P`` is the local air
pressure in hPa, and ``T`` is the local air temperature in °C.

# Literature
This method was described by [BW12](@cite).

# Example
```julia
using SolarPosition

# Create SG2 refraction model with default parameters
sg2 = SG2()

# Or specify custom atmospheric conditions
sg2_custom = SG2(101325.0, 25.0)  # 25°C temperature

# Apply refraction correction to elevation angle
elevation = 30.0  # degrees
refraction_correction = refraction(sg2, elevation)
apparent_elevation = elevation + refraction_correction
```
"""
struct SG2{T} <: RefractionAlgorithm where {T <: AbstractFloat}
    "Annual average atmospheric pressure [Pascal]"
    pressure::T
    "Annual average temperature [°C]"
    temperature::T
end

SG2() = SG2{Float64}(101325.0, 12.0)

function _refraction(model::SG2{T}, elevation_deg::T) where {T <: AbstractFloat}
    # Convert pressure from Pascal to hPa (hectopascal)
    pressure_hPa = model.pressure / T(100.0)

    # Convert elevation from degrees to radians
    elevation_rad = deg2rad(elevation_deg)

    # Calculate refraction based on elevation
    if elevation_rad > T(-0.01)
        # For elevations above -0.01 radians
        refraction_rad = (
            T(2.96706e-4) /
                tan(elevation_rad + T(0.0031376) / (elevation_rad + T(0.089186)))
        )
    else
        # Apply correction term of Cornwall et al. (2011) for low elevations
        refraction_rad = -T(1.005516e-4) / tan(elevation_rad)
    end

    # Apply atmospheric pressure and temperature corrections
    refraction_rad =
        refraction_rad * pressure_hPa / T(1010.0) * T(283.0) /
        (T(273.0) + model.temperature)

    # Convert back to degrees
    return rad2deg(refraction_rad)
end
