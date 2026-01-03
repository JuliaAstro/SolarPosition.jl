"""Unit tests for USNO algorithm"""

@testset "USNO" begin
    @testset "With default delta_t (gmst_option=1)" begin
        df_expected = expected_usno()
        conds = test_conditions()
        @test size(df_expected, 1) == 19
        @test size(df_expected, 2) == 3
        @test size(conds, 1) == 19
        @test size(conds, 2) == 4

        for ((dt, lat, lon, alt), (exp_elev, exp_zen, exp_az)) in
            zip(eachrow(conds), eachrow(df_expected))
            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            res = solar_position(obs, dt, USNO())

            @test isapprox(res.elevation, exp_elev, atol = 1e-8)
            @test isapprox(res.zenith, exp_zen, atol = 1e-8)
            @test isapprox(res.azimuth, exp_az, atol = 1e-8)
        end
    end

    @testset "With gmst_option=2" begin
        df_expected = expected_usno_option_2()
        conds = test_conditions()

        for ((dt, lat, lon, alt), (exp_elev, exp_zen, exp_az)) in
            zip(eachrow(conds), eachrow(df_expected))
            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            res = solar_position(obs, dt, USNO(67.0, 2))

            @test isapprox(res.elevation, exp_elev, atol = 1e-8)
            @test isapprox(res.zenith, exp_zen, atol = 1e-8)
            @test isapprox(res.azimuth, exp_az, atol = 1e-8)
        end
    end

    @testset "With delta_t=nothing" begin
        df_expected = expected_usno()
        conds = test_conditions()

        for ((dt, lat, lon, alt), (exp_elev, exp_zen, exp_az)) in
            zip(eachrow(conds), eachrow(df_expected))
            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            res = solar_position(obs, dt, USNO(nothing, 1))

            # results can differ when delta_t is nothing
            @test isapprox(res.elevation, exp_elev, atol = 1e0)
            @test isapprox(res.zenith, exp_zen, atol = 1e0)
            @test isapprox(res.azimuth, exp_az, atol = 1e0)
        end
    end

    @testset "Invalid gmst_option" begin
        @test_throws ErrorException USNO(67.0, 3)
        @test_throws ErrorException USNO(67.0, 0)
    end

    @testset "Solar noon test" begin
        lat, lon = 0.0, 0.0

        # spring equinox at noon UTC when sun is roughly overhead at prime meridian
        dt = ZonedDateTime(2024, 3, 20, 12, 0, 0, tz"UTC")
        obs = Observer(lat, lon)

        res = solar_position(obs, dt, USNO())

        # at equinox and solar noon at equator/prime meridian,
        # elevation should be close to 90 degrees
        @test res.elevation > 85.0
        @test res.zenith < 5.0
    end

    @testset "USNO with DefaultRefraction" begin

        obs = Observer(45.0, 10.0, 100.0)
        dt = DateTime(2020, 6, 21, 12, 0, 0)
        pos = solar_position(obs, dt, USNO())
        @test pos isa SolPos
        @test !hasfield(typeof(pos), :apparent_elevation)

        # result_type is correctly set
        @test SolarPosition.Positioning.result_type(
            USNO,
            SolarPosition.Refraction.DefaultRefraction,
            Float64,
        ) == SolPos{Float64}
    end
end
