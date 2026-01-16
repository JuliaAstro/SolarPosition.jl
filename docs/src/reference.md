# [API reference](@id reference)

This page provides comprehensive documentation for all functions and types in SolarPosition.jl.

## Contents

```@contents
Pages = ["reference.md"]
```

## Index

```@index
Pages = ["reference.md"]
```

## Core Functions

```@docs
SolarPosition.Positioning.solar_position
SolarPosition.Positioning.solar_position!
```

## Observer and Position Types

```@docs
SolarPosition.Positioning.AbstractObserver
SolarPosition.Positioning.Observer
SolarPosition.Positioning.SolPos
SolarPosition.Positioning.ApparentSolPos
SolarPosition.Positioning.SPAObserver
```

## Algorithm Base Types

SolarPosition.jl uses a type hierarchy for algorithms:

```@docs
SolarPosition.Positioning.SolarAlgorithm
SolarPosition.Refraction.RefractionAlgorithm
```

## Modules

```@docs
SolarPosition.Positioning
SolarPosition.Refraction
```
