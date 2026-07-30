"""Automatic differentiation support via ForwardDiff duals"""

using ForwardDiff
using Interpolations
using StructArrays: StructArrays

@testset "ForwardDiff" begin
    dt = DateTime(2024, 6, 21, 9, 30)

    @testset "Derivative matches finite differences: $name" for (name, alg) in test_algorithms()
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

    @testset "Interpolated" begin
        # the interpolants only cover the geocentric, time-only quantities, so the duals
        # travel through the shared topocentric half and must match the wrapped algorithm
        span = (DateTime(2024, 6, 1), DateTime(2024, 7, 1))
        itp = Interpolated(SPA(); tspan = span)

        @testset "Derivative matches finite differences: $name" for (name, mk, x0, h) in (
                ("latitude", lat -> Observer(lat, 10.0), 45.0, 1.0e-4),
                ("longitude", lon -> Observer(45.0, lon), 10.0, 1.0e-4),
                # the altitude sensitivity is ~1e-10 deg/m, so a small step is pure
                # finite-difference noise
                ("altitude", alt -> Observer(45.0, 10.0, alt), 100.0, 100.0),
            )
            for (field, refr) in
                ((:elevation, NoRefraction()), (:apparent_elevation, SPARefraction()))
                f = x -> getproperty(solar_position(mk(x), dt, itp, refr), field)
                ad = ForwardDiff.derivative(f, x0)
                fd = (f(x0 + h) - f(x0 - h)) / 2h
                @test isfinite(ad)
                @test ad ≈ fd rtol = 1.0e-6
            end
        end

        @testset "Gradient and Hessian track the wrapped SPA" begin
            f = alg -> x -> solar_position(
                Observer(x[1], x[2]), dt, alg, NoRefraction(),
            ).elevation
            x0 = [45.0, 10.0]
            @test ForwardDiff.gradient(f(itp), x0) ≈
                ForwardDiff.gradient(f(SPA()), x0) atol = 1.0e-12
            hess = ForwardDiff.hessian(f(itp), x0)
            @test hess ≈ ForwardDiff.hessian(f(SPA()), x0) atol = 1.0e-12
            @test hess[1, 2] ≈ hess[2, 1] atol = 1.0e-14
        end

        @testset "Vectorized and in-place paths carry duals" begin
            dts = [dt, dt + Hour(1), dt + Hour(2)]
            obs = Observer(ForwardDiff.Dual(45.0, 1.0), 10.0)
            pos = solar_position(obs, dts, itp, NoRefraction())
            @test eltype(pos.elevation) <: ForwardDiff.Dual
            @test length(pos) == 3
            # the partials must equal the scalar derivative at each time
            for (i, t) in enumerate(dts)
                scalar = ForwardDiff.derivative(
                    lat -> solar_position(
                        Observer(lat, 10.0), t, itp, NoRefraction(),
                    ).elevation, 45.0,
                )
                @test ForwardDiff.partials(pos.elevation[i], 1) == scalar
            end
            buf = similar(pos)
            solar_position!(buf, obs, dts, itp, NoRefraction())
            @test buf.elevation == pos.elevation
        end

        @testset "Fallback outside the span matches the wrapped algorithm" begin
            outside = DateTime(2024, 8, 15, 9, 30)
            fb = Interpolated(SPA(); tspan = span, out_of_range = :fallback)
            f = alg -> lat -> solar_position(
                Observer(lat, 10.0), outside, alg, NoRefraction(),
            ).elevation
            @test ForwardDiff.derivative(f(fb), 45.0) ==
                ForwardDiff.derivative(f(SPA()), 45.0)
            @test_throws ArgumentError solar_position(
                Observer(ForwardDiff.Dual(45.0, 1.0), 10.0), outside, itp, NoRefraction(),
            )
        end
    end

    # a refraction parameter is a differentiable input like any other, so the models and
    # the result types promote a dual-valued parameter against a Float64 observer
    @testset "Refraction parameters" begin
        dual = ForwardDiff.Dual(101325.0, 1.0)

        @testset "Mixed argument types promote: $(nameof(M))" for M in
            (HUGHES, BENNETT, SG2, SPARefraction)
            @test M(dual, 10.0) isa M{typeof(dual)}
            @test M(101325.0, ForwardDiff.Dual(10.0, 1.0)) isa
                M{ForwardDiff.Dual{Nothing, Float64, 1}}
            # the same-type constructors keep their element type unchanged
            @test M(101325.0, 10.0) isa M{Float64}
            @test M(101325.0f0, 10.0f0) isa M{Float32}
        end

        @testset "Keyword constructor promotes" begin
            @test SPARefraction(pressure = dual) isa SPARefraction{typeof(dual)}
            @test SPARefraction(temperature = dual) isa SPARefraction{typeof(dual)}
            @test SPARefraction(atmos_refract = dual) isa SPARefraction{typeof(dual)}
            @test SPARefraction() isa SPARefraction{Float64}
        end

        @testset "Result types promote over their fields" begin
            @test SolPos(1.0, dual, 3) isa SolPos{typeof(dual)}
            @test ApparentSolPos(1.0, 2.0, 3.0, dual, dual) isa
                ApparentSolPos{typeof(dual)}
            @test SolPos(1.0, 2.0, 3.0) isa SolPos{Float64}
            @test ApparentSolPos(1.0f0, 2.0f0, 3.0f0, 4.0f0, 5.0f0) isa
                ApparentSolPos{Float32}
        end

        # a Float64 observer with a dual-valued model: no need to lift the observer
        obs = Observer(45.0, 10.0)

        @testset "Derivative w.r.t. $param: $(nameof(M))" for M in
                (HUGHES, BENNETT, SG2, SPARefraction),
                (param, mk, x0, h) in (
                    (:pressure, (p, t) -> M(p, t), 101325.0, 1.0),
                    (:temperature, (t, p) -> M(p, t), 10.0, 1.0e-2),
                )

            other = param === :pressure ? 10.0 : 101325.0
            f = x -> solar_position(obs, dt, PSA(), mk(x, other)).apparent_elevation
            ad = ForwardDiff.derivative(f, x0)
            fd = (f(x0 + h) - f(x0 - h)) / 2h
            @test isfinite(ad)
            @test ad ≈ fd rtol = 1.0e-6
        end

        @testset "Vectorized path preallocates the promoted element type" begin
            dts = [dt, dt + Hour(1)]
            model = HUGHES(dual, 10.0)
            pos = solar_position(obs, dts, PSA(), model)
            @test pos isa StructArrays.StructVector{ApparentSolPos{typeof(dual)}}
            @test eltype(pos.apparent_elevation) <: ForwardDiff.Dual
            # the geometric angles have no dual dependence, the apparent ones do
            @test all(iszero, ForwardDiff.partials.(pos.elevation, 1))
            @test all(!iszero, ForwardDiff.partials.(pos.apparent_elevation, 1))
            for (i, t) in enumerate(dts)
                @test pos.apparent_elevation[i] ==
                    solar_position(obs, t, PSA(), model).apparent_elevation
            end
        end
    end
end
