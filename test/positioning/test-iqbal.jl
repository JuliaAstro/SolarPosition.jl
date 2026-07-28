"""Unit tests for Iqbal algorithm"""

@testset "Iqbal" begin
    df_expected = expected_iqbal()
    conds = test_conditions()
    @test size(df_expected, 1) == 19
    @test size(df_expected, 2) == 3
    @test size(conds, 1) == 19
    @test size(conds, 2) == 4

    for ((dt, lat, lon, alt), (exp_elev, exp_zen, exp_az)) in
        zip(eachrow(conds), eachrow(df_expected))
        obs = ismissing(alt) ? Observer(lat, lon) : Observer(lat, lon, altitude = alt)

        res = solar_position(obs, dt, Iqbal())
        @test res isa SolPos
        @test isapprox(res.elevation, exp_elev, atol = 1.0e-10)
        @test isapprox(res.zenith, exp_zen, atol = 1.0e-10)
        @test isapprox(res.azimuth, exp_az, atol = 1.0e-10)
    end
end
