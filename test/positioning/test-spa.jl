"""Unit tests for SPA algorithm"""

@testset "SPA" begin
    df_expected = expected_spa()
    conds = test_conditions()
    @test size(df_expected, 1) == 19
    @test size(df_expected, 2) == 6
    @test size(conds, 1) == 19
    @test size(conds, 2) == 4

    @testset "With default parameters" begin
        for ((dt, lat, lon, alt), row) in zip(eachrow(conds), eachrow(df_expected))
            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            # SPA includes refraction correction
            res = solar_position(obs, dt, SPA())

            @test isapprox(res.elevation, row.elevation, atol = 1e-8)
            @test isapprox(res.zenith, row.zenith, atol = 1e-8)
            @test isapprox(res.azimuth, row.azimuth, atol = 1e-8)
            @test isapprox(res.apparent_elevation, row.apparent_elevation, atol = 1e-8)
            @test isapprox(res.apparent_zenith, row.apparent_zenith, atol = 1e-8)
        end
    end

    @testset "With delta_t=nothing" begin
        for ((dt, lat, lon, alt), row) in zip(eachrow(conds), eachrow(df_expected))
            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            res = solar_position(obs, dt, SPA(nothing, 101325.0, 12.0, 0.5667))

            # results can differ when delta_t is nothing
            @test isapprox(res.elevation, row.elevation, atol = 1e0)
            @test isapprox(res.zenith, row.zenith, atol = 1e0)
            @test isapprox(res.azimuth, row.azimuth, atol = 1e0)
        end
    end

    @testset "SPA refraction at high elevation" begin
        times = [ZonedDateTime(2020, 3, 23, 12, 0, 0, tz"UTC")]
        obs = Observer(0.0, 0.0)  # Equator at prime meridian
        res = solar_position(obs, times[1], SPA())

        # refraction correction should be minimal
        @test isapprox(res.elevation, res.apparent_elevation, atol = 1e-3)
    end

    @testset "Custom atmospheric parameters" begin
        lat, lon = 45.0, 10.0
        dt = ZonedDateTime(2020, 10, 17, 12, 30, 0, tz"UTC")
        obs = Observer(lat, lon)

        # test with different pressure/temperature
        res_default = solar_position(obs, dt, SPA(67.0, 101325.0, 12.0, 0.5667))
        res_custom = solar_position(obs, dt, SPA(67.0, 95000.0, 25.0, 0.5667))

        # different atmospheric conditions should give slightly different refraction
        @test !isapprox(
            res_default.apparent_elevation,
            res_custom.apparent_elevation,
            atol = 1e-8,
        )

        @test isapprox(res_default.elevation, res_custom.elevation, atol = 1e-10)
    end

    @testset "Multiple times at same location" begin
        lat, lon, alt = 40.0, -105.0, 1655.0
        obs = Observer(lat, lon, altitude = alt)

        # generate multiple timestamps
        base_dt = DateTime(2023, 6, 21, 0, 0, 0)
        times = [base_dt + Hour(h) for h = 0:23]
        results = [solar_position(obs, dt, SPA()) for dt in times]

        # verify we got 24 results and they're reasonable
        @test length(results) == 24
        @test all(r -> -180.0 <= r.azimuth <= 360.0, results)
        @test all(r -> -90.0 <= r.elevation <= 90.0, results)
    end

    @testset "SPA edge cases" begin
        obs = Observer(45.0, 10.0, 5000.0)  # High altitude to test parallax terms

        # Test with extreme latitude close to poles
        obs_pole = Observer(89.99, 10.0, 100.0)
        dt = DateTime(2020, 6, 21, 12, 0, 0)
        pos = solar_position(obs_pole, dt, SPA())
        @test pos isa ApparentSolPos
    end

    @testset "SPA x_term and y_term functions" begin
        # These functions are used internally by SPA but not directly tested
        # They should be covered by creating SPAObserver instances
        obs1 = SolarPosition.Positioning.SPAObserver(45.0, 10.0, 0.0)
        @test obs1.x != 0.0
        @test obs1.y != 0.0

        obs2 = SolarPosition.Positioning.SPAObserver(45.0, 10.0, 5000.0)
        @test obs2.x != obs1.x  # Different altitude should give different x
        @test obs2.y != obs1.y  # Different altitude should give different y

        # Test alternative constructor with keyword argument (line 107)
        obs3 = SolarPosition.Positioning.SPAObserver(45.0, 10.0; altitude = 100.0)
        @test obs3.altitude == 100.0
        @test obs3.latitude == 45.0
        @test obs3.longitude == 10.0

        # Test internal helper functions directly (lines 281-290)
        lat_rad = deg2rad(45.0)
        u = SolarPosition.Positioning.u_term(lat_rad)
        @test u isa Float64
        @test isfinite(u)

        (sin_u, cos_u) = sincos(u)
        (sin_lat, cos_lat) = sincos(lat_rad)
        x = SolarPosition.Positioning.x_term(sin_u, cos_u, 100.0, cos_lat)
        @test x isa Float64
        @test isfinite(x)

        y = SolarPosition.Positioning.y_term(sin_u, cos_u, 100.0, sin_lat)
        @test y isa Float64
        @test isfinite(y)
    end

    @testset "SPA equation of time limits" begin
        obs = Observer(45.0, 10.0, 100.0)

        # Test time that produces E > 20.0 (should subtract 1440)
        # This is rare but can happen at specific dates/times
        dt1 = DateTime(2020, 1, 1, 0, 0, 0)
        pos1 = solar_position(obs, dt1, SPA())
        @test pos1 isa SPASolPos
        @test -20.0 <= pos1.equation_of_time <= 20.0

        # Test multiple dates to increase chance of hitting edge cases (line 377)
        # Try dates near perihelion and aphelion when equation of time extremes occur
        test_dates = [
            DateTime(2020, 1, 3, 0, 0, 0),   # Near perihelion
            DateTime(2020, 7, 4, 0, 0, 0),   # Near aphelion
            DateTime(2020, 2, 12, 0, 0, 0),  # E might be positive extreme
            DateTime(2020, 11, 3, 0, 0, 0),  # E might be negative extreme
        ]

        for dt in test_dates
            pos = solar_position(obs, dt, SPA())
            @test -20.0 <= pos.equation_of_time <= 20.0
        end
    end

    @testset "SPA refraction warning behavior" begin
        obs = Observer(51.5, -0.1, 0.0)
        dt = DateTime(2024, 6, 21, 12, 0, 0)

        # no warning should be thrown for default / no refraction
        @test_nowarn solar_position(obs, dt, SPA())
        @test_nowarn solar_position(obs, dt, SPA(), NoRefraction())

        # warning should be thrown for specific refraction algorithm
        @test_logs (:warn, r"SPA algorithm has its own refraction correction") solar_position(
            obs,
            dt,
            SPA(),
            SolarPosition.Refraction.HUGHES(),
        )
    end
end
