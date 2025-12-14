using Test
using SolarPosition:
    Observer, PSA, NOAA, Walraven, USNO, SPA, NoRefraction, SolarPositionBlock
using SolarPosition: HUGHES, BENNETT, ARCHER, MICHALSKY, SG2
using ModelingToolkit: @named, @variables, @parameters, unknowns, System, mtkcompile
using ModelingToolkit: t_nounits as t, D_nounits as D
using Dates: DateTime
using OrdinaryDiffEq
using CairoMakie

@testset "ModelingToolkit Extension" begin
    obs = Observer(37.7749, -122.4194, 100.0)
    t0 = DateTime(2024, 6, 21, 0, 0, 0)  # Summer solstice

    @testset "SolarPositionBlock Creation No Refraction" begin
        @named sun = SolarPositionBlock()
        @test sun isa System
        @test sun.azimuth isa Any
        @test sun.elevation isa Any
        @test sun.zenith isa Any
    end

    @testset "Component Composition" begin
        @named sun = SolarPositionBlock()

        @parameters begin
            area = 10.0
            efficiency = 0.2
        end

        @variables begin
            irradiance(t) = 0.0
            power(t) = 0.0
        end

        eqs = [
            irradiance ~ 1000 * max(0, sind(sun.elevation) * cosd(sun.azimuth)),
            power ~ area * efficiency * irradiance,
        ]

        @named model = System(eqs, t; systems = [sun])
        sys = mtkcompile(model)

        @test sys isa System
        # test if we can access variables without errors
        @test sys.irradiance isa Any
        @test sys.power isa Any
    end

    @testset "ODEProblem Solution and Plotting" begin
        @named sun = SolarPositionBlock()

        # Compile the system
        sys = mtkcompile(sun)

        # Create parameter dictionary using the parameters from the compiled system
        pmap = [
            sys.observer => obs,
            sys.t0 => t0,
            sys.algorithm => PSA(),
            sys.refraction => NoRefraction(),
        ]

        # Create ODEProblem for 24 hours (86400 seconds)
        tspan = (0.0, 86400.0)
        prob = ODEProblem(sys, pmap, tspan)

        # Solve with fixed time step - save every 60 seconds
        sol = solve(prob; saveat = 60.0)

        @test sol isa Any
        @test length(sol.t) > 0
        @test length(sol.t) == 1441  # 0 to 86400 in steps of 60 = 1441 points

        # Validate that the solution contains actual values
        azimuth_vals = sol[sys.azimuth]
        elevation_vals = sol[sys.elevation]
        zenith_vals = sol[sys.zenith]

        @test length(azimuth_vals) > 0
        @test length(elevation_vals) > 0
        @test length(zenith_vals) > 0

        # Verify that we have values at different times
        @test length(azimuth_vals) == length(sol.t)
        @test length(elevation_vals) == length(sol.t)
        @test length(zenith_vals) == length(sol.t)

        # Check that zenith ≈ 90 - elevation
        @test all(isapprox.(zenith_vals, 90 .- elevation_vals; atol = 1e-6))

        # For summer solstice in San Francisco, check that:
        # 1. The sun rises (elevation goes from negative to positive)
        # 2. The sun sets (elevation goes from positive to negative)
        # 3. Maximum elevation is reasonable (should be around 70-75° for San Francisco summer solstice)
        max_elevation = maximum(elevation_vals)
        min_elevation = minimum(elevation_vals)

        @test max_elevation > 60.0  # Sun should get high in sky on summer solstice
        @test min_elevation < 0.0   # Sun should be below horizon at some point
        @test max_elevation - min_elevation > 100.0  # Should have significant variation over 24h

        # Check azimuth sweeps across a wide range
        azimuth_range = maximum(azimuth_vals) - minimum(azimuth_vals)
        @test azimuth_range > 180.0  # Sun should move significantly across the sky

        # Create plots
        fig = Figure(; size = (1200, 800))

        # Plot azimuth
        ax1 = Axis(
            fig[1, 1];
            xlabel = "Time (hours)",
            ylabel = "Azimuth (°)",
            title = "Solar Azimuth",
        )
        lines!(ax1, sol.t ./ 3600, sol[sys.azimuth])

        # Plot elevation
        ax2 = Axis(
            fig[1, 2];
            xlabel = "Time (hours)",
            ylabel = "Elevation (°)",
            title = "Solar Elevation",
        )
        lines!(ax2, sol.t ./ 3600, sol[sys.elevation])

        # Plot zenith
        ax3 = Axis(
            fig[2, 1];
            xlabel = "Time (hours)",
            ylabel = "Zenith (°)",
            title = "Solar Zenith",
        )
        lines!(ax3, sol.t ./ 3600, sol[sys.zenith])

        # Sky plot (polar plot of azimuth vs elevation)
        ax4 = Axis(
            fig[2, 2];
            xlabel = "Azimuth (°)",
            ylabel = "Elevation (°)",
            title = "Sun Path",
        )
        lines!(ax4, sol[sys.azimuth], sol[sys.elevation])

        # Test that the figure was created
        @test fig isa Figure

        # Optionally save the plot (commented out to avoid file creation in tests)
        # save("test_solar_position_plot.png", fig)
    end

    @testset "Algorithm Accuracy" begin
        # Test that MTK extension produces correct results for each algorithm
        # Test all conditions from each algorithm's test file
        conds = test_conditions()

        @testset "$alg_name" for (alg_name, alg, exp_func, refr) in [
            ("PSA", PSA(2020), expected_2020, NoRefraction()),
            ("Walraven", Walraven(), expected_walraven, NoRefraction()),
            ("USNO", USNO(), expected_usno, NoRefraction()),
            ("NOAA", NOAA(), expected_noaa, HUGHES(101325.0, 10.0)),
            ("SPA", SPA(), expected_spa, NoRefraction()),
        ]
            # Get expected values for all test cases
            df_expected = exp_func()

            for ((zdt, lat, lon, alt), row) in zip(eachrow(conds), eachrow(df_expected))
                # skip pole latitudes for NOAA algorithm due to numerical instability
                if alg_name == "NOAA" && (lat == 90.0 || lat == -90.0)
                    continue
                end

                # Convert ZonedDateTime to UTC DateTime for ModelingToolkit
                # astimezone converts to UTC, then DateTime extracts the DateTime part
                dt = DateTime(astimezone(zdt, tz"UTC"))

                # Create observer
                if ismissing(alt)
                    obs = Observer(lat, lon)
                else
                    obs = Observer(lat, lon, altitude = alt)
                end

                @named sun = SolarPositionBlock()
                sys = mtkcompile(sun)

                pmap = [
                    sys.observer => obs,
                    sys.t0 => dt,
                    sys.algorithm => alg,
                    sys.refraction => refr,
                ]

                prob = ODEProblem(sys, pmap, (0.0, 1.0))
                sol = solve(prob; saveat = [0.0])

                # For algorithms with refraction or SPA, use apparent_elevation/apparent_zenith
                # Otherwise use elevation/zenith
                if haskey(row, :apparent_elevation)
                    @test isapprox(
                        sol[sys.elevation][1],
                        row.apparent_elevation,
                        atol = 1e-6,
                    )
                    @test isapprox(sol[sys.zenith][1], row.apparent_zenith, atol = 1e-6)
                else
                    @test isapprox(sol[sys.elevation][1], row.elevation, atol = 1e-6)
                    @test isapprox(sol[sys.zenith][1], row.zenith, atol = 1e-6)
                end
                @test isapprox(sol[sys.azimuth][1], row.azimuth, atol = 1e-6)
            end
        end
    end
end
