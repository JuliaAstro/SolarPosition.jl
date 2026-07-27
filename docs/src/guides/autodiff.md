# [Automatic Differentiation](@id automatic-differentiation)

The [`Observer{T}`](@ref SolarPosition.Positioning.Observer) element type is only
constrained to `Real`, so dual numbers flow through every algorithm and solar
positions are differentiable with
[ForwardDiff.jl](https://github.com/JuliaDiff/ForwardDiff.jl). No extension package is
needed. This gives exact derivatives of elevation or azimuth with respect to latitude,
longitude, and altitude, which is useful for tracker and panel orientation
optimization. See the [Numeric Precision](@ref numeric-precision) guide for the
supported number types themselves.

```@example autodiff
using SolarPosition
using Dates
using ForwardDiff

dt = DateTime(2024, 6, 21, 12, 0, 0)

grad = ForwardDiff.gradient(
    x -> solar_position(Observer(x[1], x[2]), dt, SPA(), NoRefraction()).elevation,
    [45.0, 10.0],
)
```

Gradients also pass through refraction models, and nested duals give second
derivatives. Time is a `DateTime`, not a number, so derivatives with respect to time
are not available through this route. Differentiate through a wrapper that maps a
number to a `DateTime` if you need them.

## Example: optimizing a solar panel orientation

Gradient ascent on a plane-of-array irradiance proxy finds the best fixed tilt and
azimuth for a site. The objective sums the cosine of the angle of incidence over one
year of solar positions whenever the sun is up:

```@example autodiff
obs = Observer(45.0, 10.0)
times = collect(DateTime(2024, 1, 1):Hour(1):DateTime(2024, 12, 31))
year = solar_position(obs, times, PSA(), NoRefraction())

function annual_irradiance(angles)
    tilt, panel_azimuth = angles
    total = zero(eltype(angles))
    for p in year
        p.elevation > 0 || continue
        cos_aoi = cosd(p.zenith) * cosd(tilt) +
            sind(p.zenith) * sind(tilt) * cosd(p.azimuth - panel_azimuth)
        total += max(zero(cos_aoi), cos_aoi)
    end
    return total
end

function optimize(x)
    for _ in 1:100
        g = ForwardDiff.gradient(annual_irradiance, x)
        x = x + g / sqrt(sum(abs2, g))
    end
    return x
end

best = optimize([10.0, 150.0])
round.(best; digits = 1)
```

The result lands near the textbook rule of thumb for the site at 45°N: tilt a little
below the latitude, facing just about due south, and it collects roughly 31 % more
annual irradiance than a flat panel.

## Example: a horizontal single axis tracker

A horizontal single axis tracker rotates the panel about a horizontal axis to follow
the sun east to west. The rotation angle is closed form, so the interesting free
parameter is the azimuth of the axis itself, which field layouts do not always allow
to be perfectly north to south. The rotation is limited to ±60°, a typical hardware
range, and `clamp` differentiates fine:

```@example autodiff
function cos_aoi_tracked(p, axis_azimuth; limit = 60.0)
    R = clamp(atand(tand(p.zenith) * sind(p.azimuth - axis_azimuth)), -limit, limit)
    panel_azimuth = axis_azimuth + (R < 0 ? -90 : 90)
    return cosd(p.zenith) * cosd(R) +
        sind(p.zenith) * sind(abs(R)) * cosd(p.azimuth - panel_azimuth)
end

daylight = [p for p in year if p.elevation > 0]
tracked(axis) = sum(max(zero(axis), cos_aoi_tracked(p, axis)) for p in daylight)

function optimize_axis(x)
    for i in 1:40
        g = ForwardDiff.derivative(tracked, x)
        x += g / abs(g) * max(0.1, 40.0 / (i + 10))
    end
    return x
end

axis = optimize_axis(150.0)
(axis = round(axis; digits = 1), gain_vs_fixed = round(tracked(axis) / annual_irradiance(best); digits = 3))
```

The optimum is a true north to south axis, and the tracker collects roughly 38 % more
annual irradiance than the best fixed panel from the previous example.

## One day of tracker operation

One day of operation makes the behaviour concrete. The site is the Van Gogh Museum in
Amsterdam with the tracker axis aimed due south. Negative rotation faces the panel
east. The upper panel compares the tracker rotation against the analytical rotation
computed from first principles with only the solstice declination, the latitude, and
the hour angle, ignoring the equation of time. The dashed curve lies exactly on the
solid one until the ±60° limits cut it off. The lower panel shows the sun elevation
and the angle of incidence between the panel normal and the sun. The angle of
incidence touches zero exactly when the sun crosses due east and due west, because
only then does the sun lie in the tracker's rotation plane, and its local maximum at
noon equals the solar zenith angle because the panel is flat at that moment. At night
all curves are left undefined:

```@example autodiff
using CairoMakie

vgm = Observer(52.35888, 4.88185; altitude = 100.0)
axis_south = 180.0

day = collect(DateTime(2024, 6, 21):Minute(1):DateTime(2024, 6, 22))
day_pos = solar_position(vgm, day, PSA(), NoRefraction())
hours = [Dates.value(t - day[1]) / 3_600_000 for t in day]
sunup = [p.elevation > 0 for p in day_pos]

rotation = [up ?
    clamp(atand(tand(p.zenith) * sind(p.azimuth - axis_south)), -60.0, 60.0) : NaN
    for (p, up) in zip(day_pos, sunup)]
elevation = [up ? p.elevation : NaN for (p, up) in zip(day_pos, sunup)]
aoi = [up ? acosd(clamp(cos_aoi_tracked(p, axis_south), -1, 1)) : NaN
    for (p, up) in zip(day_pos, sunup)]

# unclamped rotation from declination, latitude, and hour angle alone
decl = 23.437
lat, lon = vgm.latitude, vgm.longitude
omega = [15 * (h - 12) + lon for h in hours]
analytical = [up ?
    atand(cosd(decl) * sind(w), cosd(lat) * cosd(decl) * cosd(w) + sind(lat) * sind(decl)) : NaN
    for (w, up) in zip(omega, sunup)]

# colorblind safe hues from the Wong palette, validated for each within panel pair
blue, orange, green, vermilion = "#0072B2", "#E69F00", "#009E73", "#D55E00"

fig = Figure(size = (700, 760))
ax1 = Axis(fig[1, 1]; ylabel = "degrees", xticks = 0:3:24,
    title = "South aimed tracker at the Van Gogh Museum on June 21")
lines!(ax1, hours, analytical; color = blue, linewidth = 3, label = "analytical rotation")
lines!(
    ax1, hours, rotation;
    color = orange, linewidth = 3, linestyle = :dash, label = "tracker rotation",
)
hlines!(ax1, [-60, 60]; linestyle = :dash, color = :gray)
xlims!(ax1, 0, 24)
axislegend(ax1; position = :lt)

ax2 = Axis(fig[2, 1]; xlabel = "hour of day, UTC", ylabel = "degrees", xticks = 0:3:24)
lines!(ax2, hours, elevation; color = vermilion, linewidth = 3, label = "sun elevation")
lines!(ax2, hours, aoi; color = green, linewidth = 3, label = "angle of incidence")
xlims!(ax2, 0, 24)
axislegend(ax2; position = :rb)
fig
```
