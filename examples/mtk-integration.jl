# # # ModelingToolkit Integration Example
# #
# # This example demonstrates how to use the SolarPosition.jl ModelingToolkit extension
# # to integrate solar position calculations into larger modeling workflows.
# #
# # The ModelingToolkit extension allows you to:
# # 1. Create reusable solar position components
# # 2. Compose solar models with other physical systems
# # 3. Leverage MTK's symbolic simplification and code generation
# # 4. Build complex solar energy system models

# using ModelingToolkit
# using ModelingToolkit: t_nounits as t, D_nounits as D
# using SolarPosition
# using Dates
# using OrdinaryDiffEq
# using Plots

# # ## Example 1: Basic Solar Component
# #
# # Create a solar position component for a specific location

# @named sun_sf = SolarPositionBlock(
#     latitude = 37.7749,      # San Francisco
#     longitude = -122.4194,
#     altitude = 100.0,
#     t0 = DateTime(2024, 6, 21, 0, 0, 0),  # Summer solstice midnight
#     time_unit = Hour(1),      # t=1.0 means 1 hour from t0
# )

# # The solar component has variables for azimuth, elevation, and zenith angles
# println("Solar component unknowns: ", unknowns(sun_sf))
# println("Solar component parameters: ", parameters(sun_sf))
# println("Solar component equations: ", equations(sun_sf))

# # ## Example 2: Solar Panel Power Model
# #
# # Build a simple solar panel model that uses the solar position

# function simple_solar_panel(; name)
#     @parameters begin
#         area = 10.0           # Panel area in m²
#         efficiency = 0.20     # Panel efficiency (20%)
#         tilt_angle = 30.0     # Panel tilt from horizontal (degrees)
#         azimuth_angle = 180.0 # Panel azimuth (180° = South facing)
#     end

#     @variables begin
#         power(t)              # Power output in W
#         dni(t) = 800.0        # Direct Normal Irradiance in W/m²
#         incidence_angle(t)    # Angle between sun and panel normal
#         effective_irr(t)      # Effective irradiance on panel
#     end

#     # Note: This is a simplified model for demonstration
#     # In a real model, you would connect sun.elevation and sun.azimuth
#     # to calculate the actual incidence angle
#     eqs = [
#         # Simplified: assume some base irradiance pattern
#         dni ~ 800.0 + 200.0 * sin(t * π / 12),  # Daily variation
#         # Effective irradiance (simplified)
#         effective_irr ~ dni * max(0.0, cos(deg2rad(45.0))),
#         # Power output
#         power ~ area * efficiency * effective_irr,
#     ]

#     return System(eqs, t; name = name)
# end

# @named panel = simple_solar_panel()

# # Compose the solar component with the panel model
# @named solar_system = compose(System(Equation[], t; name = :solar_system), sun_sf, panel)

# println("\nComposed system unknowns: ", length(unknowns(solar_system)))
# println("Composed system equations: ", length(equations(solar_system)))

# # ## Example 3: Working Simulation with Solar Panel
# #
# # Create a complete working example that can be compiled and simulated

# function solar_panel_with_sun(; name, sun_elevation)
#     @parameters begin
#         area = 10.0           # Panel area in m²
#         efficiency = 0.20     # Panel efficiency (20%)
#         base_irradiance = 1000.0  # Base solar irradiance W/m²
#     end

#     @variables begin
#         power(t)              # Power output in W
#         irradiance(t)         # Effective irradiance on panel
#     end

#     eqs = [
#         # Irradiance depends on sun elevation
#         irradiance ~ base_irradiance * max(0.0, sin(deg2rad(sun_elevation))),
#         # Power output
#         power ~ area * efficiency * irradiance,
#     ]

#     return System(eqs, t; name = name)
# end

# # Pre-compute solar position for a specific time
# obs = Observer(37.7749, -122.4194, 100.0)  # San Francisco
# ref_time = DateTime(2024, 6, 21, 20, 0, 0)  # Summer solstice, local solar noon (UTC)
# ref_pos = solar_position(obs, ref_time, PSA())

# println("\nReference solar position at summer solstice noon:")
# println("  Elevation: $(ref_pos.elevation)°")
# println("  Azimuth: $(ref_pos.azimuth)°")

# # Create solar panel with the computed elevation
# @named panel_working = solar_panel_with_sun(sun_elevation = ref_pos.elevation)

# # Compile and simulate
# panel_sys = mtkcompile(panel_working)
# prob = ODEProblem(panel_sys, Dict(), (0.0, 10.0))
# sol = solve(prob, Tsit5())

# println("\nSolar panel simulation:")
# println("  Power output: $(sol[panel_working.power][end]) W")
# println("  Irradiance: $(sol[panel_working.irradiance][end]) W/m²")

# # ## Example 4: Building Thermal Model with Solar Gain
# #
# # Model a simple building with solar heat gain through windows

# function building_room(; name)
#     @parameters begin
#         mass = 1000.0           # Thermal mass in kg
#         cp = 1000.0             # Specific heat capacity J/(kg·K)
#         U_wall = 0.5            # Wall U-value W/(m²·K)
#         wall_area = 50.0        # Wall area m²
#         T_outside = 20.0        # Outside temperature °C
#     end

#     @variables begin
#         T(t) = 20.0             # Room temperature °C
#         Q_loss(t)               # Heat loss through walls W
#         Q_solar(t) = 0.0        # Solar heat gain W (placeholder)
#     end

#     eqs = [
#         # Heat loss through walls
#         Q_loss ~ U_wall * wall_area * (T - T_outside),
#         # Energy balance (simplified)
#         D(T) ~ (Q_solar - Q_loss) / (mass * cp),
#     ]

#     return System(eqs, t; name = name)
# end

# function solar_window(; name)
#     @parameters begin
#         window_area = 5.0       # Window area m²
#         transmittance = 0.7     # Glass transmittance
#         normal_azimuth = 180.0  # South-facing
#     end

#     @variables begin
#         Q_solar(t)              # Solar heat gain W
#         irradiance(t)           # Solar irradiance W/m²
#     end

#     # Simplified solar gain calculation
#     eqs = [
#         # Base irradiance pattern (in real model, use sun.elevation)
#         irradiance ~ 500.0 * (1 + sin(t * π / 12)),
#         Q_solar ~ window_area * transmittance * irradiance,
#     ]

#     return System(eqs, t; name = name)
# end

# @named room = building_room()
# @named window = solar_window()
# @named sun_building = SolarPositionBlock(latitude = 40.7128, longitude = -74.0060)  # NYC

# # Connect the window solar gain to the room
# @named building = compose(
#     System([room.Q_solar ~ window.Q_solar], t; name = :building),
#     room,
#     window,
#     sun_building,
# )

# println("\nBuilding model unknowns: ", length(unknowns(building)))
# println("Building model parameters: ", length(parameters(building)))

# # ## Example 5: Time-Varying Solar Simulation
# #
# # Simulate a simple system over a day with changing solar position

# function simple_thermal_mass(; name, Q_solar_func)
#     @parameters begin
#         mass = 100.0        # Thermal mass in kg
#         cp = 1000.0         # Specific heat J/(kg·K)
#         T_amb = 20.0        # Ambient temperature °C
#         h = 5.0             # Heat transfer coefficient W/(m²·K)
#         area = 1.0          # Surface area m²
#     end

#     @variables begin
#         T(t) = 20.0         # Temperature °C
#         Q_solar(t)          # Solar heat input W
#     end

#     eqs = [Q_solar ~ Q_solar_func, D(T) ~ (Q_solar - h * area * (T - T_amb)) / (mass * cp)]

#     return System(eqs, t; name = name)
# end

# # Create a time-varying solar input (simplified as sinusoidal)
# # In practice, you'd use pre-computed solar positions with interpolation
# solar_input_pattern = 500.0 * max(0.0, sin(π * t / 12))  # Peaks at noon (t=6)

# @named thermal = simple_thermal_mass(Q_solar_func = solar_input_pattern)
# thermal_sys = mtkcompile(thermal)

# # Simulate over 24 hours
# prob_thermal = ODEProblem(thermal_sys, Dict(), (0.0, 24.0))
# sol_thermal = solve(prob_thermal, Tsit5())

# println("\nThermal mass simulation with solar input:")
# println("  Initial temperature: $(sol_thermal[thermal.T][1]) °C")
# println("  Final temperature: $(sol_thermal[thermal.T][end]) °C")
# println("  Peak temperature: $(maximum(sol_thermal[thermal.T])) °C")

# # Plot temperature evolution
# p_thermal = plot(
#     sol_thermal,
#     idxs = [thermal.T],
#     xlabel = "Time (hours)",
#     ylabel = "Temperature (°C)",
#     label = "Temperature",
#     title = "Thermal Mass with Solar Heating",
#     linewidth = 2,
#     legend = :best,
# )

# display(p_thermal)

# # ## Example 6: Using Real Solar Position Data
# #
# # For accurate solar position calculations, you can compute positions offline
# # and use them as time-dependent parameters or callbacks

# # Create observer and time range
# obs = Observer(37.7749, -122.4194, 100.0)  # San Francisco
# start_time = DateTime(2024, 6, 21, 0, 0, 0)  # Summer solstice
# times = [start_time + Hour(h) for h = 0:23]

# # Compute solar positions
# positions = solar_position(obs, times, PSA())

# # Extract data
# hours = 0:23
# azimuths = positions.azimuth
# elevations = positions.elevation
# zeniths = positions.zenith

# # Plot solar position over the day
# p3 = plot(
#     hours,
#     elevations,
#     xlabel = "Hour of Day",
#     ylabel = "Solar Elevation (°)",
#     label = "Elevation Angle",
#     title = "Solar Position - Summer Solstice, San Francisco",
#     linewidth = 2,
#     marker = :circle,
#     legend = :best,
# )

# p4 = plot(
#     hours,
#     azimuths,
#     xlabel = "Hour of Day",
#     ylabel = "Solar Azimuth (°)",
#     label = "Azimuth Angle",
#     title = "Solar Azimuth Over the Day",
#     linewidth = 2,
#     marker = :circle,
#     legend = :best,
# )

# plot(p3, p4, layout = (2, 1), size = (800, 600))

# # ## Notes for Advanced Usage
# #
# # 1. **Time Mapping**: In a real application, you need to map simulation time `t`
# #    to actual DateTime values. This can be done with callbacks or custom functions.
# #
# # 2. **Callbacks**: For dynamic solar position updates during simulation, implement
# #    a DiscreteCallback that updates solar position parameters at each time step.
# #
# # 3. **Performance**: For long simulations, consider pre-computing solar positions
# #    and using interpolation rather than calculating at each solver step.
# #
# # 4. **Refraction**: Include atmospheric refraction for more accurate apparent
# #    solar positions, especially important near sunrise/sunset.
# #
# # 5. **Integration**: The MTK extension enables integration with:
# #    - PV system models
# #    - Solar thermal collectors
# #    - Building energy models (EnergyPlus-like)
# #    - Daylighting calculations
# #    - Solar tracking systems
# #    - Agricultural/greenhouse models

# println("\n✓ ModelingToolkit integration examples completed!")
# println("  The extension enables composable solar energy system modeling.")
# println("  See the documentation for more advanced usage patterns.")
