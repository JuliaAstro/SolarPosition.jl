"""Unit tests for sunrise and sunset time calculations"""

using Test
using SolarPosition.Utilities: TransitSunriseSunset, transit_sunrise_sunset
using SolarPosition.Positioning: Observer, SPA
using TimeZones: TimeZones, ZonedDateTime, timezone, FixedTimeZone, UTC
using Dates: Dates, DateTime, Date, datetime2unix, Day, Hour

include("expected-values.jl")

@testset "SPA" begin
    df = expected_srt_spa()

    @testset "DateTime input - Location: $(row.location), Date: $(row.date)" for row in
                                                                                 eachrow(df)
        obs = Observer(row.latitude, row.longitude)
        # Test with DateTime input - should return DateTime
        # Convert ZonedDateTime to DateTime (UTC)
        dt_input = DateTime(row.date)
        result = transit_sunrise_sunset(obs, dt_input, SPA(delta_t = row.delta_t))

        # Result should be DateTime type
        @test result.transit isa DateTime
        @test result.sunrise isa DateTime
        @test result.sunset isa DateTime

        expected_transit = datetime2unix(DateTime(row.transit))
        expected_sunrise = datetime2unix(DateTime(row.sunrise))
        expected_sunset = datetime2unix(DateTime(row.sunset))

        # compare unix timestamps with a few seconds tolerance
        @test datetime2unix(result.transit) ≈ expected_transit atol = 1.0
        @test datetime2unix(result.sunrise) ≈ expected_sunrise atol = 1.0
        @test datetime2unix(result.sunset) ≈ expected_sunset atol = 1.0
    end

    @testset "Date input - Location: $(row.location), Date: $(row.date)" for row in
                                                                             eachrow(df)
        obs = Observer(row.latitude, row.longitude)
        # Test with Date input - should return DateTime
        date_input = Date(row.date)
        result = transit_sunrise_sunset(obs, date_input, SPA(delta_t = row.delta_t))

        # Result should be DateTime type (same as DateTime input)
        @test result.transit isa DateTime
        @test result.sunrise isa DateTime
        @test result.sunset isa DateTime

        expected_transit = datetime2unix(DateTime(row.transit))
        expected_sunrise = datetime2unix(DateTime(row.sunrise))
        expected_sunset = datetime2unix(DateTime(row.sunset))

        # compare unix timestamps with a few seconds tolerance
        # Results should be identical to DateTime input tests
        @test datetime2unix(result.transit) ≈ expected_transit atol = 1.0
        @test datetime2unix(result.sunrise) ≈ expected_sunrise atol = 1.0
        @test datetime2unix(result.sunset) ≈ expected_sunset atol = 1.0
    end

    @testset "ZonedDateTime input - Location: $(row.location), Date: $(row.date)" for row in
                                                                                      eachrow(
        df,
    )
        obs = Observer(row.latitude, row.longitude)
        # Use the same instant as the DateTime test (midnight UTC)
        # but express it in the location's timezone
        dt_utc = DateTime(row.date)
        zdt_input = ZonedDateTime(dt_utc, row.timezone; from_utc = true)

        # Test with ZonedDateTime input - should return ZonedDateTime in same timezone
        result = transit_sunrise_sunset(obs, zdt_input, SPA(delta_t = row.delta_t))

        # Result should be ZonedDateTime type in the correct timezone
        @test result.transit isa ZonedDateTime
        @test result.sunrise isa ZonedDateTime
        @test result.sunset isa ZonedDateTime
        @test timezone(result.transit) == row.timezone
        @test timezone(result.sunrise) == row.timezone
        @test timezone(result.sunset) == row.timezone

        expected_transit = datetime2unix(DateTime(row.transit))
        expected_sunrise = datetime2unix(DateTime(row.sunrise))
        expected_sunset = datetime2unix(DateTime(row.sunset))

        # compare unix timestamps with a few seconds tolerance
        # Convert ZonedDateTime to UTC before converting to DateTime for comparison
        @test datetime2unix(DateTime(result.transit, UTC)) ≈ expected_transit atol = 1.0
        @test datetime2unix(DateTime(result.sunrise, UTC)) ≈ expected_sunrise atol = 1.0
        @test datetime2unix(DateTime(result.sunset, UTC)) ≈ expected_sunset atol = 1.0
    end

    @testset "Polar day/night cases" begin
        # polar night (sun doesn't rise) - Longyearbyen, Svalbard in winter
        obs_polar = Observer(78.2232, 15.6267)
        dt_winter = DateTime(2025, 1, 15, 0, 0, 0)  # mid-winter

        # test that warning is thrown for polar night with DateTime input
        result_polar_night = @test_logs (
            :warn,
            r"Sun does not rise or set.*polar night \(sun below horizon\)",
        ) transit_sunrise_sunset(obs_polar, dt_winter, SPA())

        # all times should be equal (the input datetime) when sun doesn't rise/set
        @test result_polar_night.transit isa DateTime
        @test result_polar_night.transit == result_polar_night.sunrise
        @test result_polar_night.sunrise == result_polar_night.sunset
        @test result_polar_night.transit == dt_winter

        # polar day (sun doesn't set) - same location in summer
        dt_summer = DateTime(2025, 6, 21, 0, 0, 0)  # summer solstice

        # test that warning is thrown for polar day with DateTime input
        result_polar_day =
            @test_logs (:warn, r"Sun does not rise or set.*polar day \(sun above horizon\)") transit_sunrise_sunset(
                obs_polar,
                dt_summer,
                SPA(),
            )

        # all times should be equal when sun doesn't rise/set
        @test result_polar_day.transit isa DateTime
        @test result_polar_day.transit == result_polar_day.sunrise
        @test result_polar_day.sunrise == result_polar_day.sunset
        @test result_polar_day.transit == dt_summer

        # Test with ZonedDateTime input for polar cases
        # Use UTC+1 as a fixed offset timezone (similar to Europe/Oslo winter time)
        tz_oslo = FixedTimeZone("UTC+1", 3600)
        zdt_winter = ZonedDateTime(dt_winter, tz_oslo; from_utc = true)
        result_zdt_polar_night =
            @test_logs (:warn, r"Sun does not rise or set.*polar night") transit_sunrise_sunset(
                obs_polar,
                zdt_winter,
                SPA(),
            )

        @test result_zdt_polar_night.transit isa ZonedDateTime
        @test timezone(result_zdt_polar_night.transit) == tz_oslo
        # The result should match the input when converted back to UTC
        @test DateTime(result_zdt_polar_night.transit, UTC) == dt_winter
    end

    @testset "delta_t parameter" begin
        obs = Observer(40.7128, -74.006)
        dt = DateTime(2020, 6, 21, 0, 0, 0)

        result_auto = transit_sunrise_sunset(obs, dt, SPA())
        result_zero = transit_sunrise_sunset(obs, dt, SPA(delta_t = 0.0))
        result_custom = transit_sunrise_sunset(obs, dt, SPA(delta_t = 69.0))

        # all results should be DateTime when DateTime input is used
        @test result_auto.transit isa DateTime
        @test result_zero.sunrise isa DateTime
        @test result_custom.sunset isa DateTime

        # results should differ when using different delta_t values
        @test result_auto.transit != result_zero.transit ||
              result_auto.sunrise != result_zero.sunrise ||
              result_auto.sunset != result_zero.sunset

        @test result_zero.transit != result_custom.transit ||
              result_zero.sunrise != result_custom.sunrise ||
              result_zero.sunset != result_custom.sunset

        # times should be within a reasonable range for the same day
        @test abs(datetime2unix(result_auto.transit) - datetime2unix(result_zero.transit)) <
              300
        @test abs(
            datetime2unix(result_auto.sunrise) - datetime2unix(result_custom.sunrise),
        ) < 300
    end

    @testset "next_sunrise, next_sunset, solar_noon" begin
        using SolarPosition.Utilities: next_sunrise, next_sunset, solar_noon

        # Test location: New York
        obs = Observer(40.7128, -74.006)

        # Test date: June 21, 2020 (summer solstice)
        test_date = Date(2020, 6, 21)

        # Get the full sunrise/sunset/transit for the day
        result = transit_sunrise_sunset(obs, test_date, SPA())

        # Test 1: Before sunrise - next_sunrise should return today's sunrise
        before_sunrise = result.sunrise - Hour(1)
        @test next_sunrise(obs, before_sunrise, SPA()) == result.sunrise

        # Test 2: After sunrise - next_sunrise should return tomorrow's sunrise
        after_sunrise = result.sunrise + Hour(1)
        next_day_result = transit_sunrise_sunset(obs, test_date + Day(1), SPA())
        @test next_sunrise(obs, after_sunrise, SPA()) == next_day_result.sunrise

        # Test 3: Before sunset - next_sunset should return today's sunset
        before_sunset = result.sunset - Hour(1)
        @test next_sunset(obs, before_sunset, SPA()) == result.sunset

        # Test 4: After sunset - next_sunset should return tomorrow's sunset
        after_sunset = result.sunset + Hour(1)
        @test next_sunset(obs, after_sunset, SPA()) == next_day_result.sunset

        # Test 5: Before solar noon - solar_noon should return today's transit
        before_noon = result.transit - Hour(1)
        @test solar_noon(obs, before_noon, SPA()) == result.transit

        # Test 6: After solar noon - solar_noon should return tomorrow's transit
        after_noon = result.transit + Hour(1)
        @test solar_noon(obs, after_noon, SPA()) == next_day_result.transit

        # Test 7: Exact times - should return next occurrence
        @test next_sunrise(obs, result.sunrise, SPA()) == next_day_result.sunrise
        @test next_sunset(obs, result.sunset, SPA()) == next_day_result.sunset
        @test solar_noon(obs, result.transit, SPA()) == next_day_result.transit

        # Test 8: Different location - London
        obs_london = Observer(51.5074, -0.1278)
        london_result = transit_sunrise_sunset(obs_london, test_date, SPA())
        midnight_london = DateTime(test_date)

        # Should return today's values when called at midnight
        @test next_sunrise(obs_london, midnight_london, SPA()) == london_result.sunrise
        @test next_sunset(obs_london, midnight_london, SPA()) == london_result.sunset
        @test solar_noon(obs_london, midnight_london, SPA()) == london_result.transit

        # Test 9: Date input (should work the same as DateTime at midnight)
        @test next_sunrise(obs, test_date, SPA()) == result.sunrise
        @test next_sunset(obs, test_date, SPA()) == result.sunset
        @test solar_noon(obs, test_date, SPA()) == result.transit

        # Test 10: ZonedDateTime input
        tz_ny = TimeZones.TimeZone("America/New_York")
        zdt_before_sunrise = ZonedDateTime(before_sunrise, tz_ny; from_utc = true)
        zdt_result = next_sunrise(obs, zdt_before_sunrise, SPA())
        @test zdt_result isa ZonedDateTime
        @test timezone(zdt_result) == tz_ny
        @test DateTime(zdt_result, UTC) == result.sunrise
    end

    @testset "previous_sunrise, previous_sunset, previous_solar_noon" begin
        using SolarPosition.Utilities:
            previous_sunrise, previous_sunset, previous_solar_noon

        # Test location: New York
        obs = Observer(40.7128, -74.006)

        # Test date: June 21, 2020 (summer solstice)
        test_date = Date(2020, 6, 21)

        # Get the full sunrise/sunset/transit for the day
        result = transit_sunrise_sunset(obs, test_date, SPA())
        prev_day_result = transit_sunrise_sunset(obs, test_date - Day(1), SPA())

        # Test 1: After sunrise - previous_sunrise should return today's sunrise
        after_sunrise = result.sunrise + Hour(1)
        @test previous_sunrise(obs, after_sunrise, SPA()) == result.sunrise

        # Test 2: Before sunrise - previous_sunrise should return yesterday's sunrise
        before_sunrise = result.sunrise - Hour(1)
        @test previous_sunrise(obs, before_sunrise, SPA()) == prev_day_result.sunrise

        # Test 3: After sunset - previous_sunset should return today's sunset
        after_sunset = result.sunset + Hour(1)
        @test previous_sunset(obs, after_sunset, SPA()) == result.sunset

        # Test 4: Before sunset - previous_sunset should return yesterday's sunset
        before_sunset = result.sunset - Hour(1)
        @test previous_sunset(obs, before_sunset, SPA()) == prev_day_result.sunset

        # Test 5: After solar noon - previous_solar_noon should return today's transit
        after_noon = result.transit + Hour(1)
        @test previous_solar_noon(obs, after_noon, SPA()) == result.transit

        # Test 6: Before solar noon - previous_solar_noon should return yesterday's transit
        before_noon = result.transit - Hour(1)
        @test previous_solar_noon(obs, before_noon, SPA()) == prev_day_result.transit

        # Test 7: Exact times - should return previous occurrence
        @test previous_sunrise(obs, result.sunrise, SPA()) == prev_day_result.sunrise
        @test previous_sunset(obs, result.sunset, SPA()) == prev_day_result.sunset
        @test previous_solar_noon(obs, result.transit, SPA()) == prev_day_result.transit

        # Test 8: Date input (midnight of the day)
        # At midnight, all events haven't happened yet, so should return yesterday's
        @test previous_sunrise(obs, test_date, SPA()) == prev_day_result.sunrise
        @test previous_sunset(obs, test_date, SPA()) == prev_day_result.sunset
        @test previous_solar_noon(obs, test_date, SPA()) == prev_day_result.transit

        # Test 9: ZonedDateTime input
        tz_ny = TimeZones.TimeZone("America/New_York")
        zdt_after_sunrise = ZonedDateTime(after_sunrise, tz_ny; from_utc = true)
        zdt_result = previous_sunrise(obs, zdt_after_sunrise, SPA())
        @test zdt_result isa ZonedDateTime
        @test timezone(zdt_result) == tz_ny
        @test DateTime(zdt_result, UTC) == result.sunrise

        # Test 10: Symmetry - next and previous should bracket the current time
        current_time = result.transit + Hour(3)  # afternoon
        next_sr = next_sunrise(obs, current_time, SPA())
        prev_sr = previous_sunrise(obs, current_time, SPA())
        @test prev_sr < current_time < next_sr

        next_ss = next_sunset(obs, current_time, SPA())
        prev_ss = previous_sunset(obs, current_time, SPA())
        @test prev_ss < current_time < next_ss

        next_noon = solar_noon(obs, current_time, SPA())
        prev_noon = previous_solar_noon(obs, current_time, SPA())
        @test prev_noon < current_time < next_noon
    end

    @testset "Non-midnight DateTime inputs (automatic normalization)" begin
        # Test that DateTime inputs at non-midnight times are automatically normalized
        obs = Observer(40.7128, -74.006)  # New York
        test_date = Date(2020, 6, 21)

        # Get reference result from midnight
        result_midnight = transit_sunrise_sunset(obs, DateTime(test_date), SPA())

        # Test with various times during the day - should all give same result
        dt_morning = DateTime(2020, 6, 21, 8, 30, 45)  # 8:30:45 AM
        dt_noon = DateTime(2020, 6, 21, 12, 0, 0)      # Noon
        dt_afternoon = DateTime(2020, 6, 21, 15, 45, 30) # 3:45:30 PM
        dt_evening = DateTime(2020, 6, 21, 20, 15, 0)  # 8:15 PM

        for dt_test in [dt_morning, dt_noon, dt_afternoon, dt_evening]
            result = transit_sunrise_sunset(obs, dt_test, SPA())
            @test result.transit == result_midnight.transit
            @test result.sunrise == result_midnight.sunrise
            @test result.sunset == result_midnight.sunset
        end

        # Test with ZonedDateTime at non-midnight
        tz_ny = TimeZones.TimeZone("America/New_York")
        zdt_afternoon = ZonedDateTime(2020, 6, 21, 15, 30, 0, tz_ny)

        # Convert to UTC for comparison
        dt_utc_afternoon = DateTime(zdt_afternoon, UTC)
        result_zdt = transit_sunrise_sunset(obs, zdt_afternoon, SPA())

        # Should give same UTC times as midnight of the same day
        @test DateTime(result_zdt.transit, UTC) == result_midnight.transit
        @test DateTime(result_zdt.sunrise, UTC) == result_midnight.sunrise
        @test DateTime(result_zdt.sunset, UTC) == result_midnight.sunset

        # But should be in the requested timezone
        @test timezone(result_zdt.transit) == tz_ny
        @test timezone(result_zdt.sunrise) == tz_ny
        @test timezone(result_zdt.sunset) == tz_ny

        # Test that next_sunrise/sunset/solar_noon also handle non-midnight inputs correctly
        # When called with afternoon time, should normalize to midnight for calculation
        dt_afternoon_utc = DateTime(2020, 6, 21, 15, 30, 0)

        # next_sunrise from afternoon should give tomorrow's sunrise
        # because today's sunrise (calculated from midnight) has already passed
        next_sr = next_sunrise(obs, dt_afternoon_utc, SPA())
        next_day_result = transit_sunrise_sunset(obs, test_date + Day(1), SPA())
        @test next_sr == next_day_result.sunrise

        # previous_sunrise from afternoon should give today's sunrise
        prev_sr = previous_sunrise(obs, dt_afternoon_utc, SPA())
        @test prev_sr == result_midnight.sunrise
    end
end
