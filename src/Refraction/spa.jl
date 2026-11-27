"""
    $(TYPEDEF)

SPARefraction - SPA (Solar Position Algorithm) refraction model.

Atmospheric refraction correction from the SPA algorithm.

This function calculates the atmospheric refraction correction of the solar
elevation angle using the method described in Reda and Andreas's [1]
Solar Position Algorithm (SPA).

# Fields
$(TYPEDFIELDS)

# Constructor
- `SPARefraction()`: Uses default parameters: pressure = 101325 Pa, temperature = 12 °C, atmos_refract = 0.5667°
- `SPARefraction(pressure, temperature)`: Specify custom pressure [Pa] and temperature [°C], uses default atmos_refract
- `SPARefraction(pressure, temperature, atmos_refract)`: Also specify the refraction at sunrise and sunset [degrees]

# Notes
The equation to calculate the refraction correction is given by:

```math
\\text{ref} = \\frac{P}{1010} \\cdot \\frac{283}{273 + T} \\cdot \\frac{1.02}{60 \\cdot \\tan(el + 10.3/(el + 5.11))}
```

where ``el`` is the true solar elevation angle, ``P`` is the annual average local
air pressure in hPa/mbar, and ``T`` is the annual average local air temperature in °C.

`atmos_refract` is the approximate atmospheric refraction at sunrise and sunset, with the
same sign convention as NREL SPA, pvlib and [`SPA`](@ref SolarPosition.Positioning.SPA).
Refraction is applied for true elevations ≥ -(0.26667° + `atmos_refract`), where 0.26667°
is the solar semidiameter. Below that the sun is fully below the horizon and the
correction is zero. The default of 0.5667° gives a cutoff of -0.83337°.

# Literature
This method was described by [RA04](@cite).

# Example
```julia
using SolarPosition

# Create SPARefraction model with default parameters
spa = SPARefraction()

# Or specify custom atmospheric conditions
spa_custom = SPARefraction(101325.0, 25.0)  # 25°C temperature

# With custom refraction limit
spa_limit = SPARefraction(101325.0, 12.0, 1.0)  # Don't correct below -1.26667°

# Apply refraction correction to elevation angle
elevation = 30.0  # degrees
refraction_correction = refraction(spa, elevation)
apparent_elevation = elevation + refraction_correction
```
"""
@kwdef struct SPARefraction{T <: Real} <: RefractionAlgorithm
    "Annual average atmospheric pressure [Pascal]"
    pressure::T = 101325.0
    "Annual average temperature [°C]"
    temperature::T = 12.0
    "Approximate atmospheric refraction at sunrise and sunset [degrees]. Refraction is applied for elevations ≥ -(0.26667 + atmos_refract)."
    atmos_refract::T = 0.5667
end

# mixed argument types promote, so a ForwardDiff.Dual pressure alongside a Float64
# temperature gives a dual valued model instead of a MethodError. The keyword constructor
# that @kwdef generates routes through the three argument form, so it promotes too.
function SPARefraction(pressure::Real, temperature::Real)
    T = promote_type(typeof(pressure), typeof(temperature))
    return SPARefraction{T}(pressure, temperature, T(0.5667))
end

function SPARefraction(pressure::Real, temperature::Real, atmos_refract::Real)
    T = promote_type(typeof(pressure), typeof(temperature), typeof(atmos_refract))
    return SPARefraction{T}(pressure, temperature, atmos_refract)
end

function _refraction(model::SPARefraction{T}, elevation_deg::Real) where {T <: Real}
    # Convert pressure from Pascal to hPa/mbar
    pressure_hPa = model.pressure / T(100.0)

    # no correction once the upper limb of the sun is below the refracted horizon
    if elevation_deg < -(T(0.26667) + model.atmos_refract)
        return T(0.0)
    end

    # Calculate refraction correction using SPA formula
    # ref = (P/1010) * (283/(273+T)) * 1.02 / (60 * tan(radians(el + 10.3/(el+5.11))))
    refraction_correction = (
        (pressure_hPa / T(1010.0)) * (T(283.0) / (T(273.0) + model.temperature)) * T(1.02) /
            (T(60.0) * tan(deg2rad(elevation_deg + T(10.3) / (elevation_deg + T(5.11)))))
    )

    return refraction_correction
end
