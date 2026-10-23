"""Unit tests for the NREL SOLPOS algorithm"""

# The table below holds outputs of NREL's solpos.c for the timestamps and locations of
# `test_conditions()`, at the default 1013 mbar and 15 °C. The C code computes in single
# precision with truncated degree conversion constants, so the reference build compiles it
# with `-Dfloat=double`, sets `degrad` and `raddeg` to exactly 180/π and π/180, and skips the
# early return on a validation error so rows 13 and 14, outside the 1950 to 2050 window,
# are evaluated too. Each row is elevetr, elevref, zenetr, zenref and azim with full
# round-trip digits.
#
# Rows 6, 11, 12 and 15 have the sun more than 9° below the horizon, where SOLPOS caps the
# zenith angle at 99° and the azimuth follows from the capped elevation. Rows 6 and 8 are at
# the poles, where SOLPOS reports an azimuth of 180°.
function expected_solpos()
    columns = [:elevation, :apparent_elevation, :zenith, :apparent_zenith, :azimuth]

    values = [
        [26.457002569254037, 26.488715801026096, 63.542997430745963, 63.511284198973904, 220.57252808890308],
        [25.125529780989183, 25.159161043642985, 64.874470219010817, 64.840838956357018, 223.27539269569218],
        [34.922792607349962, 34.945450264179634, 55.077207392650038, 55.054549735820366, 169.37618059217044],
        [20.74549842735378, 20.787018095425672, 69.25450157264622, 69.21298190457432, 230.96196249800775],
        [31.087748081025026, 31.113963190456701, 58.912251918974974, 58.886036809543299, 214.61564350964187],
        [-9.0, -8.9641986783060013, 99.0, 98.964198678306005, 180.0],
        [52.739329730376291, 52.751385222700982, 37.260670269623709, 37.248614777299018, 254.10455067334232],
        [9.5448865698500072, 9.6353561398628891, 80.455113430149993, 80.364643860137107, 180.0],
        [42.846089325825609, 42.863163641733443, 47.153910674174391, 47.136836358266557, 307.42050308943658],
        [34.527939668719426, 34.550931613079953, 55.472060331280574, 55.449068386920047, 193.43238259942933],
        [-9.0, -8.9641986783060013, 99.0, 98.964198678306005, 94.53361201565545],
        [-9.0, -8.9641986783060013, 99.0, 98.964198678306005, 94.53361201565545],
        [27.043595161088177, 27.074518202334126, 62.956404838911823, 62.925481797665874, 220.78679546851649],
        [26.32652526040161, 26.358418610513631, 63.67347473959839, 63.641581389486369, 220.5354714079414],
        [-9.0, -8.9641986783060013, 99.0, 98.964198678306005, 94.32395398323645],
        [0.89466813883527152, 1.2619141100500455, 89.105331861164728, 88.738085889949957, 104.31835340288025],
        [26.457002569254037, 26.488715801026096, 63.542997430745963, 63.511284198973904, 220.57252808890308],
        [26.457002569254037, 26.488715801026096, 63.542997430745963, 63.511284198973904, 220.57252808890308],
        [26.457002569254037, 26.488715801026096, 63.542997430745963, 63.511284198973904, 220.57252808890308],
    ]

    return DataFrame(reduce(hcat, values)', columns)
end

@testset "SOLPOS" begin
    @testset "Reference implementation" begin
        conds = test_conditions()
        df_expected = expected_solpos()
        @test size(df_expected) == (19, 5)
        for ((dt, lat, lon, alt), row) in zip(eachrow(conds), eachrow(df_expected))
            obs = ismissing(alt) ? Observer(lat, lon) : Observer(lat, lon; altitude = alt)
            res = solar_position(obs, dt, SOLPOS())
            @test res isa ApparentSolPos
            @test res.elevation ≈ row.elevation atol = 1.0e-10
            @test res.apparent_elevation ≈ row.apparent_elevation atol = 1.0e-10
            @test res.zenith ≈ row.zenith atol = 1.0e-10
            @test res.apparent_zenith ≈ row.apparent_zenith atol = 1.0e-10
            @test res.azimuth ≈ row.azimuth atol = 1.0e-10
        end
    end

    # The benchmark case of NREL's test program stest00.c, Atlanta at 9:45:37 local standard
    # time, UTC-5, on 22 July 1999, at 1006 mbar and 27 °C. The double precision build gives
    # the tight reference. NREL's printed values come from the single precision build and
    # agree to about 2e-4°.
    @testset "NREL benchmark" begin
        obs = Observer(33.65, -84.43)
        dt = DateTime(1999, 7, 22, 14, 45, 37)
        res = solar_position(obs, dt, SOLPOS(), HUGHES(1006 * 101325 / 1013, 27.0))
        @test res.elevation ≈ 48.396337313933472 atol = 1.0e-10
        @test res.apparent_elevation ≈ 48.409749710070145 atol = 1.0e-10
        @test res.apparent_zenith ≈ 41.590250289929855 atol = 1.0e-10
        @test res.azimuth ≈ 97.03331432056244 atol = 1.0e-10
        @test res.apparent_elevation ≈ 48.409931 atol = 1.0e-3
        @test res.apparent_zenith ≈ 41.590069 atol = 1.0e-3
        @test res.azimuth ≈ 97.032875 atol = 1.0e-3
    end

    # Within the 1950 to 2050 window SOLPOS evaluates the same series as Michalsky with the
    # original Julian date, so the two agree wherever the sun is above the zenith cap and the
    # azimuth is defined.
    @testset "Agreement with Michalsky" begin
        dt = DateTime(2020, 10, 17, 13, 30)
        for (lat, lon) in ((45.0, 10.0), (0.0, 10.0), (-45.0, 10.0), (45.0, -15.0))
            obs = Observer(lat, lon)
            a = solar_position(obs, dt, SOLPOS(), NoRefraction())
            b = solar_position(obs, dt, Michalsky(), NoRefraction())
            @test a.elevation ≈ b.elevation atol = 1.0e-10
            @test a.azimuth ≈ b.azimuth atol = 1.0e-10
        end
    end

    @testset "Default refraction" begin
        obs = Observer(45.0, 10.0)
        dt = DateTime(2020, 10, 17, 13, 30)
        @test solar_position(obs, dt, SOLPOS()) ==
            solar_position(obs, dt, SOLPOS(), HUGHES(101325.0, 15.0))
        @test solar_position(obs, dt, SOLPOS(), NoRefraction()) isa SolPos{Float64}
        @test solar_position(Observer{Float32}(45, 10), dt, SOLPOS()) isa
            ApparentSolPos{Float32}
    end
end
