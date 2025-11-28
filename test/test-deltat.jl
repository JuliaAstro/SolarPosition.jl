"""Unit tests for ΔT (Delta T) calculation

The test values are taken from NASA's documentation [1] and the tables in [2] that
describe the polynomial approximations and tabulated values for ΔT.

[1] https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html
[2] https://eclipse.gsfc.nasa.gov/SEhelp/deltat2004.html
"""

using SolarPosition.Positioning: calculate_deltat

@testset "Historical Values (Table 1: -500 to 1950)" begin
    historical_data = [
        # year, expected ΔT (seconds), standard error (seconds)
        (-500, 17190, 430),
        (-400, 15530, 390),
        (-300, 14080, 360),
        (-200, 12790, 330),
        (-100, 11640, 290),
        (0, 10580, 260),
        (100, 9600, 240),
        (200, 8640, 210),
        (300, 7680, 180),
        (400, 6700, 160),
        (500, 5710, 140),
        (600, 4740, 120),
        (700, 3810, 100),
        (800, 2960, 80),
        (900, 2200, 70),
        (1000, 1570, 55),
        (1100, 1090, 40),
        (1200, 740, 30),
        (1300, 490, 20),
        (1400, 320, 20),
        (1500, 200, 20),
        (1600, 120, 20),
        (1700, 9, 5),
        (1750, 13, 2),
        (1800, 14, 1),
        (1850, 7, 1),
        (1900, -3, 1),
        (1950, 29, 0.1),
    ]

    for (year, expected_deltat, std_error) in historical_data
        result = calculate_deltat(year, 6)
        tolerance = max(2 * std_error, 1.0)
        @test result ≈ expected_deltat atol = tolerance
    end
end

@testset "Modern Values (Table 2: 1955 to 2005)" begin
    modern_data = [
        # year, expected ΔT (seconds)
        (1955.0, 31.1),
        (1960.0, 33.2),
        (1965.0, 35.7),
        (1970.0, 40.2),
        (1975.0, 45.5),
        (1980.0, 50.5),
        (1985.0, 54.3),
        (1990.0, 56.9),
        (1995.0, 60.8),
        (2000.0, 63.8),
        (2005.0, 64.7),
    ]

    for (year, expected_deltat) in modern_data
        result = calculate_deltat(year, 1)
        @test result ≈ expected_deltat atol = 1.0
    end
end

@testset "Future Extrapolations" begin
    future_estimates = [(2010, 67, 5), (2050, 93, 10), (2100, 203, 20), (2200, 442, 50)]

    for (year, expected_deltat, tolerance) in future_estimates
        result = calculate_deltat(year, 1)
        @test result ≈ expected_deltat atol = tolerance
    end
end

@testset "Warnings for Undefined Ranges" begin
    @test_logs (:warn, r"ΔT is undefined") calculate_deltat(-2000, 6)
    @test_logs (:warn, r"ΔT is undefined") calculate_deltat(3001, 6)

    result_ancient = calculate_deltat(-2000, 6)
    result_future = calculate_deltat(3001, 6)
    @test isfinite(result_ancient)
    @test isfinite(result_future)
end

@testset "Date/DateTime Interface" begin
    using Dates

    result_baseline = calculate_deltat(2020, 6)

    date_mid = Date(2020, 6, 15)
    result_date_mid = calculate_deltat(date_mid)
    @test isfinite(result_date_mid)
    @test result_date_mid ≈ result_baseline atol = 0.05

    date_start = Date(2020, 6, 1)
    result_date_start = calculate_deltat(date_start)
    @test isfinite(result_date_start)
    @test result_date_start < result_date_mid

    date_end = Date(2020, 6, 30)
    result_date_end = calculate_deltat(date_end)
    @test isfinite(result_date_end)
    @test result_date_end > result_date_mid

    dt = DateTime(2020, 6, 15, 12, 30, 45)
    result_datetime = calculate_deltat(dt)
    @test isfinite(result_datetime)
    @test result_datetime ≈ result_date_mid atol = 0.001
end

@testset "ZonedDateTime Interface" begin
    using Dates, TimeZones

    zdt_utc = ZonedDateTime(2020, 6, 15, 12, 30, 45, tz"UTC")
    result_zdt = calculate_deltat(zdt_utc)
    @test isfinite(result_zdt)

    dt = DateTime(2020, 6, 15, 12, 30, 45)
    result_dt = calculate_deltat(dt)
    @test result_zdt ≈ result_dt atol = 0.001

    zdt_eastern = ZonedDateTime(2020, 6, 15, 8, 30, 45, tz"America/New_York")
    result_zdt_eastern = calculate_deltat(zdt_eastern)
    @test isfinite(result_zdt_eastern)
    @test result_zdt_eastern ≈ result_dt atol = 0.001
end

@testset "Fractional Month Interpolation" begin
    using Dates

    dates = [Date(2020, 6, day) for day = 1:30]
    deltat_values = [calculate_deltat(d) for d in dates]

    @test all(isfinite, deltat_values)

    for i = 1:(length(deltat_values)-1)
        @test deltat_values[i+1] >= deltat_values[i] - 0.01
    end

    @test deltat_values[1] < deltat_values[end]
end

@testset "ΔT edge cases" begin
    # Test years before -1999 (should warn and return extrapolated value)
    @test_logs (:warn, r"ΔT is undefined") calculate_deltat(DateTime(-2500, 6, 1))

    # Test years after 3000 (should warn and return extrapolated value)
    @test_logs (:warn, r"ΔT is undefined") calculate_deltat(DateTime(3500, 6, 1))

    # Test year ranges that hit specific polynomial cases
    # 1860-1900 range
    dt1 = calculate_deltat(DateTime(1870, 6, 1))
    @test dt1 isa Float64

    # 1900-1920 range
    dt2 = calculate_deltat(DateTime(1910, 6, 1))
    @test dt2 isa Float64

    # 1941-1961 range (line 50)
    dt3 = calculate_deltat(DateTime(1950, 6, 1))
    @test dt3 isa Float64
    @test dt3 > 0.0
end
