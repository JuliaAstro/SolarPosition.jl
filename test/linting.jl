using SolarPosition
using Test

using Aqua: Aqua

@testset "Aqua tests" begin
    @info "...with Aqua.jl"
    Aqua.test_all(SolarPosition)
end

if VERSION > v"1.11" # JET v0.11 requires Julia v1.11+ and PrecompileTools 1.3.2+
    using JET: JET
    @testset "JET tests" begin
        @info "...with JET.jl"
        JET.test_package(SolarPosition; target_modules = (SolarPosition,))
    end
end
