"""Type stability and genericity across floating-point precisions."""

using SolarPosition: Observer, solar_position, SolPos, ApparentSolPos,
    PSA, NOAA, Walraven, USNO, SPA
using SolarPosition.Refraction: NoRefraction, DefaultRefraction
using Dates: DateTime

@testset "Type stability across precisions" begin
    dt = DateTime(2026, 6, 2, 18, 17, 23)
    algorithms = (PSA(), NOAA(), Walraven(), USNO(), SPA())

    # The result element type must follow the Observer element type, and the call must be
    # type-stable (inferrable to a concrete type) for every precision and algorithm.
    for T in (Float16, Float32, Float64, BigFloat)
        obs = Observer(T(40), T(-105); altitude = T(1600))
        for alg in algorithms
            p = @inferred solar_position(obs, dt, alg, NoRefraction())
            @test p isa SolPos{T}

            pd = @inferred solar_position(obs, dt, alg, DefaultRefraction())
            @test pd isa Union{SolPos{T}, ApparentSolPos{T}}
            @test typeof(pd).parameters[1] === T
        end
    end
end
