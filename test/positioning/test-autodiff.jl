"""Automatic differentiation support via ForwardDiff duals"""

using ForwardDiff

@testset "ForwardDiff" begin
    dt = DateTime(2024, 6, 21, 9, 30)

    @testset "Derivative matches finite differences: $name" for (name, alg) in [
            ("PSA", PSA()),
            ("NOAA", NOAA()),
            ("Walraven", Walraven()),
            ("USNO", USNO()),
            ("SPA", SPA()),
        ]
        # h = 1e-4: small enough for negligible truncation error, large enough
        # that the ~1e-12 deg Float64 wobble of the algorithms' internal
        # sidereal terms does not dominate the finite-difference reference
        h = 1.0e-4
        for field in (:elevation, :azimuth)
            f_lat = lat -> getproperty(
                solar_position(Observer(lat, 10.0), dt, alg, NoRefraction()), field,
            )
            f_lon = lon -> getproperty(
                solar_position(Observer(45.0, lon), dt, alg, NoRefraction()), field,
            )
            for (f, x0) in ((f_lat, 45.0), (f_lon, 10.0))
                ad = ForwardDiff.derivative(f, x0)
                fd = (f(x0 + h) - f(x0 - h)) / 2h
                @test ad ≈ fd atol = 1.0e-6
            end
        end
    end

    @testset "Gradient through refraction" begin
        f = x -> solar_position(
            Observer(x[1], x[2]), dt, NOAA(), HUGHES(101325.0, 10.0),
        ).apparent_elevation
        g = ForwardDiff.gradient(f, [45.0, 10.0])
        @test length(g) == 2
        @test all(isfinite, g)
        h = 1.0e-6
        fd_lat = (f([45.0 + h, 10.0]) - f([45.0 - h, 10.0])) / 2h
        @test g[1] ≈ fd_lat atol = 1.0e-6
    end

    @testset "Altitude derivative through SPA" begin
        f = alt -> solar_position(
            Observer(45.0, 10.0, alt), dt, SPA(), NoRefraction(),
        ).elevation
        ad = ForwardDiff.derivative(f, 100.0)
        @test isfinite(ad)
        h = 1.0e-2
        fd = (f(100.0 + h) - f(100.0 - h)) / 2h
        @test ad ≈ fd atol = 1.0e-8
    end

    @testset "Second derivatives via nested duals" begin
        f = x -> solar_position(Observer(x[1], x[2]), dt, PSA(), NoRefraction()).elevation
        hess = ForwardDiff.hessian(f, [45.0, 10.0])
        @test size(hess) == (2, 2)
        @test hess[1, 2] ≈ hess[2, 1] atol = 1.0e-10
    end

    @testset "Vectorized path with a dual observer" begin
        obs = Observer(ForwardDiff.Dual(45.0, 1.0), 10.0)
        pos = solar_position(obs, [dt, dt + Hour(1)], PSA(), NoRefraction())
        @test eltype(pos.elevation) <: ForwardDiff.Dual
        @test length(pos) == 2
    end

    @testset "Observer element type promotion" begin
        @test Observer(45.0f0, 10.0f0) isa Observer{Float32}
        @test Observer(45.0f0, 10.0f0; altitude = 100.0f0) isa Observer{Float32}
        @test Observer(45, 10) isa Observer{Float64}
        @test Observer(45.0f0, 10.0) isa Observer{Float64}
        @test Observer(ForwardDiff.Dual(45.0, 1.0), 10.0).latitude isa ForwardDiff.Dual
    end
end
