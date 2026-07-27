@testset "Observer horizon parameter" begin

    @testset "Horizon as degrees => arcminutes" begin
        obs = Observer(45.0, 10.0, altitude = 100.0, horizon = 0 => 34)
        @test obs.horizon ≈ 34 / 60 atol = 1.0e-10
        @test obs.horizon ≈ 0.5666666666666667 atol = 1.0e-10
    end

    @testset "Horizon default value" begin
        obs = Observer(45.0, 10.0)
        @test obs.horizon == 0.0

        obs2 = Observer(45.0, 10.0, 100.0)
        @test obs2.horizon == 0.0
    end

    @testset "Horizon with different arcminutes" begin
        # 34 arcminutes
        obs1 = Observer(45.0, 10.0, horizon = 0 => 34)
        @test obs1.horizon ≈ 0.5666666666666667 atol = 1.0e-10

        # 1 degree 30 arcminutes
        obs2 = Observer(45.0, 10.0, horizon = 1 => 30)
        @test obs2.horizon ≈ 1.5 atol = 1.0e-10

        # negative horizon as a decimal value
        h = -0.5666666666666667
        obs3 = Observer(45.0, 10.0, horizon = h)
        @test isequal(obs3.horizon, h)
    end

    @testset "Observer display with horizon" begin
        obs = Observer(45.0, 10.0, altitude = 100.0, horizon = 0 => 34)
        str = sprint(show, obs)
        @test contains(str, "horizon=")
        @test contains(str, "0.566")
    end

    @testset "Four-argument positional constructor" begin
        # Test Observer(lat, lon, alt, horiz) constructor
        obs1 = Observer(45.0, 10.0, 100.0, 0.5)
        @test obs1.latitude == 45.0
        @test obs1.longitude == 10.0
        @test obs1.altitude == 100.0
        @test obs1.horizon == 0.5

        # Test with different types
        obs2 = Observer(Float32(45.0), Float32(10.0), Float32(100.0), Float32(0.5))
        @test obs2.latitude == Float32(45.0)
        @test obs2.longitude == Float32(10.0)
        @test obs2.altitude == Float32(100.0)
        @test obs2.horizon == Float32(0.5)
        @test eltype(obs2.latitude) == Float32
    end

    @testset "Four-argument constructor with Pair horizon" begin
        # Test Observer(lat, lon, alt, horiz::Pair) constructor
        obs1 = Observer(45.0, 10.0, 100.0, 0 => 34)
        @test obs1.latitude == 45.0
        @test obs1.longitude == 10.0
        @test obs1.altitude == 100.0
        @test obs1.horizon ≈ 0.5666666666666667 atol = 1.0e-10

        # Test with different arcminute values
        obs2 = Observer(45.0, 10.0, 100.0, 1 => 30)
        @test obs2.horizon ≈ 1.5 atol = 1.0e-10

        # Test with negative horizon using Pair
        obs3 = Observer(45.0, 10.0, 100.0, -1 => 0)
        @test obs3.horizon ≈ -1.0 atol = 1.0e-10
    end

    @testset "Converting Observer{T} constructor" begin
        # arguments of any Real type convert to the requested precision
        obs1 = Observer{Float32}(45.0, 10.0)
        @test obs1 isa Observer{Float32}
        @test obs1.latitude === Float32(45.0)
        @test obs1.sin_lat === sincos(deg2rad(Float32(45.0)))[1]

        # integer arguments
        obs2 = Observer{Float64}(45, 10)
        @test obs2 isa Observer{Float64}
        @test obs2.latitude === 45.0

        # altitude and Pair horizon convert too
        obs3 = Observer{BigFloat}(45.0, 10.0, 100.0, 0 => 34)
        @test obs3 isa Observer{BigFloat}
        @test obs3.horizon ≈ big"0.5666666666666667" atol = 1.0e-10

        # arguments that already match T give the identical result
        @test Observer{Float64}(45.0, 10.0) == Observer(45.0, 10.0)
        @test Observer{Float32}(45.0, 10.0) == Observer(45.0f0, 10.0f0)

        # integer horizon through the keyword constructor
        obs4 = Observer(45.0, 10.0; horizon = 1)
        @test obs4.horizon === 1.0
    end
end
