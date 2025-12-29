"""Unit tests for SG2 algorithm (not yet implemented)"""

function expected_sg2()
    # The expected values were generated using the official SG2 Python wrapper
    # and the SG2 SAE refraction correction
    columns = [:elevation, :apparent_elevation, :zenith, :apparent_zenith, :azimuth]

    values = [
        [32.21696737, 32.24355729, 57.78303263, 57.75644271, 204.91857639],
        [32.2045009, 32.2311035, 57.7954991, 57.7688965, 204.96486201],
        [34.92230526, 34.94633034, 55.07769474, 55.05366966, 169.37656689],
        [18.63488143, 18.6838735, 71.36511857, 71.3161265, 234.19025564],
        [35.75666309, 35.77996471, 54.24333691, 54.22003529, 197.67009822],
        [-9.53068757, -9.49650419, 99.53068757, 99.49650419, 201.18854894],
        [66.85690391, 66.86409239, 23.14309609, 23.13590761, 245.09007204],
        [9.52588549, 9.61972777, 80.47411451, 80.38027223, 338.81145106],
        [50.10677054, 50.1208336, 39.89322946, 39.8791664, 326.23457619],
        [35.36128972, 35.38493054, 54.63871028, 54.61506946, 175.38913627],
        [-53.24134227, -53.23705528, 143.24134227, 143.23705528, 18.64798841],
        [-53.24134227, -53.23705528, 143.24134227, 143.23705528, 18.64798841],
        [NaN, NaN, NaN, NaN, NaN],  # SG2 fails for year 1800
        [NaN, NaN, NaN, NaN, NaN],  # SG2 fails for year 2200
        [-23.40828474, -23.39502759, 113.40828474, 113.39502759, 79.54872263],
        [1.10752265, 1.45828141, 88.89247735, 88.54171859, 104.53992596],
        [32.21696737, 32.24355729, 57.78303263, 57.75644271, 204.91857639],
        [32.2169674, 32.24355732, 57.7830326, 57.75644268, 204.91857639],
        [32.21696607, 32.24355599, 57.78303393, 57.75644401, 204.91857639],
    ]

    return DataFrame(reduce(hcat, values)', columns)
end

@testset "SG2 (not implemented)" begin
    @test_skip begin
        df_expected = expected_sg2()
        conds = test_conditions()
        @test size(df_expected, 1) == 19
        @test size(df_expected, 2) == 5
        @test size(conds, 1) == 19
        @test size(conds, 2) == 4

        # TODO: Implement SG2 algorithm
        # Note: SG2 is valid only between 1980 and 2030
        # struct SG2 <: SolarAlgorithm end

        # for ((dt, lat, lon, alt), row) in zip(eachrow(conds), eachrow(df_expected))
        #     year_val = year(dt)
        #
        #     # Skip years outside valid range (1980-2030)
        #     if year_val < 1980 || year_val > 2030
        #         # These should return NaN or throw error
        #         @test all(isnan.([row.elevation, row.zenith, row.azimuth]))
        #         continue
        #     end
        #
        #     if ismissing(alt)
        #         obs = Observer(lat, lon)
        #     else
        #         obs = Observer(lat, lon, altitude = alt)
        #     end
        #
        #     # SG2 includes built-in refraction correction
        #     res = solar_position(obs, dt, SG2())
        #     @test isapprox(res.elevation, row.elevation, atol = 1e-3)
        #     @test isapprox(res.zenith, row.zenith, atol = 1e-3)
        #     @test isapprox(res.azimuth, row.azimuth, atol = 1e-3)
        #     @test isapprox(res.apparent_elevation, row.apparent_elevation, atol = 1e-3)
        #     @test isapprox(res.apparent_zenith, row.apparent_zenith, atol = 1e-3)
        # end
    end

    @testset "SG2 year validation" begin
        @test_skip begin
            # Test that SG2 throws error for years outside 1980-2030 range
            obs = Observer(50.0, 10.0)

            # Should throw error for 1960
            dt_1960 = ZonedDateTime(1960, 1, 1, 12, 0, 0, tz"UTC")
            @test_throws ArgumentError solar_position(obs, dt_1960, SG2())

            # Should throw error for 2035
            dt_2035 = ZonedDateTime(2035, 1, 1, 12, 0, 0, tz"UTC")
            @test_throws ArgumentError solar_position(obs, dt_2035, SG2())
        end
    end

    @testset "SG2 site elevation" begin
        @test_skip begin
            # Make sure that site elevations are properly used by the SG2 algorithm
            times = [ZonedDateTime(2020, 1, 1, 12, 0, 0, tz"UTC+2")]
            latitude, longitude = 50.0, 10.0

            obs_zero = Observer(latitude, longitude, altitude = 0.0)
            obs_high = Observer(latitude, longitude, altitude = 4000.0)

            zero_elevation = solar_position(obs_zero, times[1], SG2())
            high_elevation = solar_position(obs_high, times[1], SG2())

            @test zero_elevation.elevation ≠ high_elevation.elevation
        end
    end
end
