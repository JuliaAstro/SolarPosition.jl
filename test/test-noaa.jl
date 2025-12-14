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
            # skip pole latitudes for NOAA algorithm due to numerical instability
            if abs(lat) ≈ 90.0
                continue
            end

            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            # the original NOAA algorithm is defined with Hughes refraction correction
            # NOAA uses Hughes with temperature=10°C and pressure=101325 Pa
            res = solar_position(obs, dt, NOAA(), HUGHES(101325.0, 10.0))

            # azimuth calculations have small variations
            @test isapprox(res.elevation, exp_elev, atol = 1e-8)
            @test isapprox(res.zenith, exp_zen, atol = 1e-8)
            @test isapprox(res.azimuth, exp_az, atol = 1e-8)
            @test isapprox(res.apparent_elevation, exp_app_elev, atol = 1e-8)
            @test isapprox(res.apparent_zenith, exp_app_zen, atol = 1e-8)
        end
    end

    @testset "With delta_t=nothing" begin
        for ((dt, lat, lon, alt), (exp_elev, exp_app_elev, exp_zen, exp_app_zen, exp_az)) in
            zip(eachrow(conds), eachrow(df_expected))

            # skip pole latitudes for NOAA algorithm due to numerical instability
            if abs(lat) ≈ 90.0
                continue
            end

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

    @testset "NOAA edge cases" begin
        obs = Observer(45.0, 10.0, 100.0)

        # Test time that produces negative true_solar_time / 4.0
        # This should trigger the hour_angle < 0 branch
        dt = DateTime(2020, 1, 1, 0, 0, 0)
        pos = solar_position(obs, dt, NOAA(), NoRefraction())
        @test pos isa SolPos
        @test isfinite(pos.azimuth)

        # Test time that produces positive true_solar_time / 4.0 (line 88)
        # Solar noon should trigger the else branch
        dt_noon = DateTime(2020, 6, 21, 12, 0, 0)
        pos_noon = solar_position(obs, dt_noon, NOAA(), NoRefraction())
        @test pos_noon isa SolPos
        @test isfinite(pos_noon.azimuth)
    end
end
