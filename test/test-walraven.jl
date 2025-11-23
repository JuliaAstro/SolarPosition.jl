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
        @test isapprox(res.elevation, exp_elev, atol = 1e-6)
        @test isapprox(res.zenith, exp_zen, atol = 1e-6)
        @test isapprox(res.azimuth, exp_az, atol = 1e-6)
    end
end
