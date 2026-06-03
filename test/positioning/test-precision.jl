"""Genuine precision across types: BigFloat carries real extra digits, Float64 stays accurate,
and Float32 is usable for every algorithm thanks to the magnitude-safe time base."""

using SolarPosition: Observer, solar_position, PSA, NOAA, Walraven, USNO, SPA
using SolarPosition.Refraction: NoRefraction
using Dates: DateTime

@testset "Arbitrary precision" begin
    dt = DateTime(2026, 6, 2, 18, 17, 23)
    mkobs(T) = Observer(T(40), T(-105); altitude = T(1600))
    allalgs = (PSA(), NOAA(), Walraven(), USNO(), SPA())

    @testset "BigFloat carries genuine extra precision" begin
        # Recomputing at higher precision must keep refining the answer. If the computation
        # secretly ran in Float64, the result would plateau at ~1e-16 instead of converging.
        for alg in allalgs
            az(bits) = setprecision(BigFloat, bits) do
                solar_position(mkobs(BigFloat), dt, alg, NoRefraction()).azimuth
            end
            a128, a256, a512 = az(128), az(256), az(512)
            @test abs(a256 - a512) < abs(a128 - a256) < 1.0e-15
        end
    end

    @testset "Float64 matches the BigFloat reference" begin
        # The magnitude-safe time base keeps full intra-day resolution, so every algorithm
        # tracks the genuine (BigFloat) answer to ~1e-8 in Float64.
        for alg in allalgs
            ref = setprecision(() -> solar_position(mkobs(BigFloat), dt, alg, NoRefraction()), BigFloat, 256)
            p = solar_position(mkobs(Float64), dt, alg, NoRefraction())
            @test isapprox(p.azimuth, Float64(ref.azimuth), atol = 1.0e-8)
            @test isapprox(p.elevation, Float64(ref.elevation), atol = 1.0e-8)
        end
    end

    @testset "Float32 is usable for every algorithm" begin
        # Float32 runs genuinely in Float32 and stays usable. PSA/NOAA/Walraven/USNO reach
        # ~1e-2 deg; SPA is looser (~0.3 deg) because its sidereal term (~3.5e6) still costs
        # Float32 precision, but it is far from the ~10 deg a non-magnitude-safe base would give.
        for (alg, atol) in (
                (PSA(), 0.05), (NOAA(), 0.05), (Walraven(), 0.05), (USNO(), 0.05), (SPA(), 0.3),
            )
            ref = setprecision(() -> solar_position(mkobs(BigFloat), dt, alg, NoRefraction()), BigFloat, 128)
            p = solar_position(mkobs(Float32), dt, alg, NoRefraction())
            @test isapprox(Float64(p.azimuth), Float64(ref.azimuth); atol)
            @test isapprox(Float64(p.elevation), Float64(ref.elevation); atol)
        end
    end
end
