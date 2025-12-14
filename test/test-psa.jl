"""Unit tests for PSA.jl"""

@testset "PSA" begin
    coeffs = Dict(2020 => expected_2020, 2001 => expected_2001)

    @testset "Coeff $i" for (i, expected) in coeffs
        df_expected = expected()
        conds = test_conditions()
        @test size(df_expected, 1) == 19
        @test size(df_expected, 2) == 3
        @test size(conds, 1) == 19
        @test size(conds, 2) == 4

        # conds = time, latitude, longitude, altitude
        # for (dt, lat, lon, alt) in eachrow(conds)
        for ((dt, lat, lon, alt), (exp_elev, exp_zen, exp_az)) in
            zip(eachrow(conds), eachrow(df_expected))
            if ismissing(alt)
                obs = Observer(lat, lon)
            else
                obs = Observer(lat, lon, altitude = alt)
            end

            res = solar_position(obs, dt, PSA(i))
            @test isapprox(res.elevation, exp_elev, atol = 1e-8)
            @test isapprox(res.zenith, exp_zen, atol = 1e-8)
            @test isapprox(res.azimuth, exp_az, atol = 1e-8)
        end
    end

    @testset "PSA with refraction returns ApparentSolPos" begin
        obs = Observer(37.7749, -122.4194, 100.0)
        dt = DateTime(2023, 6, 21, 18, 0, 0)  # 6 PM UTC, sun should be above horizon
        res = solar_position(obs, dt, PSA(), BENNETT())

        @test res isa ApparentSolPos
        @test hasfield(typeof(res), :azimuth)
        @test hasfield(typeof(res), :elevation)
        @test hasfield(typeof(res), :zenith)
        @test hasfield(typeof(res), :apparent_elevation)
        @test hasfield(typeof(res), :apparent_zenith)

        # when sun is above horizon, apparent elevation should be higher than true elevation
        if res.elevation > 0
            @test res.apparent_elevation > res.elevation
            @test res.apparent_zenith < res.zenith
        end

        # test with other refraction algorithms
        algs = [ARCHER(), MICHALSKY(), SG2()]
        for alg in algs
            res_alg = solar_position(obs, dt, PSA(), alg)
            @test res_alg isa ApparentSolPos
        end
    end

    @testset "PSA coefficient error" begin
        obs = Observer(45.0, 10.0, 100.0)
        dt = DateTime(2020, 6, 21, 12, 0, 0)
        @test_throws ErrorException solar_position(obs, dt, PSA(9999))
    end
end
