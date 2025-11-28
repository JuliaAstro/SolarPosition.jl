"""Unit tests for SolarPositionOhMyThreadsExt.jl"""

using OhMyThreads
using SolarPosition.Positioning:
    Observer,
    PSA,
    NOAA,
    SPA,
    SolPos,
    ApparentSolPos,
    SPASolPos,
    solar_position,
    solar_position!
using SolarPosition.Refraction: NoRefraction, BENNETT
using Dates: DateTime, Hour
using TimeZones: ZonedDateTime, @tz_str
using StructArrays: StructVector

fields = (:azimuth, :elevation, :zenith)
allfields = (:azimuth, :elevation, :zenith, :apparent_elevation, :apparent_zenith)
spafields = (
    :azimuth,
    :elevation,
    :zenith,
    :apparent_elevation,
    :apparent_zenith,
    :equation_of_time,
)

@testset "OhMyThreads Extension" begin

    obs = Observer(51.5, -0.18, 15.0)  # London
    times = collect(DateTime(2024, 6, 21, 0, 0, 0):Hour(1):DateTime(2024, 6, 21, 23, 0, 0))
    n = length(times)

    # Get serial results for comparison
    serial_results = solar_position(obs, times, PSA(), NoRefraction())

    @testset "DynamicScheduler" begin
        scheduler = DynamicScheduler()

        @testset "solar_position with DateTime" begin
            results = solar_position(obs, times, PSA(), NoRefraction(), scheduler)
            @test length(results) == n
            @test results isa StructVector{SolPos{Float64}}

            @testset "$field" for field in fields
                @test all(getfield.(results, field) .== getfield.(serial_results, field))
            end
        end

        @testset "solar_position with ZonedDateTime" begin
            tz = tz"UTC"
            zoned_times = [ZonedDateTime(dt, tz) for dt in times]
            zoned_serial_results = solar_position(obs, zoned_times, PSA(), NoRefraction())
            results = solar_position(obs, zoned_times, PSA(), NoRefraction(), scheduler)
            @test length(results) == n
            @test results isa StructVector{SolPos{Float64}}

            @testset "$field" for field in fields
                @test all(
                    getfield.(results, field) .== getfield.(zoned_serial_results, field),
                )
            end
        end

        @testset "solar_position! with DateTime" begin
            results = StructVector{SolPos{Float64}}(undef, n)
            ret = solar_position!(results, obs, times, PSA(), NoRefraction(), scheduler)

            @test ret === results
            @test length(results) == n

            @testset "$field" for field in fields
                @test all(getfield.(results, field) .== getfield.(serial_results, field))
            end
        end

        @testset "solar_position! with ZonedDateTime" begin
            tz = tz"UTC"
            zoned_times = [ZonedDateTime(dt, tz) for dt in times]
            zoned_serial_results = solar_position(obs, zoned_times, PSA(), NoRefraction())
            results = StructVector{SolPos{Float64}}(undef, n)
            ret =
                solar_position!(results, obs, zoned_times, PSA(), NoRefraction(), scheduler)

            @test ret === results
            @test length(results) == n

            @testset "$field" for field in fields
                @test all(
                    getfield.(results, field) .== getfield.(zoned_serial_results, field),
                )
            end
        end
    end

    @testset "StaticScheduler" begin
        scheduler = StaticScheduler()

        @testset "solar_position with DateTime" begin
            results = solar_position(obs, times, PSA(), NoRefraction(), scheduler)
            @test length(results) == n
            @test results isa StructVector{SolPos{Float64}}

            @testset "$field" for field in fields
                @test all(getfield.(results, field) .== getfield.(serial_results, field))
            end
        end

        @testset "solar_position! with DateTime" begin
            results = StructVector{SolPos{Float64}}(undef, n)
            ret = solar_position!(results, obs, times, PSA(), NoRefraction(), scheduler)

            @test ret === results
            @test length(results) == n

            @testset "$field" for field in fields
                @test all(getfield.(results, field) .== getfield.(serial_results, field))
            end
        end
    end

    @testset "Different algorithms" begin
        scheduler = DynamicScheduler()

        @testset "NOAA algorithm" begin
            serial_noaa = solar_position(obs, times, NOAA(), NoRefraction())
            parallel_noaa = solar_position(obs, times, NOAA(), NoRefraction(), scheduler)

            @testset "$field" for field in fields
                @test all(getfield.(parallel_noaa, field) .== getfield.(serial_noaa, field))
            end
        end

        @testset "SPA algorithm" begin
            serial_spa = solar_position(obs, times, SPA(), NoRefraction())
            parallel_spa = solar_position(obs, times, SPA(), NoRefraction(), scheduler)

            @test parallel_spa isa StructVector{SPASolPos{Float64}}

            @testset "$field" for field in spafields
                @test all(getfield.(parallel_spa, field) .== getfield.(serial_spa, field))
            end
        end
    end

    @testset "With refraction correction" begin
        scheduler = DynamicScheduler()
        ref = solar_position(obs, times, PSA(), BENNETT())

        @testset "BENNETT refraction" begin
            result = solar_position(obs, times, PSA(), BENNETT(), scheduler)

            @test result isa StructVector{ApparentSolPos{Float64}}

            @testset "$field" for field in allfields
                @test all(getfield.(result, field) .== getfield.(ref, field))
            end
        end

        @testset "In-place with refraction" begin
            result = StructVector{ApparentSolPos{Float64}}(undef, n)
            solar_position!(result, obs, times, PSA(), BENNETT(), scheduler)

            @testset "$field" for field in allfields
                @test all(getfield.(result, field) .== getfield.(ref, field))
            end
        end
    end

    @testset "Simplified syntax (scheduler as 3rd arg)" begin
        @testset "DynamicScheduler defaults" begin
            result = solar_position(obs, times, DynamicScheduler())
            @test length(result) == n
            @test result isa StructVector{SolPos{Float64}}

            # Should match PSA() with NoRefraction()
            expected = solar_position(obs, times, PSA(), NoRefraction())
            @testset "$field" for field in fields
                @test all(getfield.(result, field) .== getfield.(expected, field))
            end
        end

        @testset "StaticScheduler defaults" begin
            result = solar_position(obs, times, StaticScheduler())
            @test length(result) == n
            @test result isa StructVector{SolPos{Float64}}

            # Should match PSA() with NoRefraction()
            expected = solar_position(obs, times, PSA(), NoRefraction())
            @testset "$field" for field in fields
                @test all(getfield.(result, field) .== getfield.(expected, field))
            end
        end

        @testset "ZonedDateTime with defaults" begin
            zoned_times = [ZonedDateTime(dt, tz"UTC") for dt in times]
            result = solar_position(obs, zoned_times, DynamicScheduler())
            @test length(result) == n
            @test result isa StructVector{SolPos{Float64}}

            expected = solar_position(obs, zoned_times, PSA(), NoRefraction())
            @testset "$field" for field in fields
                @test all(getfield.(result, field) .== getfield.(expected, field))
            end
        end
    end
end
