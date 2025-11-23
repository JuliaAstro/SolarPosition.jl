# Copilot Instructions for SolarPosition.jl

This file provides guidance for GitHub Copilot when working on the SolarPosition.jl package.

## Project Overview

SolarPosition.jl provides a simple, unified interface to a collection of validated solar position algorithms written in pure Julia. The package implements various solar positioning algorithms (PSA, NOAA, Walraven, USNO, SPA) and atmospheric refraction correction models.

## Code Structure

- `src/SolarPosition.jl`: Main module file
- `src/Positioning/`: Solar position calculation algorithms
- `src/Refraction/`: Atmospheric refraction correction algorithms
- `ext/`: Package extensions (e.g., Makie integration)
- `test/`: Test files (see Testing section)
- `docs/`: Documentation

## Julia Code Style and Conventions

### General Style

1. **Indentation**: Use 4 spaces (configured in `.JuliaFormatter.toml`)
2. **Line length**: Maximum 92 characters (configured in `.JuliaFormatter.toml`)
3. **Line endings**: Unix-style LF only
4. **Formatting**: Code is automatically formatted with JuliaFormatter
   - Run manually: `julia -e 'using JuliaFormatter; format(".")'`
   - Pre-commit hooks ensure formatting before commits

### Documentation

1. **Use DocStringExtensions**: Leverage `TYPEDEF`, `TYPEDFIELDS`, and `TYPEDSIGNATURES` macros for automatic documentation

   ```julia
   """
       $(TYPEDEF)

   Description of the type.

   # Fields
   $(TYPEDFIELDS)
   """
   struct MyType
       field::Type
   end
   ```

2. **Module docstrings**: Include comprehensive module documentation at the top of each module file, listing exported types and functions

3. **Function docstrings**: Include examples where appropriate

### Type System

1. **Abstract types**: Use abstract types as base types for algorithms
   - `SolarAlgorithm` for solar position algorithms
   - `RefractionAlgorithm` for refraction correction algorithms

2. **Type parameters**: Use type parameters for numeric precision (e.g., `Observer{T<:AbstractFloat}`)

3. **Struct constructors**: Include inner constructors for validation and preprocessing when needed

### Module Organization

1. **Submodules**: Core functionality is organized into submodules:
   - `Positioning` for solar position algorithms
   - `Refraction` for atmospheric refraction models

2. **Exports**: Explicitly export public API from the main module

3. **Extensions**: Optional features (like plotting) use package extensions in the `ext/` directory

## Testing

### Test Organization

1. **Test file naming**: Create test files with the pattern `test-<feature>.jl`
   - Example: `test-psa.jl`, `test-refraction.jl`
   - These are automatically discovered and run in testsets

2. **Test structure**: Tests are automatically wrapped in `@testset` blocks based on filename

3. **Avoid modifying `runtests.jl`**: It automatically discovers and runs all `test-*.jl` files

4. **Linting tests**: Include linting tests in `linting.jl` for code quality checks

### Running Tests

```bash
# Run all tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Run from Julia REPL
julia> using Pkg
julia> Pkg.activate(".")
julia> Pkg.test()
```

## Building and Linting

### Package Installation

```bash
# Install dependencies
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Linting

The project uses pre-commit hooks for various checks:

```bash
# Install pre-commit (requires Python)
pip install pre-commit

# Run all pre-commit hooks
pre-commit run --all-files

# Individual tools:
# - JuliaFormatter: Code formatting
# - ExplicitImports: Check for explicit imports
# - markdownlint: Markdown linting
# - yamllint: YAML linting
# - typos: Spell checking
```

### CI/CD

The project uses GitHub Actions workflows:

- `Test.yml`: Runs tests on multiple Julia versions and operating systems
- `Lint.yml`: Runs linting checks including pre-commit hooks
- `Docs.yml`: Builds and deploys documentation

## Dependencies

### Core Dependencies

- `Dates`: Date/time handling
- `TimeZones`: Time zone support
- `StructArrays`: Efficient array of structures
- `Tables`: Table interface
- `DocStringExtensions`: Documentation macros

### Optional Dependencies

- `Makie`: Plotting (loaded via package extension)

## Best Practices

1. **Performance**: Write performant Julia code
   - Use type-stable functions
   - Avoid type piracy
   - Use `@inbounds` judiciously for performance-critical loops

2. **Validation**: The package includes validation against reference implementations
   - PSA, NOAA algorithms are validated against pvlib-python and solposx

3. **Issue workflow**:
   - Comment on an issue before starting work
   - Create an issue for non-trivial changes before opening a PR
   - Follow the PR template checklist

4. **Documentation**:
   - Update documentation when changing public APIs
   - Include examples in docstrings
   - Keep the README.md updated

5. **Code quality**:
   - All code must pass linting checks
   - Tests must pass on all supported platforms (Linux, macOS, Windows)
   - Maintain test coverage

## Useful Commands

```bash
# Format code
julia -e 'using Pkg; pkg"add JuliaFormatter"; using JuliaFormatter; format(".")'

# Run tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Build documentation locally
julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
julia --project=docs docs/make.jl

# Run pre-commit checks
pre-commit run --all-files
```

## Contributing

See [docs/src/contributing.md](../docs/src/contributing.md) for detailed contributing guidelines.

## References

- [JuliaFormatter documentation](https://domluna.github.io/JuliaFormatter.jl/stable/)
- [DocStringExtensions documentation](https://juliadocs.org/DocStringExtensions.jl/stable/)
- [Julia Style Guide](https://docs.julialang.org/en/v1/manual/style-guide/)
