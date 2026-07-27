"""Unit tests for Iqbal algorithm (not yet implemented)"""

function expected_iqbal()
    columns = [:elevation, :zenith, :azimuth]

    values = [
        [26.6231757, 63.3768243, 220.74318428],
        [25.28992118, 64.71007882, 223.45050949],
        [35.10239415, 54.89760585, 169.4252099],
        [20.90496279, 69.09503721, 231.14854712],
        [30.93502627, 59.06497373, 214.37693117],
        [-9.32664685, 99.32664685, 216.24829056],
        [52.73099466, 37.26900534, 254.47698051],
        [9.32664685, 80.67335315, 323.75170944],
        [42.63395574, 47.36604426, 307.52528128],
        [34.73351125, 55.26648875, 193.54549706],
        [-47.76601619, 137.76601619, 40.48683144],
        [-47.76601619, 137.76601619, 40.48683144],
        [26.96991112, 63.03008888, 220.88959339],
        [26.96991112, 63.03008888, 220.88959339],
        [-20.6870207, 110.6870207, 82.37883558],
        [1.01850731, 88.98149269, 104.30039875],
        [26.6231757, 63.3768243, 220.74318428],
        [26.6231757, 63.3768243, 220.74318428],
        [26.6231757, 63.3768243, 220.74318428],
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
