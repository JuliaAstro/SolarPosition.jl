"""
    SolarPositionInterpolationsExt

Extension that builds the cubic B-spline interpolants behind the `Interpolated` solar
position algorithm. It activates when Interpolations.jl is loaded and implements the
sampling of the wrapped algorithm's geocentric solar coordinates on a uniform time
grid. Evaluation lives in the main package and needs no extension.
"""
module SolarPositionInterpolationsExt

using SolarPosition.Positioning: Positioning, SPA, calculate_deltat
using Interpolations: interpolate, scale, BSpline, Cubic, Line, OnGrid
using Dates: Dates, DateTime, Millisecond
using Base.Threads: @threads

function Positioning._build_interpolants(
        algorithm::SPA, t0::DateTime, t1::DateTime, step::Millisecond,
    )
    # pad the grid two steps beyond each end so queries at the exact span endpoints
    # stay away from the spline's less accurate boundary cells
    t0p = t0 - 2 * step
    t1p = t1 + 2 * step
    n = Int(cld(Dates.value(t1p) - Dates.value(t0p), Dates.value(step))) + 1

    αs = Vector{Float64}(undef, n)
    δs = Vector{Float64}(undef, n)
    Rs = Vector{Float64}(undef, n)
    eqs = Vector{Float64}(undef, n)
    @threads for i in 1:n
        dti = t0p + (i - 1) * step
        δt = if algorithm.delta_t === nothing
            calculate_deltat(Float64, dti)
        else
            Float64(algorithm.delta_t)
        end
        p = Positioning._compute_spa_srt_parameters(Float64, dti, δt)
        αs[i] = p.α
        δs[i] = p.δ
        Rs[i] = p.R
        eqs[i] = p.δψ * cosd(p.ε)
    end

    # unwrap right ascension so the fitted series is continuous across 0/360. This is
    # sequential and relies on the constructor's step cap keeping the per step advance
    # far below half a turn.
    for i in 2:n
        αs[i] -= 360.0 * round((αs[i] - αs[i - 1]) / 360.0)
    end

    x0 = Positioning.julian_day_j2000(Float64, t0p)
    dx = Dates.value(step) / 86_400_000
    xs = range(x0; step = dx, length = n)
    mk(v) = scale(interpolate(v, BSpline(Cubic(Line(OnGrid())))), xs)
    return (mk(αs), mk(δs), mk(Rs), mk(eqs))
end

end
