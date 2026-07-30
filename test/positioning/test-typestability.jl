"""Type stability and genericity across floating-point precisions."""

using SolarPosition: Observer, solar_position, SolPos, ApparentSolPos,
    PSA, NOAA, Walraven, USNO, SPA
using SolarPosition.Refraction: NoRefraction, DefaultRefraction, HUGHES, BENNETT, SG2,
    SPARefraction, ARCHER, MICHALSKY
using Dates: DateTime, Hour

@testset "Type stability across precisions" begin
    dt = DateTime(2026, 6, 2, 18, 17, 23)
    algorithms = last.(test_algorithms())

    # The result element type must follow the Observer element type, and the call must be
    # type-stable (inferable to a concrete type) for every precision and algorithm.
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

@testset "Type stability with explicit refraction models" begin
    dt = DateTime(2026, 6, 2, 18, 17, 23)
    dts = [dt, dt + Hour(1)]
    algorithms = last.(test_algorithms())
    models = (
        NoRefraction(), DefaultRefraction(), HUGHES(), BENNETT(), SG2(),
        SPARefraction(), ARCHER(), MICHALSKY(),
    )

    # the vector path sizes its StructVector from a type computed at call time, so it must
    # infer to a concrete element type or the whole vector API goes unstable
    obs = Observer(40.0, -105.0)
    @testset "$(nameof(typeof(alg))) / $(nameof(typeof(model)))" for alg in algorithms,
            model in models

        p = @inferred solar_position(obs, dt, alg, model)
        @test p isa Union{SolPos{Float64}, ApparentSolPos{Float64}}

        v = @inferred solar_position(obs, dts, alg, model)
        @test isconcretetype(eltype(v))
        @test eltype(v) === typeof(p)
    end

    # A refraction model carries its own parameter type and the apparent angles are
    # computed at it, so the result type is the promotion of the two. Matched precision and
    # parameterless models keep the observer's element type.
    @testset "Refraction parameters promote the result element type" begin
        obs32 = Observer(40.0f0, -105.0f0)
        for r in (HUGHES(), BENNETT(), SG2(), SPARefraction())
            @test solar_position(obs32, dt, PSA(), r) isa ApparentSolPos{Float64}
            @test eltype(solar_position(obs32, dts, PSA(), r)) === ApparentSolPos{Float64}
        end
        for r in (
                HUGHES{Float32}(), BENNETT{Float32}(), SG2{Float32}(),
                SPARefraction{Float32}(), ARCHER(), MICHALSKY(),
            )
            @test solar_position(obs32, dt, PSA(), r) isa ApparentSolPos{Float32}
            @test eltype(solar_position(obs32, dts, PSA(), r)) === ApparentSolPos{Float32}
        end
        # DefaultRefraction builds its model at the observer's precision, so it never widens
        @test solar_position(obs32, dt, SPA(), DefaultRefraction()) isa
            ApparentSolPos{Float32}
        @test solar_position(obs32, dt, PSA(), NoRefraction()) isa SolPos{Float32}
    end
end
