"""
    $(TYPEDEF)

Bennett refraction model.

Atmospheric refraction correction based on the Bennett algorithm.

Calculation of atmospheric refraction correction of the solar
elevation angle using the method developed by Bennett [1].

# Fields
$(TYPEDFIELDS)

# Constructor
- `BENNETT()`: Uses default parameters: pressure = 101325 Pa, temperature = 12 °C
- `BENNETT(pressure, temperature)`: Specify custom pressure [Pa] and temperature [°C]

# Notes
The equation to calculate the refraction correction is given by:

```math
\\text{ref} = \\frac{0.28 \\cdot P}{T+273} \\cdot \\frac{0.016667}{\\tan(el + 7.31 / (el+4.4))}
```

where ``P`` is the local air pressure in hPa, ``T`` is the local air
temperature in °C, and ``el`` is the true (uncorrected) solar elevation angle.

# Literature
This method was described by [Ben82](@cite).

# Example
```julia
using SolarPosition

# Create Bennett refraction model with default parameters
bennett = BENNETT()

# Or specify custom atmospheric conditions
bennett_custom = BENNETT(101325.0, 25.0)  # 25°C temperature

# Apply refraction correction to elevation angle
elevation = 30.0  # degrees
refraction_correction = refraction(bennett, elevation)
apparent_elevation = elevation + refraction_correction
```
"""
struct BENNETT{T} <: RefractionAlgorithm where {T <: AbstractFloat}
    "Annual average atmospheric pressure [Pascal]"
    pressure::T
    "Annual average temperature [°C]"
    temperature::T
end

BENNETT() = BENNETT{Float64}(101325.0, 12.0)

function _refraction(model::BENNETT{T}, elevation_deg::T) where {T <: AbstractFloat}
    # convert pressure from Pascal to hPa
    pressure_hPa = model.pressure / T(100.0)
    r = T(0.016667) / tand(elevation_deg + T(7.31) / (elevation_deg + T(4.4)))
    return r * (T(0.28) * pressure_hPa / (model.temperature + T(273.0)))
end
