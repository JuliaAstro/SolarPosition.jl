@testset "Observer horizon parameter" begin

    @testset "Horizon as degrees => arcminutes" begin
        obs = Observer(45.0, 10.0, altitude = 100.0, horizon = 0 => 34)
        @test obs.horizon ≈ 34 / 60 atol = 1e-10
        @test obs.horizon ≈ 0.5666666666666667 atol = 1e-10
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
        @test obs1.horizon ≈ 0.5666666666666667 atol = 1e-10

        # 1 degree 30 arcminutes
        obs2 = Observer(45.0, 10.0, horizon = 1 => 30)
        @test obs2.horizon ≈ 1.5 atol = 1e-10

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
end
