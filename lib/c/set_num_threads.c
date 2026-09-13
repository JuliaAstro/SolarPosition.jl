/*
 * Load-time thread configuration for libsolarposition.
 *
 * JuliaC compiles its own __attribute__((constructor)) that calls jl_parse_opts with the
 * --threads and --handle-signals values baked in at build time. The Julia runtime does
 * not initialise until the first call into a @ccallable entrypoint, so there is a window
 * after dlopen in which those options can still be changed.
 *
 * Two things matter for using that window:
 *
 *   1. Assigning jl_options.nthreads directly does NOT work. The write lands, but
 *      Threads.nthreads() does not follow it; jl_parse_opts does bookkeeping beyond that
 *      field. Re-running jl_parse_opts, exactly as JuliaC's own shim does, works.
 *
 *   2. More than one thread requires handle-signals=yes. On Julia >= 1.12 a library with
 *      handle-signals=no and more than one thread segfaults during shutdown. So asking
 *      for n > 1 necessarily turns Julia's own SIGINT/SIGSEGV handlers on in the host
 *      process. That is the caller's decision to make, which is why it is a function
 *      rather than something this library does on its own.
 *      See https://github.com/JuliaLang/julia/issues/61319
 *
 * Must be called before the first solar position call. Afterwards it is a no-op as far as
 * the runtime is concerned, so it returns -2 once the runtime has started.
 */
#include <julia.h>
#include <getopt.h>
#include <stdint.h>
#include <stdio.h>

/* Set by the first successful configuration so repeat calls can be reported. */
static int solarposition_threads_configured = 0;

static int apply_option(const char *opt)
{
    /* Save the getopt state and the fields jl_parse_opts overwrites, exactly as JuliaC's
     * shim does, so the host process is left as it was found. */
    int saved_optind = optind, saved_opterr = opterr, saved_optopt = optopt;
    char *saved_optarg = optarg;
    const char *saved_image_file = jl_options.image_file;

    char *argv[] = {"juliac", (char *)opt, NULL};
    int argc = 2;
    char **argvp = argv;

    optind = 0;
    jl_parse_opts(&argc, &argvp);

    jl_options.image_file = saved_image_file;
    optind = saved_optind;
    opterr = saved_opterr;
    optopt = saved_optopt;
    optarg = saved_optarg;
    return 0;
}

/*
 * Request `n` Julia compute threads. Returns the resulting Threads.nthreads() value, or
 * -1 for n < 1 and -2 if the Julia runtime has already started.
 */
JL_DLLEXPORT int solarposition_set_num_threads(int n)
{
    char flag[32];

    if (n < 1) return -1;
    if (jl_is_initialized()) return -2;

    if (n > 1) {
        /* Required: see note 2 above. */
        apply_option("--handle-signals=yes");
    }
    snprintf(flag, sizeof(flag), "--threads=%d", n);
    apply_option(flag);
    solarposition_threads_configured = 1;

    /* jl_options.nthreads counts the interactive thread too; report the compute pool. */
    return n;
}

/* The raw jl_options.nthreads, for diagnostics. Includes the interactive thread. */
JL_DLLEXPORT int solarposition_get_option_nthreads(void)
{
    return (int)jl_options.nthreads;
}
