#!/usr/bin/env julia
#
# Build libsolarposition and its C header and Python package.
#
#     julia --project=lib lib/build.jl                # default: signal-safe, 1 thread
#     julia --project=lib lib/build.jl --threads=4    # threaded, see the caveat below
#     julia --project=lib lib/build.jl --verbose
#
# ## The two builds
#
# The default build sets `threads=1` and `handle-signals=no`. Those are JuliaC's defaults
# for a library and the correct mode for embedding: Python keeps its own SIGINT/SIGSEGV
# handlers, so Ctrl-C behaves normally. This is the build the wheel ships.
#
# The threaded build sets `threads=N` and `handle-signals=yes`. The second half is not
# optional: on Julia >= 1.12 a library with more than one thread and signal handling off
# segfaults during shutdown, and JuliaC's own validation step rejects the combination. The
# cost is that Julia installs its own signal handlers into the host process. Upstream
# tracking issue: https://github.com/JuliaLang/julia/issues/61319
#
# The thread count is fixed at compile time. It cannot be chosen when the library loads:
# JuliaC compiles an `__attribute__((constructor))` shim that calls `jl_parse_opts` with
# `--threads=<N>` before `jl_init`, which overrides `JULIA_NUM_THREADS`, and by the time
# Python has `dlopen`ed the library that constructor has already run.
#
# ## Why the threaded path drives JuliaC directly
#
# JuliaLibWrapping 0.2's `build_library` does not forward `jl_options` to
# `JuliaC.ImageRecipe`, so the thread count cannot be set through it. Both builds produce
# byte-identical wrappers and ABI metadata — only the `.so` differs — so the threaded path
# runs the normal `standard_build` first and then recompiles just the library and bundle
# with `jl_options` set. Delete `build_threaded_library` once JuliaLibWrapping grows a
# `jl_options` passthrough.

push!(LOAD_PATH, joinpath(@__DIR__, "build-env"))
using JuliaC: BundleRecipe, ImageRecipe, LinkRecipe, bundle_products, compile_products,
    link_products
using JuliaLibWrapping: standard_build
using TOML: TOML

const LIBNAME = "libsolarposition"
const PYPKG = "solarposition"

flag(args, name) = name in args

function parse_threads(args)
    for a in args
        startswith(a, "--threads=") || continue
        return a[(length("--threads=") + 1):end]
    end
    return "1"
end

# `juliac` relocates the project into a temporary directory to build it, which breaks the
# relative paths this project uses to reach SolarPosition one level up. `build_library`
# has a private helper for this; the threaded path needs its own. Paths are resolved
# against the original project directory, matching what JuliaLibWrapping does, so the
# manifest keeps pointing at the real package rather than into the copy.
function absolutize_paths!(table, base)
    table isa AbstractDict || return
    p = get(table, "path", nothing)
    if p isa AbstractString && !isabspath(p)
        abs = abspath(joinpath(base, p))
        ispath(abs) || error("path \"$p\" resolves to $abs, which does not exist")
        table["path"] = abs
    end
    for (_, v) in table
        if v isa AbstractDict
            absolutize_paths!(v, base)
        elseif v isa AbstractVector
            foreach(e -> absolutize_paths!(e, base), v)
        end
    end
    return
end

function materialize_project(project::AbstractString)
    dir = mktempdir()
    for entry in readdir(project)
        entry in ("out", "test", "build-env") && continue   # not needed to compile
        cp(joinpath(project, entry), joinpath(dir, entry); force = true)
    end
    for name in ("Project.toml", "Manifest.toml")
        path = joinpath(dir, name)
        isfile(path) || continue
        toml = TOML.parsefile(path)
        absolutize_paths!(toml, project)
        open(path, "w") do io
            TOML.print(io, toml)
        end
    end
    return dir
end

"""
Recompile the library and its bundle with `jl_options` set and the load-time thread shim
linked in, then refresh the bundle copy inside the generated Python package. Everything
else from `standard_build` — the ABI JSON, the C header, `_lowlevel.py`, `_facade.py` —
is independent of this and is left alone.

This runs for every build, not just threaded ones, because `standard_build` can pass
neither `c_sources` nor `jl_options` to `JuliaC.ImageRecipe`.
"""
function rebuild_library(dir, out, threads, handle_signals; verbose::Bool)
    entry = joinpath(dir, "src", LIBNAME * ".jl")
    bundle_dir = joinpath(out, LIBNAME * "-bundle")
    project = materialize_project(dir)

    img = ImageRecipe(;
        output_type = "--output-lib",
        file = entry,
        project,
        trim_mode = "safe",
        add_ccallables = true,
        export_abi = joinpath(out, LIBNAME * ".abi.json"),
        verbose,
        c_sources = [joinpath(dir, "c", "set_num_threads.c")],
        jl_options = Dict("threads" => threads, "handle-signals" => handle_signals),
    )
    # `@bundle` is required for a relocatable wheel; without it the `.so` bakes in
    # absolute paths to this machine's Julia installation.
    link = LinkRecipe(;
        image_recipe = img, outname = joinpath(out, LIBNAME), rpath = "@bundle",
    )
    compile_products(img)
    link_products(link)

    # `juliac --bundle` refuses to overwrite an existing tree.
    ispath(bundle_dir) && rm(bundle_dir; recursive = true)
    bundle_products(
        BundleRecipe(; link_recipe = link, output_dir = bundle_dir, privatize = true),
    )

    pkg_bundle = joinpath(out, PYPKG, "bundle")
    ispath(pkg_bundle) && rm(pkg_bundle; recursive = true)
    cp(bundle_dir, pkg_bundle)
    return bundle_dir
end

const EXTRAS_MARKER = "# Appended by lib/build.jl: hand-maintained wrappers from _extras.py."

"""
The names `_extras.py` exports, read out of its `__all__` literal.

Parsed rather than hardcoded so that adding a wrapper there is enough to have it shadow
the generated one: a name listed in `__all__` but missing from the appended import would
be reachable through `from ._facade import *` while the generated definition still won.
"""
function extras_exports(path)
    text = read(path, String)
    m = match(r"^__all__\s*=\s*\[(.*?)\]"ms, text)
    m === nothing && error("no __all__ literal in $path")
    return [String(x.captures[1]) for x in eachmatch(r"\"([^\"]+)\"", m.captures[1])]
end

"""
Install the hand-maintained Python additions from `lib/python/` into the generated
package. `_extras.py` becomes a module of its own, and one import is appended to the
generated `_facade.py` so its definitions win. See `lib/python/_extras.py` for why some
entrypoints need this.
"""
function install_python_extras(dir, out)
    extras = joinpath(dir, "python", "_extras.py")
    isfile(extras) || return false
    cp(extras, joinpath(out, PYPKG, "_extras.py"); force = true)
    names = extras_exports(extras)
    facade = joinpath(out, PYPKG, "_facade.py")
    text = read(facade, String)
    # Truncate any block from an earlier build before appending, so a changed export list
    # replaces the old import instead of stacking a second one on top of it.
    idx = findfirst(EXTRAS_MARKER, text)
    idx === nothing || (text = rstrip(text[1:(first(idx) - 1)]) * "\n")
    open(facade, "w") do io
        print(io, text)
        println(io)
        println(io, EXTRAS_MARKER)
        println(io, "# The import shadows the generated definitions; the __all__ update is")
        println(io, "# what makes the new names reachable through `from ._facade import *`.")
        println(io, "from ._extras import $(join(names, ", "))  # noqa: F811,E402")
        println(io, "from ._extras import __all__ as _extras_all  # noqa: E402")
        println(io, "__all__ = sorted(set(__all__) | set(_extras_all))")
    end
    return true
end

function main(args)
    threads = parse_threads(args)
    verbose = flag(args, "--verbose")
    out = joinpath(@__DIR__, "out")

    @info "Building $LIBNAME" threads handle_signals =
        (threads == "1" ? "no" : "yes")

    # JuliaLibWrapping writes `_facade.py` once and never overwrites it, so a renamed or
    # deleted entrypoint would otherwise survive as a definition calling a `_lowlevel`
    # symbol that no longer exists. Nothing in it is hand-edited -- the hand-maintained
    # wrappers live in `python/_extras.py` and are appended below -- so regenerate it.
    facade = joinpath(out, PYPKG, "_facade.py")
    isfile(facade) && rm(facade)

    result = standard_build(
        @__DIR__;
        libname = LIBNAME,
        python_package = PYPKG,
        bundle = true,
        verbose,
    )

    install_python_extras(@__DIR__, out)

    if threads != "1"
        @warn """
        Threaded build: Julia will install its own SIGINT/SIGSEGV handlers into the host
        process, because more than one thread requires handle-signals=yes on Julia >= 1.12.
        A default build can raise the thread count at load time instead, via
        solarposition.set_num_threads(). See https://github.com/JuliaLang/julia/issues/61319
        """
    end
    rebuild_library(@__DIR__, out, threads, threads == "1" ? "no" : "yes"; verbose)

    @info "Build complete" library = result.library abi = result.abi_path
    @info "Python package" path = joinpath(out, PYPKG) install = "pip install $out"
    return result
end

main(ARGS)

pop!(LOAD_PATH)
