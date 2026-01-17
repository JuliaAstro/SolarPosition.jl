module SolarPositionMakieExt

using Dates, Makie
using SolarPosition
import SolarPosition: analemmas!

"""
    _generate_analemma_data(observer, year, hours; algorithm=PSA())

Generate solar position data for analemmas at specified hours throughout the year.

# Arguments
- `observer::Observer`: Observer location
- `year::Int`: Year for which to generate positions
- `hours::AbstractVector{Int}`: Hours of the day to generate analemmas for (0-23)
- `algorithm`: Solar position algorithm to use (default: PSA())

# Returns
A named tuple with fields: `datetime`, `zenith`, `azimuth`, `hour`, `dayofyear`
"""
function _generate_analemma_data(observer, year, hours; algorithm = PSA())
    # Generate dates for every day of the year
    datetimes = DateTime(year, 1, 1):Hour(1):DateTime(year, 12, 31)
    n_points = length(datetimes)

    # Pre-allocate arrays
    zeniths = Vector{Float64}(undef, n_points)
    azimuths = Vector{Float64}(undef, n_points)
    hour_vals = Vector{Int}(undef, n_points)
    doy_vals = Vector{Int}(undef, n_points)

    # Calculate solar position
    for (idx, dt) in enumerate(datetimes)
        pos = solar_position(observer, dt, algorithm)
        zeniths[idx] = pos.zenith
        azimuths[idx] = pos.azimuth
        hour_vals[idx] = Dates.hour(dt)
        doy_vals[idx] = dayofyear(dt)
    end

    return (
        datetime = datetimes,
        zenith = zeniths,
        azimuth = azimuths,
        hour = hour_vals,
        dayofyear = doy_vals,
    )
end

"""
    _add_hour_labels!(ax, observer, year, hours, coords; algorithm=PSA())

Add hour labels to a sun path plot at the position of maximum elevation for each hour.

# Arguments
- `ax`: The axis to add labels to
- `observer::Observer`: Observer location
- `year::Int`: Year for the solar positions
- `hours::AbstractVector{Int}`: Hours to label (0-23)
- `coords`: Coordinate system (`:polar` or `:cartesian`)
- `algorithm`: Solar position algorithm to use (default: PSA())
"""
function _add_hour_labels!(ax, observer, year, hours, coords; algorithm = PSA())
    # For each hour, find the day when the sun reaches maximum elevation at that hour
    for hour in hours
        # Sample a few days throughout the year to find max elevation
        dates = [Date(year, m, 15) for m = 1:12]
        max_el = -90.0
        best_pos = nothing

        for date in dates
            dt = DateTime(date) + Hour(hour)
            pos = solar_position(observer, dt, algorithm)
            el = 90.0 - pos.zenith

            if el > max_el
                max_el = el
                best_pos = pos
            end
        end

        # Only label if sun is above horizon
        if max_el > 0 && !isnothing(best_pos)
            if coords === :polar
                x = deg2rad(best_pos.azimuth)
                y = best_pos.zenith
            else  # cartesian
                offset = best_pos.azimuth < 180 ? -10 : 10
                x = best_pos.azimuth + offset
                y = max_el
            end

            text!(
                ax,
                x,
                y,
                text = lpad(string(hour), 2, '0'),
                align = (:center, :bottom),
                fontsize = 13,
            )
        end
    end
end

"""
    _configure_axis!(ax::Axis)

Configure cartesian axis for analemma plot.
"""
function _configure_axis!(ax::Axis)
    xlims!(ax, 0, 360)
    ylims!(ax, 0, 90)
    ax.xlabel = "Azimuth (°)"
    ax.ylabel = "Elevation (°)"
    ax.xticks = 0:30:360
    ax.yticks = 0:10:90
end

"""
    _configure_axis!(ax::PolarAxis)

Configure polar axis for analemma plot.
"""
function _configure_axis!(ax::PolarAxis)
    ax.direction = -1
    ax.theta_0 = -π / 2
    ax.rlimits = (0, 90)
end

"""
    _plot_analemmas!(sp, ax::Axis, data, observer, year, hours)

Plot analemmas on a cartesian axis.
"""
function _plot_analemmas!(sp, ax::Axis, data, observer, year, hours)
    _configure_axis!(ax)

    # Only plot points where sun is above horizon
    el = 90 .- data.zenith
    above_horizon = el .> 0
    vals = 365 .- data.dayofyear[above_horizon]

    p = scatter!(
        sp,
        data.azimuth[above_horizon],
        el[above_horizon];
        color = vals,
        colormap = sp.colorscheme[],
        markersize = sp.markersize[],
    )

    # Add hour labels if requested
    if sp.hour_labels[]
        _add_hour_labels!(ax, observer, year, hours, :cartesian)
    end

    return p
end

"""
    _plot_analemmas!(sp, ax::PolarAxis, data, observer, year, hours)

Plot analemmas on a polar axis.
"""
function _plot_analemmas!(sp, ax::PolarAxis, data, observer, year, hours)
    _configure_axis!(ax)

    # Only plot points where sun is above horizon
    el = 90 .- data.zenith
    above_horizon = el .> 0
    vals = 365 .- data.dayofyear[above_horizon]

    p = scatter!(
        sp,
        deg2rad.(data.azimuth[above_horizon]),
        data.zenith[above_horizon];
        color = vals,
        colormap = sp.colorscheme[],
        markersize = sp.markersize[],
    )

    # Add hour labels if requested
    if sp.hour_labels[]
        _add_hour_labels!(ax, observer, year, hours, :polar)
    end

    return p
end

@recipe(Analemmas) do scene
    Theme(colorscheme = :twilight, markersize = 3, hour_labels = true)
end

function Makie.plot!(sp::Analemmas{<:Tuple{Observer,Int}})
    observer = sp[1][]
    year = sp[2][]

    # Generate analemma data for all 24 hours
    hours = collect(0:23)
    data = _generate_analemma_data(observer, year, hours)

    ax = current_axis()
    return _plot_analemmas!(sp, ax, data, observer, year, hours)
end

end # module
