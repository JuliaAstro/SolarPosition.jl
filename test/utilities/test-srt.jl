"""Unit tests for sunrise and sunset time calculations"""

using Test
using SolarPosition.Utilities: TransitSunriseSunset, transit_sunrise_sunset
using SolarPosition.Positioning: Observer, SPA
using TimeZones
using Dates

include("expected-values.jl")

@testset "SPA" begin
    df = expected_srt_spa()

    @testset "Location: $(row.location), Date: $(row.date)" for row in eachrow(df)
        obs = Observer(row.latitude, row.longitude)
        result = transit_sunrise_sunset(obs, row.date, SPA(delta_t = row.delta_t))

        expected_transit = datetime2unix(DateTime(row.transit))
        expected_sunrise = datetime2unix(DateTime(row.sunrise))
        expected_sunset = datetime2unix(DateTime(row.sunset))

        # compare unix timestamps with a few seconds tolerance
        @test datetime2unix(DateTime(result.transit)) ≈ expected_transit atol = 1.0
        @test datetime2unix(DateTime(result.sunrise)) ≈ expected_sunrise atol = 1.0
        @test datetime2unix(DateTime(result.sunset)) ≈ expected_sunset atol = 1.0
    end
end
