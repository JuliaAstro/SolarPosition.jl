# [Adding a New Solar Position Algorithm](@id new-algorithm)

This tutorial walks you through the process of adding a new solar positioning algorithm
to `SolarPosition.jl`. We'll implement a simplified algorithm step by step, covering
all the necessary components: the algorithm struct, core computation, refraction handling,
exports, and tests.

## Overview

Adding a new algorithm involves these steps:

1. [**Create the algorithm struct**](@ref step-1-create-struct) - Define a type that subtypes [`SolarAlgorithm`](@ref SolarPosition.Positioning.SolarAlgorithm).
2. [**Implement the core function**](@ref step-2-implement-core) - Write `_solar_position` for your algorithm.
3. [**Handle refraction**](@ref step-3-handle-refraction) - Define how your algorithm interacts with `DefaultRefraction`.
4. [**Export the algorithm**](@ref step-4-export) - Make it available to users.
5. [**Write tests**](@ref step-5-write-tests) - Validate correctness against reference values.
6. [**Document**](@ref step-6-document) - Add docstrings and update documentation.
7. [**Run pre-commit checks**](@ref step-7-precommit) - Ensure code quality and formatting.

!!! info "Underscore"
    Note the underscore prefix in `_solar_position`. This function is internal
    and should not be called directly by users. Instead, they will use the public
    [`solar_position`](@ref SolarPosition.Positioning.solar_position) function, which dispatches to your implementation based on
    the algorithm type struct.

## [Step 1: Create the Algorithm Struct](@id step-1-create-struct)

Create a new file in `src/Positioning/` for your algorithm. For this example, we'll
create a simplified algorithm called `SimpleAlgorithm`.

The struct must:

- Subtype [`SolarAlgorithm`](@ref SolarPosition.Positioning.SolarAlgorithm)
- Include a docstring with `TYPEDEF` and `TYPEDFIELDS` macros
- Document accuracy and provide literature references

```julia
# src/Positioning/simple.jl

"""
    \$(TYPEDEF)

Simple solar position algorithm for demonstration purposes.

This algorithm uses basic spherical trigonometry to compute solar positions.
It is provided as a teaching example and is NOT suitable for production use.

# Accuracy
This is a simplified algorithm with limited accuracy (±1°).

# Literature
Based on basic solar geometry principles.

# Fields
\$(TYPEDFIELDS)
"""
struct SimpleAlgorithm <: SolarAlgorithm
    "Optional configuration parameter"
    param::Float64
end

# Provide a default constructor
SimpleAlgorithm() = SimpleAlgorithm(1.0)
```

## [Step 2: Implement the Core Function](@id step-2-implement-core)

The core of any algorithm is the `_solar_position` function. This function:

- Takes an [`Observer`](@ref SolarPosition.Positioning.Observer), `DateTime`, and your algorithm type
- Returns a [`SolPos{T}`](@ref SolarPosition.Positioning.SolPos) with azimuth, elevation, and zenith angles
- Should be type-stable and performant

Here's the basic structure:

```julia
function _solar_position(obs::Observer{T}, dt::DateTime, alg::SimpleAlgorithm) where {T}
    # 1. Convert datetime to Julian date
    jd = datetime2julian(dt)

    # 2. Calculate days since J2000.0 epoch
    n = jd - 2451545.0

    # 3. Compute solar coordinates (declination, hour angle, etc.)
    # ... your algorithm's calculations here ...

    # 4. Calculate local horizontal coordinates
    # ... azimuth and elevation calculations ...

    # 5. Return the result
    return SolPos{T}(azimuth_deg, elevation_deg, zenith_deg)
end
```

### Key Implementation Notes

1. **Use helper functions** from `utils.jl`:
   - `fractional_hour(dt)` - Convert time to decimal hours
   - `deg2rad(x)` / `rad2deg(x)` - Angle conversions

2. **Observer properties** are pre-computed for efficiency:
   - `obs.latitude`, `obs.longitude`, `obs.altitude` - Input values
   - `obs.latitude_rad`, `obs.longitude_rad` - Radians versions
   - `obs.sin_lat`, `obs.cos_lat` - Precomputed trigonometric values

3. **Type parameter `T`** ensures numerical precision is preserved from the `Observer`

4. **Angle conventions**:
   - Azimuth: 0° = North, positive clockwise, range [0°, 360°]
   - Elevation: angle above horizon, range [-90°, 90°]
   - Zenith: 90° - elevation, range [0°, 180°]

## [Step 3: Handle Default Refraction](@id step-3-handle-refraction)

Each algorithm must specify how it handles `DefaultRefraction`. There are two common
patterns:

### Pattern A: No Refraction by Default (like [`PSA`](@ref SolarPosition.Positioning.PSA))

If your algorithm should NOT apply refraction by default:

```julia
function _solar_position(obs, dt, alg::SimpleAlgorithm, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, NoRefraction())
end

# Return type for DefaultRefraction
result_type(::Type{SimpleAlgorithm}, ::Type{DefaultRefraction}, ::Type{T}) where {T} =
    SolPos{T}
```

### Pattern B: Apply Refraction by Default (like [`NOAA`](@ref SolarPosition.Positioning.NOAA))

If your algorithm should apply a specific refraction model by default:

```julia
using ..Refraction: HUGHES, DefaultRefraction

function _solar_position(obs, dt, alg::SimpleAlgorithm, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, HUGHES())
end

# Return type for DefaultRefraction
result_type(::Type{SimpleAlgorithm}, ::Type{DefaultRefraction}, ::Type{T}) where {T} =
    ApparentSolPos{T}
```

The `result_type` function tells the system what return type to expect, enabling
type-stable code for vectorized operations.

## [Step 4: Export the Algorithm](@id step-4-export)

After implementing your algorithm, you need to export it so users can access it.

### 4.1 Include in Positioning Module

Edit `src/Positioning/Positioning.jl` to include your new file:

```julia
# Near the bottom of the file, with other includes
include("utils.jl")
include("deltat.jl")
include("psa.jl")
include("noaa.jl")
include("walraven.jl")
include("usno.jl")
include("spa.jl")
include("simple.jl")  # Add your new file

# Add to the export list
export Observer,
    PSA,
    NOAA,
    Walraven,
    USNO,
    SPA,
    SimpleAlgorithm,  # Add your algorithm
    solar_position,
    solar_position!,
    SolPos,
    ApparentSolPos,
    SPASolPos
```

### 4.2 Export from Main Module

Edit `src/SolarPosition.jl` to re-export your algorithm:

```julia
using .Positioning:
    Observer, PSA, NOAA, Walraven, USNO, SPA, SimpleAlgorithm, solar_position, solar_position!

# ... later in exports ...
export PSA, NOAA, Walraven, USNO, SPA, SimpleAlgorithm
```

## [Step 5: Write Tests](@id step-5-write-tests)

Create a test file following the naming convention `test/test-simple.jl`.

!!! warning "Generating Validation Data"
    It is required to validate your algorithm against known reference values. You
    can use a reference implementation of your algorithm (if available) or compare against
    trusted solar position calculators. Store these reference values in your test file
    and use `@test` statements to ensure your implementation matches them. See the
    existing test files like `test/test-psa.jl` for examples of how to structure these tests.

### Running Tests

Tests are automatically discovered by `runtests.jl`. Run them with:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

Or from the Julia REPL:

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

## [Step 6: Document Your Algorithm](@id step-6-document)

### Add to Documentation Pages

Update `docs/src/positioning.md` to include your algorithm in the algorithm reference
section.

### Add Literature References

If your algorithm is based on published work, add the reference to `docs/src/refs.bib`:

```bibtex
@article{YourReference,
    author = {Author Name},
    title = {Algorithm Title},
    journal = {Journal Name},
    year = {2024},
    volume = {1},
    pages = {1-10}
}
```

Then cite it in your docstring using `[YourReference](@cite)`.

## [Step 7: Run Pre-commit Checks (Recommended)](@id step-7-precommit)

Before submitting a pull request, it's recommended to run pre-commit hooks locally
to catch formatting and linting issues early. This saves time during code review
and ensures your code meets the project's quality standards. The pre-commit configuration
is defined in the `.pre-commit-config.yaml` file at the root of the repository.

!!! info "CI Runs Pre-commit"
    Even if you skip this step locally, GitHub CI will automatically run pre-commit
    checks on your pull request. However, running them locally first helps you catch
    and fix issues before pushing.

### Installing Pre-commit

```bash
# Install pre-commit (requires Python)
pip install pre-commit

# Install the git hooks (run once per clone)
pre-commit install
```

### Running Pre-commit

```bash
# Run all hooks on all files
pre-commit run --all-files

# Or run on staged files only
pre-commit run
```

Pre-commit runs several checks including:

- **JuliaFormatter** - Ensures consistent code formatting
- **ExplicitImports** - Checks for explicit imports
- **markdownlint** - Lints markdown files
- **typos** - Catches common spelling mistakes

If any checks fail, fix the issues and run pre-commit again until all checks pass.

## Checklist

Before submitting your algorithm for review, ensure you've completed the following:

| Task | Description |
| ---- | ----------- |
| Algorithm struct | Subtypes [`SolarAlgorithm`](@ref SolarPosition.Positioning.SolarAlgorithm) |
| Docstring | Includes `TYPEDEF`, `TYPEDFIELDS`, accuracy, and references |
| `_solar_position` | Function implemented with correct signature |
| Default refraction | Handling defined for [`DefaultRefraction`](@ref SolarPosition.Refraction.DefaultRefraction)  |
| `result_type` | Function defined for [`DefaultRefraction`](@ref SolarPosition.Refraction.DefaultRefraction) |
| Export | Algorithm exported from both modules |
| Tests | Cover basic functionality, refraction, vectors, and edge cases |
| Test coverage | Ensure tests cover all new code paths |
| Pre-commit | Checks pass (recommended locally, required in CI) |
| Documentation | Add your algorithm to the list of available algorithms and update the tables in `positioning.md`, `README.md` and `refraction.md` if needed |
| Literature | References added to `refs.bib` and cited in docstrings |

## Additional Resources

- See existing implementations in `src/Positioning/` for reference:
  - `psa.jl` - Simple algorithm with no default refraction ([`PSA`](@ref SolarPosition.Positioning.PSA))
  - `noaa.jl` - Algorithm with default [`HUGHES`](@ref SolarPosition.Refraction.HUGHES) refraction ([`NOAA`](@ref SolarPosition.Positioning.NOAA))
  - `spa.jl` - Complex algorithm with additional output fields ([`SPA`](@ref SolarPosition.Positioning.SPA))
- Check the [Contributing Guidelines](@ref contributing) for general contribution workflow
- Review the [Solar Positioning Algorithms](@ref solar-positioning-algorithms) page for context
