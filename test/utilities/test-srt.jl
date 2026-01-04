"""Unit tests for sunrise and sunset time calculations"""

using Test
using SolarPosition.Utilities:
    TransitSunriseSunset,
    transit_sunrise_sunset,
    next_sunrise,
    next_sunset,
    next_solar_noon,
    previous_sunrise,
    previous_sunset,
    previous_solar_noon
using SolarPosition.Positioning: Observer, SPA
using TimeZones: TimeZones, ZonedDateTime, timezone, FixedTimeZone, UTC
using Dates: Dates, DateTime, Date, datetime2unix, Day, Hour

include("expected-values.jl")

# Common test locations
const OBS_NEW_YORK = Observer(40.7128, -74.006)
const OBS_LONDON = Observer(51.5074, -0.1278)
const OBS_POLAR = Observer(78.2232, 15.6267)  # Longyearbyen, Svalbard

# Common test dates
const TEST_DATE = Date(2020, 6, 21)  # summer solstice
const TEST_DATETIME = DateTime(2020, 6, 21, 0, 0, 0)
const WINTER_DATETIME = DateTime(2025, 1, 15, 0, 0, 0)
const SUMMER_DATETIME = DateTime(2025, 6, 21, 0, 0, 0)

# Common timezones
const TZ_NY = TimeZones.TimeZone("America/New_York")
const TZ_OSLO = FixedTimeZone("UTC+1", 3600)

# Helper function to test transit/sunrise/sunset results
function test_srt_result(result, row, to_datetime_fn)
    for field in (:transit, :sunrise, :sunset)
        expected = datetime2unix(DateTime(getproperty(row, field)))
        actual = datetime2unix(to_datetime_fn(getproperty(result, field)))
        @test actual ≈ expected atol = 1.0
    end
end

@testset "SPA" begin
    df = expected_srt_spa()
    fields = (:sunset, :sunrise, :transit)

    @testset "DateTime input - Location: $(row.location), Date: $(row.date)" for row in
                                                                                 eachrow(df)
        obs = Observer(row.latitude, row.longitude)
        dt_input = DateTime(row.date)
        result = transit_sunrise_sunset(obs, dt_input, SPA(delta_t = row.delta_t))

        @test all(
            getfield(result, field) isa DateTime for field in (:transit, :sunrise, :sunset)
        )
        test_srt_result(result, row, identity)
    end

    @testset "Date input - Location: $(row.location), Date: $(row.date)" for row in
                                                                             eachrow(df)
        obs = Observer(row.latitude, row.longitude)
        date_input = Date(row.date)
        result = transit_sunrise_sunset(obs, date_input, SPA(delta_t = row.delta_t))

        @test all(
            getfield(result, field) isa DateTime for field in (:transit, :sunrise, :sunset)
        )
        test_srt_result(result, row, identity)
    end

    @testset "ZonedDateTime input - Location: $(row.location), Date: $(row.date)" for row in
                                                                                      eachrow(
        df,
    )
        obs = Observer(row.latitude, row.longitude)
        dt_utc = DateTime(row.date)
        zdt_input = ZonedDateTime(dt_utc, row.timezone; from_utc = true)
        result = transit_sunrise_sunset(obs, zdt_input, SPA(delta_t = row.delta_t))

        for field in (:transit, :sunrise, :sunset)
            @test getfield(result, field) isa ZonedDateTime
            @test timezone(getfield(result, field)) == row.timezone
        end

        test_srt_result(result, row, dt -> DateTime(dt, UTC))
    end

    @testset "Polar day/night cases" begin
        result_polar_night = @test_logs (
            :warn,
            r"Sun does not rise or set.*polar night \(sun below horizon\)",
        ) transit_sunrise_sunset(OBS_POLAR, WINTER_DATETIME, SPA())

        @test result_polar_night.transit isa DateTime
        @test result_polar_night.transit == result_polar_night.sunrise
        @test result_polar_night.sunrise == result_polar_night.sunset
        @test result_polar_night.transit == WINTER_DATETIME

        result_polar_day =
            @test_logs (:warn, r"Sun does not rise or set.*polar day \(sun above horizon\)") transit_sunrise_sunset(
                OBS_POLAR,
                SUMMER_DATETIME,
                SPA(),
            )

        @test result_polar_day.transit isa DateTime
        @test result_polar_day.transit == result_polar_day.sunrise
        @test result_polar_day.sunrise == result_polar_day.sunset
        @test result_polar_day.transit == SUMMER_DATETIME

        zdt_winter = ZonedDateTime(WINTER_DATETIME, TZ_OSLO; from_utc = true)
        result_zdt_polar_night =
            @test_logs (:warn, r"Sun does not rise or set.*polar night") transit_sunrise_sunset(
                OBS_POLAR,
                zdt_winter,
                SPA(),
            )

        @test result_zdt_polar_night.transit isa ZonedDateTime
        @test timezone(result_zdt_polar_night.transit) == TZ_OSLO
        @test DateTime(result_zdt_polar_night.transit, UTC) == WINTER_DATETIME
    end

    @testset "delta_t parameter" begin
        result_auto = transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATETIME, SPA())
        result_nothing =
            transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATETIME, SPA(delta_t = nothing))
        result_zero =
            transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATETIME, SPA(delta_t = 0.0))
        result_custom =
            transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATETIME, SPA(delta_t = 69.0))

        @test result_auto.transit isa DateTime
        @test result_nothing.transit isa DateTime
        @test result_zero.sunrise isa DateTime
        @test result_custom.sunset isa DateTime

        # delta_t = nothing should use automatic calculation (calculate_deltat)
        # This should give the same result as the default (which is delta_t = 67.0)
        # but different from delta_t = 0.0
        @test result_nothing.transit != result_zero.transit ||
              result_nothing.sunrise != result_zero.sunrise ||
              result_nothing.sunset != result_zero.sunset

        @test result_auto.transit != result_zero.transit ||
              result_auto.sunrise != result_zero.sunrise ||
              result_auto.sunset != result_zero.sunset

        @test result_zero.transit != result_custom.transit ||
              result_zero.sunrise != result_custom.sunrise ||
              result_zero.sunset != result_custom.sunset

        @test abs(datetime2unix(result_auto.transit) - datetime2unix(result_zero.transit)) <
              300
        @test abs(
            datetime2unix(result_auto.sunrise) - datetime2unix(result_custom.sunrise),
        ) < 300
    end

    @testset "next_sunrise, next_sunset, next_solar_noon" begin
        result = transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATE, SPA())
        next_day_result = transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATE + Day(1), SPA())
        london_result = transit_sunrise_sunset(OBS_LONDON, TEST_DATE, SPA())

        # Define test cases: (function, field, before_time, after_time)
        test_cases = [
            (next_sunrise, :sunrise, result.sunrise - Hour(1), result.sunrise + Hour(1)),
            (next_sunset, :sunset, result.sunset - Hour(1), result.sunset + Hour(1)),
            (next_solar_noon, :transit, result.transit - Hour(1), result.transit + Hour(1)),
        ]

        for (func, field, before_time, after_time) in test_cases
            @testset "$(func) before/after event" begin
                @test func(OBS_NEW_YORK, before_time, SPA()) == getfield(result, field)
                @test func(OBS_NEW_YORK, after_time, SPA()) ==
                      getfield(next_day_result, field)
                @test func(OBS_NEW_YORK, getfield(result, field), SPA()) ==
                      getfield(next_day_result, field)
            end

            @testset "$(func) Date input" begin
                @test func(OBS_NEW_YORK, TEST_DATE, SPA()) == getfield(result, field)
            end

            @testset "$(func) different location" begin
                @test func(OBS_LONDON, DateTime(TEST_DATE), SPA()) ==
                      getfield(london_result, field)
            end

            @testset "$(func) ZonedDateTime input" begin
                zdt_before = ZonedDateTime(before_time, TZ_NY; from_utc = true)
                zdt_result = func(OBS_NEW_YORK, zdt_before, SPA())
                @test zdt_result isa ZonedDateTime
                @test timezone(zdt_result) == TZ_NY
                @test DateTime(zdt_result, UTC) == getfield(result, field)

                zdt_after = ZonedDateTime(after_time, TZ_NY; from_utc = true)
                zdt_next_result = func(OBS_NEW_YORK, zdt_after, SPA())
                @test zdt_next_result isa ZonedDateTime
                @test timezone(zdt_next_result) == TZ_NY
                @test DateTime(zdt_next_result, UTC) == getfield(next_day_result, field)
            end
        end
    end

    @testset "previous_sunrise, previous_sunset, previous_solar_noon" begin
        result = transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATE, SPA())
        prev_day_result = transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATE - Day(1), SPA())

        # Define test cases: (function, field, before_time, after_time)
        test_cases = [
            (
                previous_sunrise,
                :sunrise,
                result.sunrise - Hour(1),
                result.sunrise + Hour(1),
            ),
            (previous_sunset, :sunset, result.sunset - Hour(1), result.sunset + Hour(1)),
            (
                previous_solar_noon,
                :transit,
                result.transit - Hour(1),
                result.transit + Hour(1),
            ),
        ]

        for (func, field, before_time, after_time) in test_cases
            @testset "$(func) before/after event" begin
                @test func(OBS_NEW_YORK, after_time, SPA()) == getfield(result, field)
                @test func(OBS_NEW_YORK, before_time, SPA()) ==
                      getfield(prev_day_result, field)
                @test func(OBS_NEW_YORK, getfield(result, field), SPA()) ==
                      getfield(prev_day_result, field)
            end

            @testset "$(func) Date input at midnight" begin
                @test func(OBS_NEW_YORK, TEST_DATE, SPA()) ==
                      getfield(prev_day_result, field)
            end

            @testset "$(func) ZonedDateTime input" begin
                zdt_after = ZonedDateTime(after_time, TZ_NY; from_utc = true)
                zdt_result = func(OBS_NEW_YORK, zdt_after, SPA())
                @test zdt_result isa ZonedDateTime
                @test timezone(zdt_result) == TZ_NY
                @test DateTime(zdt_result, UTC) == getfield(result, field)

                zdt_before = ZonedDateTime(before_time, TZ_NY; from_utc = true)
                zdt_prev_result = func(OBS_NEW_YORK, zdt_before, SPA())
                @test zdt_prev_result isa ZonedDateTime
                @test timezone(zdt_prev_result) == TZ_NY
                @test DateTime(zdt_prev_result, UTC) == getfield(prev_day_result, field)
            end
        end

        @testset "Symmetry with next functions" begin
            current_time = result.transit + Hour(3)
            symmetry_cases = [
                (next_sunrise, previous_sunrise),
                (next_sunset, previous_sunset),
                (next_solar_noon, previous_solar_noon),
            ]

            for (next_func, prev_func) in symmetry_cases
                next_event = next_func(OBS_NEW_YORK, current_time, SPA())
                prev_event = prev_func(OBS_NEW_YORK, current_time, SPA())
                @test prev_event < current_time < next_event
            end
        end
    end

    @testset "Non-midnight DateTime inputs (automatic normalization)" begin
        result_midnight = transit_sunrise_sunset(OBS_NEW_YORK, DateTime(TEST_DATE), SPA())

        dt_morning = DateTime(2020, 6, 21, 8, 30, 45)
        dt_noon = DateTime(2020, 6, 21, 12, 0, 0)
        dt_afternoon = DateTime(2020, 6, 21, 15, 45, 30)
        dt_evening = DateTime(2020, 6, 21, 20, 15, 0)

        @testset "Various times during day normalize to midnight" begin
            for dt_test in [dt_morning, dt_noon, dt_afternoon, dt_evening]
                result = transit_sunrise_sunset(OBS_NEW_YORK, dt_test, SPA())
                @test result.transit == result_midnight.transit
                @test result.sunrise == result_midnight.sunrise
                @test result.sunset == result_midnight.sunset
            end
        end

        @testset "ZonedDateTime at non-midnight" begin
            zdt_afternoon = ZonedDateTime(2020, 6, 21, 15, 30, 0, TZ_NY)
            result_zdt = transit_sunrise_sunset(OBS_NEW_YORK, zdt_afternoon, SPA())

            @test DateTime(result_zdt.transit, UTC) == result_midnight.transit
            @test DateTime(result_zdt.sunrise, UTC) == result_midnight.sunrise
            @test DateTime(result_zdt.sunset, UTC) == result_midnight.sunset

            @test timezone(result_zdt.transit) == TZ_NY
            @test timezone(result_zdt.sunrise) == TZ_NY
            @test timezone(result_zdt.sunset) == TZ_NY
        end

        @testset "Next/previous functions with non-midnight inputs" begin
            dt_afternoon_utc = DateTime(2020, 6, 21, 15, 30, 0)
            next_day_result =
                transit_sunrise_sunset(OBS_NEW_YORK, TEST_DATE + Day(1), SPA())

            next_sr = next_sunrise(OBS_NEW_YORK, dt_afternoon_utc, SPA())
            @test next_sr == next_day_result.sunrise

            prev_sr = previous_sunrise(OBS_NEW_YORK, dt_afternoon_utc, SPA())
            @test prev_sr == result_midnight.sunrise
        end
    end
end
