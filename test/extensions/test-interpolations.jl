"""Interpolated solar position algorithm backed by the Interpolations.jl extension"""

using Interpolations
using OhMyThreads: DynamicScheduler
using StructArrays: StructArrays
using TimeZones: ZonedDateTime, @tz_str

# a prime minute step gives a deterministic sample that never aligns with the
# interpolation grid
sample_times(t0, t1; step = Minute(9973)) = collect(t0:step:t1)

wrapdiff(a, b) = abs(mod(a - b + 180, 360) - 180)

const INTERP_OBSERVERS = [
    Observer(lat, lon; altitude = alt) for (lat, lon, alt) in [
            (-85.0, 170.0, 0.0),
            (-66.5, -120.0, 500.0),
            (-45.0, 30.0, 0.0),
            (-23.4, -60.0, 100.0),
            (0.0, 5.0, 0.0),
            (23.4, 100.0, 2000.0),
            (45.0, -90.0, 0.0),
            (52.35888, 4.88185, 100.0),
            (66.5, 25.0, 300.0),
            (85.0, -45.0, 0.0),
        ]
]

@testset "Interpolated" begin
    span1y = (DateTime(2024, 1, 1), DateTime(2025, 1, 1))
    alg = Interpolated(SPA(); tspan = span1y)

    @testset "Constructor validation" begin
        @test_throws ArgumentError Interpolated(SPA(); tspan = span1y, out_of_range = :clamp)
        @test_throws ArgumentError Interpolated(SPA(); tspan = (span1y[2], span1y[1]))
        @test_throws ArgumentError Interpolated(SPA(); tspan = span1y, step = Day(60))
        @test_throws ArgumentError Interpolated(SPA(); tspan = span1y, step = Hour(0))
        @test_logs (:warn, r"interpolation error above") Interpolated(
            SPA(); tspan = span1y, step = Day(10),
        )
        @test_logs Interpolated(SPA(); tspan = span1y, step = Day(3))
        @test alg isa Interpolated{SPA}
        @test occursin("out_of_range = :error", string(alg))
        @test occursin("step = 1 hour", string(alg))

        # the extension only implements sampling for SPA, so any other algorithm
        # reaches the stub that asks for Interpolations.jl
        @test_throws ArgumentError SolarPosition.Positioning._build_interpolants(
            PSA(), span1y[1], span1y[2], Millisecond(Hour(1)),
        )
    end

    @testset "Accuracy against direct SPA" begin
        for (tspan, times) in [
                (span1y, sample_times(span1y...)),
                (
                    (DateTime(2020, 1, 1), DateTime(2030, 1, 1)),
                    sample_times(DateTime(2020, 1, 1), DateTime(2030, 1, 1); step = Hour(1289)),
                ),
            ]
            interp = tspan == span1y ? alg : Interpolated(SPA(); tspan)
            maxaz = 0.0
            maxel = 0.0
            for obs in INTERP_OBSERVERS, dt in times
                p1 = solar_position(obs, dt, interp, NoRefraction())
                p2 = solar_position(obs, dt, SPA(), NoRefraction())
                maxaz = max(maxaz, wrapdiff(p1.azimuth, p2.azimuth))
                maxel = max(maxel, abs(p1.elevation - p2.elevation))
            end
            @info "Interpolated vs SPA over $(tspan[1]) to $(tspan[2])" maxaz maxel
            @test maxaz < 1.0e-6
            @test maxel < 1.0e-6
        end

        # queries at the exact span endpoints stay in range
        for dt in span1y
            @test solar_position(INTERP_OBSERVERS[1], dt, alg, NoRefraction()) isa SolPos{Float64}
        end
    end

    @testset "Refraction parity with SPA" begin
        obs = INTERP_OBSERVERS[8]
        dt = DateTime(2024, 6, 21, 12, 30)
        p1 = solar_position(obs, dt, alg)
        p2 = solar_position(obs, dt, SPA())
        @test p1 isa ApparentSolPos{Float64}
        for field in propertynames(p1)
            @test getproperty(p1, field) ≈ getproperty(p2, field) atol = 1.0e-6
        end
        @test solar_position(obs, dt, alg, NoRefraction()) isa SolPos{Float64}
    end

    @testset "Out of range behaviour" begin
        obs = INTERP_OBSERVERS[8]
        outside = DateTime(2025, 6, 1)
        err = try
            solar_position(obs, outside, alg, NoRefraction())
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("2024-01-01", err.msg)
        @test occursin("2025-01-01", err.msg)
        @test_throws ArgumentError solar_position(obs, span1y[1] - Second(1), alg, NoRefraction())

        alg_fb = Interpolated(SPA(); tspan = span1y, out_of_range = :fallback)
        pfb = solar_position(obs, outside, alg_fb, NoRefraction())
        pspa = solar_position(obs, outside, SPA(), NoRefraction())
        # the fallback runs the identical SPA code path, so results are bit equal
        @test pfb.azimuth === pspa.azimuth
        @test pfb.elevation === pspa.elevation
    end

    @testset "Batch, in place, and table paths" begin
        obs = INTERP_OBSERVERS[8]
        dts = collect(DateTime(2024, 6, 21):Minute(5):DateTime(2024, 6, 22))

        batch = solar_position(obs, dts, alg, NoRefraction())
        @test batch isa StructArrays.StructVector{SolPos{Float64}}

        # the default refraction batch path resolves to ApparentSolPos like SPA
        batch_ref = solar_position(obs, dts, alg)
        @test batch_ref isa StructArrays.StructVector{ApparentSolPos{Float64}}
        @test all(
            batch[i].elevation === solar_position(obs, dts[i], alg, NoRefraction()).elevation
                for i in eachindex(dts)
        )

        pos = StructArrays.StructVector{SolPos{Float64}}(undef, length(dts))
        solar_position!(pos, obs, dts, alg, NoRefraction())
        @test pos.azimuth == batch.azimuth

        df = DataFrame(datetime = dts)
        solar_position!(df, obs, alg, NoRefraction())
        @test df.elevation == batch.elevation

        threaded = solar_position(obs, dts, alg, NoRefraction(), DynamicScheduler())
        @test threaded.azimuth == batch.azimuth
    end

    @testset "ZonedDateTime support" begin
        obs = INTERP_OBSERVERS[8]
        offset = tz"UTC+02"
        algz = Interpolated(
            SPA();
            tspan = (
                ZonedDateTime(DateTime(2024, 1, 1, 2), offset),
                ZonedDateTime(DateTime(2024, 2, 1, 2), offset),
            ),
        )
        @test algz.tspan == (DateTime(2024, 1, 1), DateTime(2024, 2, 1))
        zdt = ZonedDateTime(DateTime(2024, 1, 15, 14, 30), offset)
        pz = solar_position(obs, zdt, algz, NoRefraction())
        pu = solar_position(obs, DateTime(2024, 1, 15, 12, 30), algz, NoRefraction())
        @test pz.azimuth === pu.azimuth
    end

    @testset "solar_rate" begin
        fd_rate = function (obs, dt)
            p1 = solar_position(obs, dt - Second(1), SPA(), NoRefraction())
            p2 = solar_position(obs, dt + Second(1), SPA(), NoRefraction())
            daz = mod(p2.azimuth - p1.azimuth + 180, 360) - 180
            return (daz * 1800, (p2.elevation - p1.elevation) * 1800)
        end
        for obs in INTERP_OBSERVERS
            for dt in (DateTime(2024, 3, 21, 9), DateTime(2024, 6, 21, 12, 30), DateTime(2024, 12, 21, 15))
                r = solar_rate(obs, dt, alg)
                (fd_az, fd_el) = fd_rate(obs, dt)
                @test r.dazimuth_dt ≈ fd_az atol = 0.01
                @test r.delevation_dt ≈ fd_el atol = 0.01
            end
        end

        # around noon in summer at mid northern latitude the azimuth advances faster
        # than the mean 15 degrees per hour
        r = solar_rate(INTERP_OBSERVERS[8], DateTime(2024, 6, 21, 12, 30), alg)
        @test 15 < r.dazimuth_dt < 40

        zdt = ZonedDateTime(DateTime(2024, 6, 21, 14, 30), tz"UTC+02")
        rz = solar_rate(INTERP_OBSERVERS[8], zdt, alg)
        @test rz == solar_rate(INTERP_OBSERVERS[8], DateTime(2024, 6, 21, 12, 30), alg)
    end

    @testset "Allocations and precision" begin
        obs = INTERP_OBSERVERS[8]
        dt = DateTime(2024, 6, 21, 12, 30)
        measure = (obs, dt, alg) -> @allocated solar_position(obs, dt, alg, NoRefraction())
        measure(obs, dt, alg)
        @test measure(obs, dt, alg) == 0
        @test @inferred(solar_position(obs, dt, alg, NoRefraction())) isa SolPos{Float64}

        p32 = solar_position(Observer{Float32}(52.0, 4.9), dt, alg, NoRefraction())
        @test p32 isa SolPos{Float32}
    end
end
