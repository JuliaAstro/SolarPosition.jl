"""Unit tests for sunrise and sunset time calculations"""

using Test
using SolarPosition.Utilities: TransitSunriseSunset, transit_sunrise_sunset
using SolarPosition.Positioning: Observer, SPA
using TimeZones: TimeZones, ZonedDateTime, timezone, FixedTimeZone, UTC
using Dates: Dates, DateTime, Date, datetime2unix

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
end
