"""
    $(TYPEDEF)

Hughes refraction model.

This function was developed by G. Hughes [1] and was used in the SUNAEP
software [2].

It is also used to calculate the refraction correction in the NOAA
solar position algorithm using a fixed pressure of 101325 Pa and
a temperature of 10 degrees Celsius.

# Fields
$(TYPEDFIELDS)

# Constructor
- `HUGHES()`: Uses default parameters: pressure = 101325 Pa, temperature = 12 °C
- `HUGHES(pressure, temperature)`: Specify custom pressure [Pa] and temperature [°C]

# Notes
The equation to calculate the refraction correction is given by:

For 5° < elevation ≤ 90°:
```math
\\frac{58.1}{\\tan(el)} - \\frac{0.07}{\\tan(el)^3} + \\frac{8.6 \\times 10^{-5}}{\\tan(el)^5}
```

For -0.575° < elevation ≤ 5°:
```math
el \\cdot (-518.2 + el \\cdot (103.4 + el \\cdot (-12.79 + el \\cdot 0.711))) + 1735
```

For elevation ≤ -0.575°:
```math
\\frac{-20.774}{\\tan(el)}
```

where `el` is the true (unrefracted) solar elevation angle.

The result is then corrected for temperature and pressure:
```math
\\text{Refract} \\times \\frac{283}{273 + T} \\times \\frac{P}{101325} \\times \\frac{1}{3600}
```

# References
[1] G. W. Hughes, "Engineering Astronomy," Sandia Laboratories, 1985,
    https://pvpmc.sandia.gov/app/uploads/sites/243/2022/10/Engineering-Astronomy.pdf

[2] J. C. Zimmerman, "Sun-pointing programs and their accuracy,"
    SANDIA Technical Report SAND-81-0761, 1981, DOI: 10.2172/6377969

# Example
```julia
using SolarPosition

# Create Hughes refraction model with default parameters
hughes = HUGHES()

# Or specify custom atmospheric conditions
hughes_custom = HUGHES(101325.0, 25.0)  # 25°C temperature

# Apply refraction correction to elevation angle
elevation = 30.0  # degrees
refraction_correction = refraction(hughes, elevation)
apparent_elevation = elevation + refraction_correction
```
"""
struct HUGHES{T} <: RefractionAlgorithm where {T<:AbstractFloat}
    "Annual average atmospheric pressure [Pascal]"
    pressure::T
    "Annual average temperature [°C]"
    temperature::T
end

HUGHES() = HUGHES{Float64}(101325.0, 12.0)

function _refraction(model::HUGHES{T}, elevation_deg::T) where {T<:AbstractFloat}
    tan_el = tand(elevation_deg)
    Tw = model.temperature
    Pw = model.pressure

    # calculate refraction correction in arcseconds based on elevation angle
    if elevation_deg > T(5.0)
        refract = T(58.1) / tan_el - T(0.07) / (tan_el^3) + T(8.6e-5) / (tan_el^5)
    elseif elevation_deg > T(-0.575)
        refract =
            elevation_deg * (
                T(-518.2) +
                elevation_deg *
                (T(103.4) + elevation_deg * (T(-12.79) + elevation_deg * T(0.711)))
            ) + T(1735.0)
    else
        refract = T(-20.774) / tan_el
    end

    # correct for temperature and pressure, convert from arcseconds to degrees
    refract_deg = refract * (T(283.0) / (T(273.0) + Tw)) * (Pw / T(101325.0)) / T(3600.0)

    return refract_deg
end
