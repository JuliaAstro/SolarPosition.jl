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
    delta_t::Union{Float64, Nothing}
    "Option for calculating Greenwich mean sidereal time (1 or 2)"
    gmst_option::Int

    function USNO(delta_t::Union{Float64, Nothing}, gmst_option::Int)
        if gmst_option != 1 && gmst_option != 2
            error("gmst_option must be either 1 or 2")
        end
        return new(delta_t, gmst_option)
    end
end

USNO() = USNO(67.0, 1)  # default delta_t value and gmst_option


function _solar_position(obs::Observer{T}, dt::DateTime, alg::USNO) where {T <: AbstractFloat}
    δt::T = if alg.delta_t === nothing
        calculate_deltat(T, dt)
    else
        T(alg.delta_t)
    end

    # days since J2000.0 (UT), magnitude-safe at precision T
    D = julian_day_j2000(T, dt)

    # mean anomaly of the sun [deg]
    g = T(357.529) + T(0.98560028) * D
    g = mod(g, 360)

    # mean longitude of the sun [deg]
    q = T(280.459) + T(0.98564736) * D
    q = mod(q, 360)

    # geocentric apparent ecliptic longitude of the sun (adjusted for aberration) [deg]
    L = q + T(1.915) * sind(g) + T(0.02) * sind(2 * g)
    L = mod(L, 360)

    # mean obliquity of the ecliptic [deg]
    ϵ = T(23.439) - T(0.00000036) * D

    # sun's right ascension angle [hours]
    ra = rad2deg(atan(cosd(ϵ) * sind(L), cosd(L))) / 15
    ra = mod(ra, 24)

    # sun's declination angle [deg]
    δ = asind(sind(ϵ) * sind(L))

    # hours elapsed since the previous midnight (0h) UT1, and that midnight's day-count
    H = fractional_hour(T, dt)
    day_ut = julian_day_j2000(T, DateTime(year(dt), month(dt), day(dt), 0, 0, 0))
    D_tt = D + δt / T(86400)
    t_cent = D_tt / T(36525)

    # Greenwich mean sidereal time [hours]
    gmst = if alg.gmst_option == 1
        (
            T(6.697375) +
                T(0.065707485828) * day_ut +
                T(1.0027379) * H +
                T(0.0854103) * t_cent +
                T(0.0000258) * t_cent^2
        )
    else  # gmst_option == 2
        (T(6.697375) + T(0.065709824279) * day_ut + T(1.0027379) * H + T(0.0000258) * t_cent^2)
    end
    gmst = mod(gmst, 24)

    # longitude of the ascending node of the moon [deg]
    Ω = T(125.04) - T(0.052954) * D_tt

    # mean longitude of the sun [deg]
    L_s = T(280.47) + T(0.98565) * D_tt

    # nutation in longitude [hours]
    Δψ = T(-0.000319) * sind(Ω) - T(0.000024) * sind(2 * L_s)

    # obliquity of the ecliptic [deg]
    ε = T(23.4393) - T(0.0000004) * D_tt

    # equation of equinoxes [hours]
    eqeq = Δψ * cosd(ε)

    # Greenwich apparent sidereal time [hours]
    gast = gmst + eqeq

    # local hour angle [deg], longitude is positive if it is east
    ha = (gast - ra) * 15 + obs.longitude

    # solar elevation [deg]
    elevation = asind(cosd(ha) * cosd(δ) * obs.cos_lat + sind(δ) * obs.sin_lat)

    # azimuth [deg]
    azimuth = rad2deg(atan(-sind(ha), (tand(δ) * obs.cos_lat - obs.sin_lat * cosd(ha))))

    return SolPos{T}(mod(azimuth, 360), elevation, 90 - elevation)
end

function _solar_position(obs, dt, alg::USNO, ::DefaultRefraction)
    return _solar_position(obs, dt, alg, NoRefraction())
end

# USNO with DefaultRefraction returns SolPos (no refraction by default)
result_type(::Type{USNO}, ::Type{DefaultRefraction}, ::Type{T}) where {T} = SolPos{T}
