"""Unit tests for Walraven algorithm"""

@testset "Walraven" begin
    df_expected = expected_walraven()
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

        res = solar_position(obs, dt, Walraven())
        @test isapprox(res.elevation, exp_elev, atol = 1e-8)
        @test isapprox(res.zenith, exp_zen, atol = 1e-8)
        @test isapprox(res.azimuth, exp_az, atol = 1e-8)
    end

    @testset "Walraven edge cases" begin
        obs = Observer(45.0, 10.0, 100.0)

        # Test leap year edge case
        # February 29 in a leap year
        dt_leap = DateTime(2020, 2, 29, 12, 0, 0)
        pos = solar_position(obs, dt_leap, Walraven())
        @test pos isa SolPos

        # Test edge case with negative δ that's not leap*4 (line 33)
        # Early in the year when δ < 0
        dt_neg = DateTime(2020, 1, 2, 0, 0, 0)
        pos = solar_position(obs, dt_neg, Walraven())
        @test pos isa SolPos
        @test isfinite(pos.azimuth)
        @test isfinite(pos.elevation)
    end
end
