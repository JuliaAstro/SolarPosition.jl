"""Unit tests for Iqbal algorithm (not yet implemented)"""

function expected_iqbal()
    columns = [:elevation, :zenith, :azimuth]

    values = [
        [32.3933559, 57.6066441, 205.057264],
        [32.3808669, 57.6191331, 205.103653],
        [35.10239415, 54.89760585, 169.4252099],
        [18.79386827, 71.20613173, 234.3799454],
        [35.58304355, 54.41695645, 197.47158811],
        [-9.32664685, 99.32664685, 201.24829056],
        [66.88194467, 23.11805533, 245.62133739],
        [9.32664685, 80.67335315, 338.75170944],
        [49.89989703, 40.10010297, 326.27538784],
        [35.56795719, 54.43204281, 175.44720266],
        [-53.03010805, 143.03010805, 18.66654047],
        [-53.03010805, 143.03010805, 18.66654047],
        [32.7577876, 57.2422124, 205.13681576],
        [32.7577876, 57.2422124, 205.13681576],
        [-23.30557846, 113.30557846, 79.558556],
        [1.23252489, 88.76747511, 104.52245037],
        [32.3933559, 57.6066441, 205.057264],
        [32.3933559, 57.6066441, 205.057264],
        [32.3933559, 57.6066441, 205.057264],
    ]

    return DataFrame(reduce(hcat, values)', columns)
end

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
        @test isapprox(res.elevation, exp_elev, atol = 1.0e-6)
        @test isapprox(res.zenith, exp_zen, atol = 1.0e-6)
        @test isapprox(res.azimuth, exp_az, atol = 1.0e-6)
    end
end
