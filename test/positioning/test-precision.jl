"""Genuine precision across types: BigFloat carries real extra digits, Float64 stays exact,
Float32 is usable for the magnitude-safe algorithms."""

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

    # PSA/NOAA/Walraven use a magnitude-safe time base -> Float64 tracks the true answer to
    # ~1e-12. USNO/SPA reproduce the exact Julian-date arithmetic, whose ~2.45e6 magnitude
    # limits Float64 intraday resolution (~1e-7 after the sidereal-rate amplification).
    @testset "Float64 matches the BigFloat reference" begin
        for (alg, atol) in (
                (PSA(), 1.0e-9), (NOAA(), 1.0e-9), (Walraven(), 1.0e-9),
                (USNO(), 1.0e-6), (SPA(), 1.0e-6),
            )
            ref = setprecision(() -> solar_position(mkobs(BigFloat), dt, alg, NoRefraction()), BigFloat, 256)
            p = solar_position(mkobs(Float64), dt, alg, NoRefraction())
            @test isapprox(p.azimuth, Float64(ref.azimuth); atol)
            @test isapprox(p.elevation, Float64(ref.elevation); atol)
        end
    end

    # PSA/NOAA/Walraven keep a magnitude-safe time base, so Float32 stays accurate (and runs
    # genuinely in Float32). USNO/SPA reproduce the exact Float64 Julian-date arithmetic, which
    # is magnitude-limited below Float64 — they are not asserted here.
    @testset "Float32 is usable for magnitude-safe algorithms" begin
        for alg in (PSA(), NOAA(), Walraven())
            ref = setprecision(() -> solar_position(mkobs(BigFloat), dt, alg, NoRefraction()), BigFloat, 128)
            p = solar_position(mkobs(Float32), dt, alg, NoRefraction())
            @test isapprox(Float64(p.azimuth), Float64(ref.azimuth), atol = 0.05)
            @test isapprox(Float64(p.elevation), Float64(ref.elevation), atol = 0.05)
        end
    end
end
