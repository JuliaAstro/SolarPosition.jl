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

            # SPA includes refraction correction and equation of time
            res = solar_position(obs, dt, SPA())

            @test isapprox(res.elevation, row.elevation, atol = 1e-6)
            @test isapprox(res.zenith, row.zenith, atol = 1e-6)
            @test isapprox(res.azimuth, row.azimuth, atol = 1e-6)
            @test isapprox(res.apparent_elevation, row.apparent_elevation, atol = 1e-6)
            @test isapprox(res.apparent_zenith, row.apparent_zenith, atol = 1e-6)
            @test isapprox(res.equation_of_time, row.equation_of_time, atol = 1e-6)
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
            atol = 1e-6,
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
end
