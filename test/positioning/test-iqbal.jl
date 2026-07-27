"""Unit tests for Iqbal algorithm (not yet implemented)"""

function expected_iqbal()
    columns = [:elevation, :zenith, :azimuth]

    values = [
        [26.62317570131046, 63.37682429868954, 220.74318427634765],
        [25.289921182042022, 64.71007881795798, 223.4505094850185],
        [35.102394148651, 54.897605851349, 169.42520989773726],
        [20.9049627925463, 69.0950372074537, 231.1485471225258],
        [30.935026271551713, 59.06497372844829, 214.37693117294452],
        [-9.326646848826442, 99.32664684882644, 216.24829055742407],
        [52.73099466472483, 37.26900533527517, 254.47698050680197],
        [9.326646848826442, 80.67335315117356, 323.75170944257593],
        [42.633955743216504, 47.366044256783496, 307.5252812770202],
        [34.733511249796976, 55.266488750203024, 193.54549706200996],
        [-47.766016189423, 137.766016189423, 40.486831436150254],
        [-47.76601618942303, 137.76601618942303, 40.486831436150226],
        [26.96991112201878, 63.03008887798122, 220.88959338731894],
        [26.96991112201878, 63.03008887798122, 220.88959338731894],
        [-20.687020699160556, 110.68702069916056, 82.37883558094575],
        [1.0185073067602701, 88.98149269323973, 104.3003987509144],
        [26.62317570131046, 63.37682429868954, 220.74318427634765],
        [26.62317570131046, 63.37682429868954, 220.74318427634765],
        [26.62317570131046, 63.37682429868954, 220.74318427634765],
    ]

    return DataFrame(reduce(hcat, values)', columns)
end

@testset "Iqbal (not implemented)" begin
    @test_skip begin
        df_expected = expected_iqbal()
        conds = test_conditions()
        @test size(df_expected, 1) == 19
        @test size(df_expected, 2) == 3
        @test size(conds, 1) == 19
        @test size(conds, 2) == 4

        # TODO: Implement Iqbal algorithm
        # struct Iqbal <: SolarAlgorithm end

        # for ((dt, lat, lon, alt), (exp_elev, exp_zen, exp_az)) in
        #     zip(eachrow(conds), eachrow(df_expected))
        #     if ismissing(alt)
        #         obs = Observer(lat, lon)
        #     else
        #         obs = Observer(lat, lon, altitude = alt)
        #     end
        #
        #     res = solar_position(obs, dt, Iqbal())
        #     @test isapprox(res.elevation, exp_elev, atol = 1e-8)
        #     @test isapprox(res.zenith, exp_zen, atol = 1e-8)
        #     @test isapprox(res.azimuth, exp_az, atol = 1e-8)
        # end
    end
end
