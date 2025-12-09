"""
    $(TYPEDEF)

USNO (U.S. Naval Observatory) solar position algorithm. This algorithm provides solar
position calculations based on the USNO's Astronomical Applications Department formulas.

# Accuracy
The accuracy is typically within a few arcminutes for most practical applications.
This algorithm is suitable for general-purpose solar position calculations.

# Literature
The U.S. Naval Observatory (USNO) algorithm is provided in [USNO](@cite).

# Fields
$(TYPEDFIELDS)
"""
struct USNO <: SolarAlgorithm
    "Difference between terrestrial time and UT1 [seconds]. If `nothing`, uses automatic calculation."
    delta_t::Union{Float64,Nothing}
    "Option for calculating Greenwich mean sidereal time (1 or 2)"
    gmst_option::Int

    function USNO(delta_t::Union{Float64,Nothing}, gmst_option::Int)
        if gmst_option != 1 && gmst_option != 2
            error("gmst_option must be either 1 or 2")
        end
        new(delta_t, gmst_option)
    end
end

USNO() = USNO(67.0, 1)  # default delta_t value and gmst_option


function _solar_position(obs::Observer{T}, dt::DateTime, alg::USNO) where {T<:AbstractFloat}
    δt::T = if alg.delta_t === nothing
        calculate_deltat(dt)
    else
        alg.delta_t
    end

    # convert to Julian date
    jd = datetime2julian(dt)

    # days since J2000.0
    D = jd - 2451545.0

    # mean anomaly of the sun [deg]
    g = 357.529 + 0.98560028 * D
    g = mod(g, 360.0)

    # mean longitude of the sun [deg]
    q = 280.459 + 0.98564736 * D
    q = mod(q, 360.0)

    # geocentric apparent ecliptic longitude of the sun (adjusted for aberration) [deg]
    L = q + 1.915 * sind(g) + 0.020 * sind(2 * g)
    L = mod(L, 360.0)

    # mean obliquity of the ecliptic [deg]
    ϵ = 23.439 - 0.00000036 * D

    # sun's right ascension angle [hours]
    ra = rad2deg(atan(cosd(ϵ) * sind(L), cosd(L))) / 15.0
    ra = mod(ra, 24.0)

    # sun's declination angle [deg]
    δ = asind(sind(ϵ) * sind(L))

    # JD_0 is the Julian date of the previous midnight (0h) UT1
    dt_midnight = DateTime(year(dt), month(dt), day(dt), 0, 0, 0)
    jd_0 = datetime2julian(dt_midnight)

    # hours of UT1 elapsed since the previous midnight
    H = (jd - jd_0) * 24.0
    day_ut = jd_0 - 2451545.0
    jd_tt = jd + δt / 86400.0
    D_tt = jd_tt - 2451545.0

    # centuries since the year 2000
    t_cent = D_tt / 36525.0

    # Greenwich mean sidereal time [hours]
    gmst = if alg.gmst_option == 1
        (
            6.697375 +
            0.065707485828 * day_ut +
            1.0027379 * H +
            0.0854103 * t_cent +
            0.0000258 * t_cent^2
        )
    else  # gmst_option == 2
        (6.697375 + 0.065709824279 * day_ut + 1.0027379 * H + 0.0000258 * t_cent^2)
    end
    gmst = mod(gmst, 24.0)

    # longitude of the ascending node of the moon [deg]
    Ω = 125.04 - 0.052954 * D_tt

    # mean longitude of the sun [deg]
    L_s = 280.47 + 0.98565 * D_tt

    # nutation in longitude [hours]
    Δψ = -0.000319 * sind(Ω) - 0.000024 * sind(2 * L_s)

    # obliquity of the ecliptic [deg]
    ε = 23.4393 - 0.0000004 * D_tt

    # equation of equinoxes [hours]
    eqeq = Δψ * cosd(ε)

    # Greenwich apparent sidereal time [hours]
    gast = gmst + eqeq

    # local hour angle [deg], longitude is positive if it is east
    ha = (gast - ra) * 15.0 + obs.longitude

    # solar elevation [deg]
    elevation = asind(cosd(ha) * cosd(δ) * obs.cos_lat + sind(δ) * obs.sin_lat)

    # azimuth [deg]
    azimuth = rad2deg(atan(-sind(ha), (tand(δ) * obs.cos_lat - obs.sin_lat * cosd(ha))))

    return SolPos{T}(mod(azimuth, 360.0), elevation, 90.0 - elevation)
end

function _solar_position(obs, dt, alg::USNO, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, NoRefraction())
end

# USNO with DefaultRefraction returns SolPos (no refraction by default)
result_type(::Type{USNO}, ::Type{DefaultRefraction}, ::Type{T}) where {T} = SolPos{T}
