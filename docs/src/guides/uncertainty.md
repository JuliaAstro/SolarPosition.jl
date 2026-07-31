# [Uncertainty Propagation](@id uncertainty-propagation)

The [`Observer{T}`](@ref SolarPosition.Positioning.Observer) element type is only
constrained to `Real`, so measurement values flow through every algorithm and solar
positions work with
[Measurements.jl](https://github.com/JuliaPhysics/Measurements.jl). No extension package
is needed. See the [Automatic Differentiation](@ref automatic-differentiation) guide for
the other thing that genericity buys, and the [Numeric Precision](@ref numeric-precision)
guide for the supported number types themselves.

Give the coordinates an uncertainty and it reaches every returned angle:

```@example uncertainty
using SolarPosition
using Dates
using Measurements

obs = Observer(52.35888 ± 0.01, 4.88185 ± 0.01)  # Van Gogh Museum, Amsterdam

pos = solar_position(obs, DateTime(2023, 6, 21, 12))
```

## Correlations

Results that share an input stay consistent, because Measurements tracks the derivative
chain rather than combining variances blindly. Zenith is derived from elevation, so their
sum carries no uncertainty at all:

```@example uncertainty
pos.elevation + pos.zenith
```

Treating the two as independent would instead report about `± 0.014`. This holds through
the [`Observer`](@ref SolarPosition.Positioning.Observer)'s precomputed latitude trig,
which is the part most likely to lose the correlation.

Everything else the package offers behaves the same way. `Measurement{Float32}` stays
`Float32`, and the vectorized, in-place, and table interfaces all carry uncertainties
through unchanged:

```@example uncertainty
times = collect(DateTime(2023, 6, 21, 10):Hour(2):DateTime(2023, 6, 21, 14))

solar_position(obs, times).elevation
```

## Refraction parameters

Pressure and temperature are measured quantities too, and refraction models accept them
with uncertainties in the same way. Pairing an *exact* observer with an uncertain
atmosphere isolates what the weather alone contributes:

```@example uncertainty
exact = Observer(52.35888, 4.88185)
low = DateTime(2023, 12, 21, 8)  # a low winter sun, where refraction is largest

solar_position(exact, low, PSA(), HUGHES(101325.0 ± 500.0, 12.0 ± 2.0))
```

The geometric angles come back exact, since they do not depend on the atmosphere, while
the apparent ones carry the pressure and temperature uncertainty. Making the observer
uncertain as well widens both, and the two contributions combine in the apparent angles.

## Sunrise and sunset

Event times are a special case, because a `DateTime` cannot carry an uncertainty.
[`transit_sunrise_sunset`](@ref) rounds to a whole second, so it returns the nominal times
however uncertain the observer is:

```@example uncertainty
transit_sunrise_sunset(Observer(52.35888 ± 5.0, 4.88185 ± 5.0), Date(2023, 6, 21)).sunrise
```

[`transit_sunrise_sunset_seconds`](@ref) keeps the observer's element type instead, giving
seconds since midnight UTC:

```@example uncertainty
transit_sunrise_sunset_seconds(obs, Date(2023, 6, 21))
```

Rounding to a whole second also costs the sub-second part, so this variant is the more
precise one even with ordinary numbers, and it is the one to use with ForwardDiff. The
`next_`/`previous_` helpers return a `DateTime` and drop the uncertainty in the same way
[`transit_sunrise_sunset`](@ref) does.
