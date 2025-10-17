"""Unit tests for atmospheric refraction algorithms"""

using SolarPosition.Refraction: HUGHES, ARCHER, BENNETT, MICHALSKY, SG2, SPA, refraction

# test elevation angles in degrees
test_elevation_angles() = [-1.0, -0.6, 0.0, 1.0, 4.0, 6.0, 10.0, 90.0]

# expected results for each algorithm (unit: degrees)
expected = Dict(
    "Hughes" => [
        0.32827494,
        0.54716046,
        0.47856238,
        0.360817,
        0.1875788,
        0.13769375,
        0.08750312,
        0.00000000,
    ],
    "Archer" => [
        0.76852998,
        0.61784902,
        0.47556015,
        0.34104051,
        0.17880831,
        0.13306518,
        0.08518174,
        -0.00218662,
    ],
    "Bennett" => [
        0.826520608,
        0.718039255,
        0.572036066,
        0.403658095,
        0.194720611,
        0.141175878,
        0.089453486,
        -0.000022424,
    ],
    "Michalsky" => [
        0.5600000,
        0.560000000,
        0.56038823,
        0.39595124,
        0.19147691,
        0.13805928,
        0.08665373,
        0.01003072,
    ],
    "SG2" => [
        0.328796332,
        0.548029502,
        0.481177890,
        0.361009325,
        0.188613883,
        0.139390534,
        0.089783442,
        -0.000032010,
    ],
    "SPA" => [
        0.00000000,
        0.5760885771,
        0.481185828,
        0.361012918,
        0.188614492,
        0.139390797,
        0.0897835168,
        -0.000032010,
    ],
)

# test configurations: (algorithm_name, constructor, expected_results)
test_algorithms = [
    ("Hughes", () -> HUGHES(101325.0, 12.0), expected["Hughes"]),
    ("Archer", () -> ARCHER(), expected["Archer"]),
    ("Bennett", () -> BENNETT(101325.0, 12.0), expected["Bennett"]),
    ("Michalsky", () -> MICHALSKY(), expected["Michalsky"]),
    ("SG2", () -> SG2(101325.0, 12.0), expected["SG2"]),
    ("SPA", () -> SPA(101325.0, 12.0), expected["SPA"]),
]

elevations = test_elevation_angles()

@testset "Refraction: $name" for (name, constructor, expected) in test_algorithms
    algorithm = constructor()

    @testset "Scalar computation" begin
        for (i, elev) in enumerate(elevations)
            result = refraction(algorithm, elev)
            @test result ≈ expected[i] atol = 1e-7
        end
    end

    @testset "Vectorized computation" begin
        results = refraction.(Ref(algorithm), elevations)
        for (i, res) in enumerate(results)
            @test res ≈ expected[i] atol = 1e-7
        end
    end
end

@testset "SPA refraction limit" begin
    @test refraction(SPA(101325.0, 12.0, -1.0), -2.0) == 0.0
    @test refraction(SPA(101325.0, 12.0, -3.0), -2.0) != 0.0
    @test refraction(SPA(101325.0, 12.0, -2.0), -2.0) != 0.0
    @test refraction(SPA(101325.0, 12.0, 0.0), -0.26667) != 0.0
    @test refraction(SPA(101325.0, 12.0, 0.0), -0.26668) != 1.0
end
