"""Unit tests for NOAA.jl"""

@testset "NOAA" begin
    df_expected = expected_noaa()
    conds = test_conditions()
    @test size(df_expected, 1) == 19
    @test size(df_expected, 2) == 5
    @test size(conds, 1) == 19
    @test size(conds, 2) == 4

    @testset "With default delta_t" begin
        # conds = time, latitude, longitude, altitude
        for ((dt, lat, lon, alt), (exp_elev, exp_app_elev, exp_zen, exp_app_zen, exp_az)) in
            zip(eachrow(conds), eachrow(df_expected))
            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            # the original NOAA algorithm is defined with Hughes refraction correction
            # NOAA uses Hughes with temperature=10°C and pressure=101325 Pa
            res = solar_position(obs, dt, NOAA(), HUGHES(101325.0, 10.0))

            # azimuth calculations have small variations
            @test isapprox(res.elevation, exp_elev, atol = 2e-7)
            @test isapprox(res.zenith, exp_zen, atol = 2e-7)
            @test isapprox(res.azimuth, exp_az, atol = 3e-7)
            @test isapprox(res.apparent_elevation, exp_app_elev, atol = 2e-7)
            @test isapprox(res.apparent_zenith, exp_app_zen, atol = 2e-7)
        end
    end

    @testset "With delta_t=nothing" begin
        for ((dt, lat, lon, alt), (exp_elev, exp_app_elev, exp_zen, exp_app_zen, exp_az)) in
            zip(eachrow(conds), eachrow(df_expected))
            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            res = solar_position(obs, dt, NOAA(nothing), HUGHES(101325.0, 10.0))

            # results can differ when delta_t is nothing
            @test isapprox(res.elevation, exp_elev, atol = 1e0)
            @test isapprox(res.zenith, exp_zen, atol = 1e0)
            @test isapprox(res.azimuth, exp_az, atol = 1e0)
            @test isapprox(res.apparent_elevation, exp_app_elev, atol = 1e0)
            @test isapprox(res.apparent_zenith, exp_app_zen, atol = 1e0)
        end
    end

    @testset "Refraction comparison at solar noon" begin
        lat, lon = 0.0, 0.0

        # spring equinox at noon UTC when sun is roughly overhead at prime meridian
        dt = ZonedDateTime(2024, 3, 20, 12, 0, 0, tz"UTC")
        obs = Observer(lat, lon)

        # with refraction correction
        res_with_refraction = solar_position(obs, dt, NOAA(), HUGHES())

        # without refraction correction
        res_no_refraction = solar_position(obs, dt, NOAA())

        # elevation and apparent_elevation should be nearly identical
        @test isapprox(
            res_with_refraction.apparent_elevation,
            res_no_refraction.elevation,
            atol = deg2rad(0.1),
        )
        @test isapprox(
            res_with_refraction.apparent_zenith,
            res_no_refraction.zenith,
            atol = deg2rad(0.1),
        )

        @test isapprox(res_with_refraction.azimuth, res_no_refraction.azimuth, atol = 1e-10)
        @test isapprox(
            res_with_refraction.elevation,
            res_no_refraction.elevation,
            atol = 1e-10,
        )
        @test isapprox(res_with_refraction.zenith, res_no_refraction.zenith, atol = 1e-10)
    end
end
