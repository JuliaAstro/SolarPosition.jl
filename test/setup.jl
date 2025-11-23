"""Common test setup code for SolarPosition.jl"""

using DataFrames
using TimeZones
using Dates

include("expected-values.jl")

function test_conditions()
    inputs = DataFrame(
        time = [
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30:10+00:00",
            "2020-10-17T12:30+02:00",
            "2020-10-17T12:30-02:00",
            "2020-02-29T12:30+00:00",
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30+00:00",
            "1800-10-17T12:30+00:00",
            "2200-10-17T12:30+00:00",
            "2020-10-17T03:30+00:00",
            "2020-10-17T05:50+00:00",
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30+00:00",
            "2020-10-17T12:30+00:00",
        ],
        latitude = [
            45.0,
            45.0,
            45.0,
            45.0,
            45.0,
            90.0,
            0.0,
            -90.0,
            -45.0,
            45.0,
            45.0,
            45.0,
            45.0,
            45.0,
            45.0,
            45.0,
            45.0,
            45.0,
            45.0,
        ],
        longitude = [
            10.0,
            10.0,
            10.0,
            10.0,
            10.0,
            10.0,
            10.0,
            10.0,
            10.0,
            -15.0,
            -180.0,
            180.0,
            10.0,
            10.0,
            10.0,
            10.0,
            10.0,
            10.0,
            10.0,
        ],
        altitude = [
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            0.0,
            -100.0,
            4000.0,
        ],
    )

    # parse times as ZonedDateTime
    inputs.time = [
        try
            ZonedDateTime(t, dateformat"yyyy-mm-ddTHH:MM:SSzzzz")
        catch
            ZonedDateTime(t, dateformat"yyyy-mm-ddTHH:MMzzzz")
        end for t in inputs.time
    ]
    return inputs
end
