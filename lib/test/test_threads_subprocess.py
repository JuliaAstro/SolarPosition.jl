"""Thread-count tests that each need a fresh Julia runtime.

The thread count is fixed once the runtime starts, so these cannot share a process with
each other or with the rest of the suite. Each runs in a subprocess.
"""

import subprocess
import sys

import pytest


def run(code: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-c", code], capture_output=True, text=True, timeout=300
    )


@pytest.mark.parametrize("n", [1, 2, 4, 8])
def test_set_num_threads_takes_effect(n):
    """set_num_threads(n) before the first call must actually give n Julia threads."""
    proc = run(
        f"import solarposition as sp;"
        f"got = sp.set_num_threads({n});"
        f"print(got, sp.julia_nthreads())"
    )
    assert proc.returncode == 0, proc.stderr
    got, reported = proc.stdout.split()
    assert int(got) == n
    assert int(reported) == n


def test_default_build_is_single_threaded():
    """Without an explicit request the library must start single-threaded, which is the
    signal-safe configuration."""
    proc = run("import solarposition as sp; print(sp.julia_nthreads())")
    assert proc.returncode == 0, proc.stderr
    assert int(proc.stdout.strip()) == 1


def test_threaded_results_match_serial_with_runtime_threads():
    """Raising the thread count at runtime must not change any answer."""
    proc = run(
        "import numpy as np, solarposition as sp\n"
        "sp.set_num_threads(4)\n"
        "t = np.linspace(1687348800.0, 1687435200.0, 20000)\n"
        "a = [np.empty(len(t)) for _ in range(5)]\n"
        "b = [np.empty(len(t)) for _ in range(5)]\n"
        "sp.solar_position_inplace(52.35888, 4.88185, t, *a,"
        " algorithm=sp.Algorithm.SPA)\n"
        "sp.solar_position_inplace_threaded(52.35888, 4.88185, t, *b,"
        " algorithm=sp.Algorithm.SPA)\n"
        "c = sp.solar_position_threaded(52.35888, 4.88185, t,"
        " algorithm=sp.Algorithm.SPA)\n"
        "print(all(np.array_equal(x, y) for x, y in zip(a, b))"
        " and all(np.array_equal(x, c[:, i]) for i, x in enumerate(a)))\n"
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.strip() == "True"


def test_multithreaded_process_exits_cleanly():
    """On Julia >= 1.12 a multi-threaded library with signal handling off segfaults at
    shutdown. set_num_threads() turns signal handling on for n > 1 to avoid exactly that,
    so a threaded process must still exit 0."""
    for _ in range(5):
        proc = run(
            "import numpy as np, solarposition as sp\n"
            "sp.set_num_threads(8)\n"
            "t = np.linspace(1687348800.0, 1687435200.0, 5000)\n"
            "b = [np.empty(len(t)) for _ in range(5)]\n"
            "sp.solar_position_inplace_threaded(40.0, -105.0, t, *b,"
            " algorithm=sp.Algorithm.SPA)\n"
        )
        assert proc.returncode == 0, f"exit {proc.returncode}: {proc.stderr[-400:]}"
