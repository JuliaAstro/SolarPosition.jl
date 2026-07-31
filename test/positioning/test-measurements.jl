"""Uncertainty propagation via Measurements.jl"""

using DataFrames: DataFrame
using Measurements: Measurement, ±, uncertainty, value
using StructArrays: StructArrays

@testset "Measurements" begin
    dt = DateTime(2024, 6, 21, 9, 30)
    σ = 0.01

    # latitude and longitude enter as independent inputs, so the propagated uncertainty
    # must equal the magnitude of the finite-difference gradient scaled by σ
    @testset "Propagated uncertainty matches finite differences: $name" for (name, alg) in
        test_algorithms()
        h = 1.0e-4
        obs = Observer(45.0 ± σ, 10.0 ± σ)
        for field in (:elevation, :azimuth)
            f = (lat, lon) -> getproperty(
                solar_position(Observer(lat, lon), dt, alg, NoRefraction()), field,
            )
            res = getproperty(solar_position(obs, dt, alg, NoRefraction()), field)
            ∂lat = (f(45.0 + h, 10.0) - f(45.0 - h, 10.0)) / 2h
            ∂lon = (f(45.0, 10.0 + h) - f(45.0, 10.0 - h)) / 2h
            @test value(res) ≈ f(45.0, 10.0) atol = 1.0e-10
            @test uncertainty(res) ≈ hypot(∂lat * σ, ∂lon * σ) rtol = 1.0e-5
        end
    end

    # zenith is 90 minus elevation, so the sum must carry no uncertainty at all. This
    # holds only if the observer's precomputed sin_lat and cos_lat stay correlated with
    # latitude, which is the part most likely to be silently wrong.
    @testset "Correlations survive the precomputed observer trig" begin
        @testset "$name" for (name, alg) in test_algorithms()
            res = solar_position(Observer(45.0 ± σ, 10.0 ± σ), dt, alg, NoRefraction())
            total = res.elevation + res.zenith
            @test value(total) ≈ 90.0 atol = 1.0e-12
            @test uncertainty(total) == 0.0
            @test uncertainty(res.elevation) > 0
        end
    end

    @testset "Uncertain refraction parameters widen the apparent angles" begin
        # a low sun, where refraction is large enough for its parameters to matter
        dt_low = DateTime(2024, 12, 21, 8)
        obs = Observer(52.0 ± σ, 5.0 ± σ)
        @testset "$(nameof(M))" for M in (HUGHES, BENNETT, SG2, SPARefraction)
            fixed = solar_position(obs, dt_low, PSA(), M(101325.0, 12.0))
            loose = solar_position(obs, dt_low, PSA(), M(101325.0 ± 500.0, 12.0 ± 2.0))
            @test value(loose.apparent_elevation) ≈
                value(fixed.apparent_elevation) atol = 1.0e-12
            @test uncertainty(loose.apparent_elevation) >
                uncertainty(fixed.apparent_elevation)
            # the geometric angle does not depend on the refraction parameters
            @test uncertainty(loose.elevation) == uncertainty(fixed.elevation)
        end
    end

    @testset "Element and result types" begin
        obs = Observer(45.0 ± σ, 10.0 ± σ)
        @test obs isa Observer{Measurement{Float64}}
        @test Observer(45.0f0 ± 0.01f0, 10.0f0 ± 0.01f0) isa Observer{Measurement{Float32}}
        @test solar_position(obs, dt, PSA(), NoRefraction()) isa
            SolPos{Measurement{Float64}}
        @test solar_position(obs, dt, PSA(), HUGHES(101325.0, 12.0)) isa
            ApparentSolPos{Measurement{Float64}}
    end

    @testset "Vectorized, in-place, and table paths" begin
        obs = Observer(45.0 ± σ, 10.0 ± σ)
        dts = [dt, dt + Hour(1), dt + Hour(2)]

        pos = solar_position(obs, dts, PSA(), NoRefraction())
        @test pos isa StructArrays.StructVector{SolPos{Measurement{Float64}}}
        @test length(pos) == 3
        for (i, t) in enumerate(dts)
            @test pos.elevation[i] ==
                solar_position(obs, t, PSA(), NoRefraction()).elevation
        end

        buf = similar(pos)
        solar_position!(buf, obs, dts, PSA(), NoRefraction())
        @test buf.elevation == pos.elevation

        df = DataFrame(datetime = dts)
        solar_position!(df, obs, PSA(), NoRefraction())
        @test eltype(df.elevation) === Measurement{Float64}
        @test df.elevation == pos.elevation
    end

    # a DateTime cannot carry an uncertainty, so the sunrise and sunset utilities compute
    # from the nominal coordinates and drop it. This test pins that down as deliberate
    # behaviour rather than leaving it to be rediscovered.
    @testset "Sunrise and sunset drop the uncertainty" begin
        nominal = Observer(45.0, 10.0)
        loose = Observer(45.0 ± 5.0, 10.0 ± 5.0)
        for f in (next_sunrise, next_sunset, next_solar_noon)
            @test f(loose, dt) == f(nominal, dt)
        end
        a = transit_sunrise_sunset(loose, Date(2024, 6, 21))
        b = transit_sunrise_sunset(nominal, Date(2024, 6, 21))
        @test (a.transit, a.sunrise, a.sunset) == (b.transit, b.sunrise, b.sunset)
    end
end
