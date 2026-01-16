"""Unit tests for solar_position interface variants"""

using SolarPosition.Positioning:
    Observer,
    PSA,
    NOAA,
    Walraven,
    USNO,
    SPA,
    SolPos,
    ApparentSolPos,
    solar_position,
    solar_position!
using Dates, TimeZones, Tables, DataFrames
using StructArrays: StructVector
using Dates: Hour, @dateformat_str

@testset "$alg_name" for (alg_name, alg) in [
    ("PSA", PSA()),
    ("NOAA", NOAA()),
    ("Walraven", Walraven()),
    ("SPA", SPA()),
]

    @testset "Scalar Interface" begin
        lat, lon, alt = 45.0, 10.0, 4000.0
        dt_plain = DateTime(2020, 10, 17, 12, 30)
        dt_zoned = ZonedDateTime(2020, 10, 17, 12, 30, tz"UTC")

        # reference result using Observer directly
        obs_ref = Observer(lat, lon, alt)
        result_ref = solar_position(obs_ref, dt_plain, alg)

        # DateTime
        result1 = solar_position(obs_ref, dt_plain, alg)
        @test result1 == result_ref

        # ZonedDateTime
        result2 = solar_position(obs_ref, dt_zoned, alg)
        @test result2 == result_ref
    end

    @testset "Vectorized Interface" begin
        lat, lon, alt = 45.0, 10.0, 4000.0
        obs = Observer(lat, lon, alt)
        n_dts = 10

        base_dt = DateTime(2020, 10, 17, 12, 30)
        dts = [base_dt + Hour(i) for i = 0:(n_dts-1)]
        dts_zoned = [ZonedDateTime(dt, tz"UTC") for dt in dts]

        single_dt = base_dt
        single_result = solar_position(obs, single_dt, alg)

        @testset "In place" begin
            if alg isa SPA
                PosType = ApparentSolPos{Float64}
                pos = StructVector{ApparentSolPos{Float64}}((
                    azimuth = zeros(n_dts),
                    elevation = zeros(n_dts),
                    zenith = zeros(n_dts),
                    apparent_elevation = zeros(n_dts),
                    apparent_zenith = zeros(n_dts),
                ))
            elseif alg isa NOAA
                PosType = ApparentSolPos{Float64}
                pos = StructVector{ApparentSolPos{Float64}}((
                    azimuth = zeros(n_dts),
                    elevation = zeros(n_dts),
                    zenith = zeros(n_dts),
                    apparent_elevation = zeros(n_dts),
                    apparent_zenith = zeros(n_dts),
                ))
            else
                PosType = SolPos{Float64}
                pos = StructVector{SolPos{Float64}}((
                    azimuth = zeros(n_dts),
                    elevation = zeros(n_dts),
                    zenith = zeros(n_dts),
                ))
            end

            solar_position!(pos, obs, dts, alg)
            @test all(pos.azimuth .!= 0.0)
            @test pos[1] == single_result
            @test pos isa StructVector{PosType}
            @test length(pos) == n_dts

            # test a second time to ensure there are minimal allocations
            alloc_limit = alg isa SPA ? 300 : 48
            @test @allocated(solar_position!(pos, obs, dts, alg)) ≤ alloc_limit
            @test all(pos.azimuth .!= 0.0)
            @test pos[1] == single_result
            @test pos isa StructVector{PosType}
            @test length(pos) == n_dts
        end

        @testset "Return new" begin
            # Determine result type based on algorithm
            PosType = if alg isa SPA
                ApparentSolPos{Float64}
            elseif alg isa NOAA
                ApparentSolPos{Float64}
            else
                SolPos{Float64}
            end

            # DateTime
            pos1 = solar_position(obs, dts, alg)
            @test pos1 isa StructVector{PosType}
            @test length(pos1) == n_dts
            @test pos1[1] == single_result

            # ZonedDateTime
            pos2 = solar_position(obs, dts_zoned, alg)
            @test pos2 isa StructVector{PosType}
            @test length(pos2) == n_dts
            @test pos2[1] == single_result

            @test pos1 == pos2
        end
    end

    @testset "Tables Interface" begin
        lat, lon, alt = 45.0, 10.0, 4000.0
        obs = Observer(lat, lon, alt)
        base_dt = DateTime(2020, 10, 17, 12, 30)
        dt_vector = [base_dt + Hour(i) for i = 0:2]

        @testset "DataFrame with Observer" begin
            df = DataFrame(datetime = dt_vector, temperature = [20.0, 21.0, 22.0])
            solar_position!(df, obs, alg)

            @test "azimuth" in names(df)
            @test "elevation" in names(df)
            @test "zenith" in names(df)
            @test "temperature" in names(df)
            @test df.datetime == dt_vector
            @test df.temperature == [20.0, 21.0, 22.0]
            @test all(isfinite, df.azimuth)
            @test all(isfinite, df.elevation)
            @test all(isfinite, df.zenith)

            # SPA algorithm adds additional fields
            if alg isa SPA
                @test "apparent_elevation" in names(df)
                @test "apparent_zenith" in names(df)
                @test all(isfinite, df.apparent_elevation)
                @test all(isfinite, df.apparent_zenith)
            end

            direct_result = solar_position(obs, dt_vector, alg)
            @test df.azimuth == direct_result.azimuth
            @test df.elevation == direct_result.elevation
            @test df.zenith == direct_result.zenith

            if alg isa SPA
                @test df.apparent_elevation == direct_result.apparent_elevation
                @test df.apparent_zenith == direct_result.apparent_zenith
            end
        end

        @testset "Error Cases" begin
            df_no_datetime = DataFrame(temperature = [20.0, 21.0, 22.0])
            @test_throws ArgumentError solar_position!(df_no_datetime, obs, alg)

            df_empty = DataFrame(datetime = DateTime[])
            solar_position!(df_empty, obs, alg)
            @test "azimuth" in names(df_empty)
            @test "elevation" in names(df_empty)
            @test "zenith" in names(df_empty)
            @test length(df_empty.azimuth) == 0

            if alg isa SPA
                @test "apparent_elevation" in names(df_empty)
                @test "apparent_zenith" in names(df_empty)
                @test length(df_empty.apparent_elevation) == 0
            end
        end

        @testset "Custom DateTime Column" begin
            df = DataFrame(time_utc = dt_vector)
            solar_position!(df, obs, alg; dt_col = :time_utc)

            @test "azimuth" in names(df)
            @test "elevation" in names(df)
            @test "zenith" in names(df)
            @test df.time_utc == dt_vector

            direct_result = solar_position(obs, dt_vector, alg)
            @test df.azimuth == direct_result.azimuth
            @test df.elevation == direct_result.elevation
            @test df.zenith == direct_result.zenith

            if alg isa SPA
                @test df.apparent_elevation == direct_result.apparent_elevation
                @test df.apparent_zenith == direct_result.apparent_zenith
            end
        end

        @testset "Return new Table" begin
            df = DataFrame(datetime = dt_vector, temperature = [20.0, 21.0, 22.0])
            result_table = solar_position(df, obs, alg)

            @test result_table isa DataFrame
            @test "azimuth" in names(result_table)
            @test "elevation" in names(result_table)
            @test "zenith" in names(result_table)
            @test "temperature" in names(result_table)
            @test result_table.datetime == df.datetime
            @test result_table.temperature == df.temperature

            direct_result = solar_position(obs, dt_vector, alg)
            @test result_table.azimuth == direct_result.azimuth
            @test result_table.elevation == direct_result.elevation
            @test result_table.zenith == direct_result.zenith

            if alg isa SPA
                @test "apparent_elevation" in names(result_table)
                @test "apparent_zenith" in names(result_table)
                @test result_table.apparent_elevation == direct_result.apparent_elevation
                @test result_table.apparent_zenith == direct_result.apparent_zenith
            end
        end
    end
end

@testset "Refraction Integration" begin
    using SolarPosition.Positioning: ApparentSolPos
    using SolarPosition.Refraction: BENNETT, HUGHES, ARCHER, MICHALSKY, SG2

    obs = Observer(45.0, 10.0, 100.0)
    dt = DateTime(2023, 6, 21, 12, 0, 0)

    @testset "$alg_name with refraction" for (alg_name, alg) in [
        ("PSA", PSA()),
        ("NOAA", NOAA()),
        ("Walraven", Walraven()),
        ("USNO", USNO()),
    ]
        @testset "Returns ApparentSolPos with $refr_name" for (refr_name, refr) in [
            ("BENNETT", BENNETT()),
            ("HUGHES", HUGHES()),
            ("ARCHER", ARCHER()),
            ("MICHALSKY", MICHALSKY()),
            ("SG2", SG2()),
        ]
            res = solar_position(obs, dt, alg, refr)
            @test res isa ApparentSolPos
            @test hasfield(typeof(res), :azimuth)
            @test hasfield(typeof(res), :elevation)
            @test hasfield(typeof(res), :zenith)
            @test hasfield(typeof(res), :apparent_elevation)
            @test hasfield(typeof(res), :apparent_zenith)

            # Basic sanity checks
            @test isfinite(res.azimuth)
            @test isfinite(res.elevation)
            @test isfinite(res.apparent_elevation)
            @test abs(res.apparent_elevation - res.elevation) < 1.0  # Refraction is typically < 1 degree
        end
    end

    @testset "SPA with refraction returns ApparentSolPos" begin
        # SPA returns ApparentSolPos when refraction is applied
        res = solar_position(obs, dt, SPA(), BENNETT())
        @test res isa ApparentSolPos
        @test hasfield(typeof(res), :azimuth)
        @test hasfield(typeof(res), :elevation)
        @test hasfield(typeof(res), :zenith)
        @test hasfield(typeof(res), :apparent_elevation)
        @test hasfield(typeof(res), :apparent_zenith)
    end
end

@testset "Base.show methods" begin
    @testset "Observer show" begin
        obs = Observer(45.0, 10.0, 100.0)
        str = sprint(show, obs)
        @test occursin("Observer", str)
        @test occursin("45.0", str)
        @test occursin("10.0", str)
        @test occursin("100.0", str)
    end

    @testset "SolPos show" begin
        pos = SolPos(180.0, 45.0, 45.0)
        str = sprint(show, pos)
        @test occursin("SolPos", str)
        @test occursin("180.0", str)
        @test occursin("45.0", str)
    end

    @testset "ApparentSolPos show" begin
        pos = ApparentSolPos(180.0, 45.0, 45.0, 46.0, 44.0)
        str = sprint(show, pos)
        @test occursin("ApparentSolPos", str)
        @test occursin("180.0", str)
        @test occursin("45.0", str)
        @test occursin("46.0", str)
        @test occursin("44.0", str)
    end
end

@testset "Union{DateTime,ZonedDateTime} vector handling" begin
    obs = Observer(45.0, 10.0, 100.0)
    dt1 = DateTime(2020, 6, 21, 12, 0, 0)
    dt2 = ZonedDateTime(2020, 6, 21, 13, 0, 0, tz"UTC")

    # mixed vector of DateTime and ZonedDateTime
    dts = Union{DateTime,ZonedDateTime}[dt1, dt2]
    positions = solar_position(obs, dts, PSA())
    @test length(positions) == 2
    @test positions isa StructVector

    # in-place version
    pos = StructVector{SolPos{Float64}}(undef, 2)
    solar_position!(pos, obs, dts, PSA())
    @test length(pos) == 2
    @test all(p -> p isa SolPos, pos)
end

@testset "Table interface with copy" begin
    # non-mutating solar_position function for tables
    obs = Observer(45.0, 10.0, 100.0)
    df = DataFrame(
        datetime = [DateTime(2020, 6, 21, 12, 0, 0), DateTime(2020, 6, 21, 13, 0, 0)],
    )

    # returns copy
    df_result = solar_position(df, obs, PSA())

    # should not be modified
    @test !hasproperty(df, :azimuth)
    @test hasproperty(df_result, :azimuth)
    @test hasproperty(df_result, :elevation)
    @test hasproperty(df_result, :zenith)
end
