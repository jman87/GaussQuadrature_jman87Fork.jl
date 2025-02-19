module GaussQuadrature

using SpecialFunctions: gamma, loggamma

# October 2013 by Bill McLean, School of Maths and Stats,
# The University of New South Wales.
#
# Based on earlier Fortran codes
#
# gaussq.f original version 20 Jan 1975 from Stanford
# gaussq.f modified 21 Dec by Eric Grosse
# gaussquad.f95 Nov 2005 by Bill Mclean
#
# This module provides functions to compute the abscissae x[j] and
# weights w[j] for the classical Gauss quadrature rules, including
# the Radau and Lobatto variants.  Thus, the sum
#
#           n
#           ∑  w[j] f(x[j])
#          j=1
#
# approximates
#
#           hi
#          ∫  f(x) w(x) dx
#          lo
#
# where the weight function w(x) and interval lo < x < hi are as shown
# in the table below.
#
# Name                      Interval     Weight Function
#
# Legendre                 -1 < x < 1          1
# Chebyshev (first kind)   -1 < x < 1     1 / sqrt(1-x²)
# Chebyshev (second kind)  -1 < x < 1       sqrt(1-x²)
# Jacobi                   -1 < x < 1     (1-x)ᵅ (1+x)ᵝ
# Laguerre                  0 < x < ∞     xᵅ exp(-x)
# Hermite                  -∞ < x < ∞      exp(-x²)
#
# In addition to these classical rules, the module generates Gauss rules
# for logarithmic weights of the form
#
#    w(x) = x^ρ log(1/x)   for 0 < x < 1.
#
# For the Jacobi and Laguerre rules we require α > -1 and
# β > -1, so that the weight function is integrable.  Likewise, for
# log weight we require ρ > -1.
#
# Use the endpt argument to include one or both of the end points
# of the interval of integration as an abscissa in the quadrature
# rule, as follows.
#
# endpt = neither   Default      lo < x[j] < hi, j = 1:n.
# endpt = left      Left Radau   lo = x[1] < x[j] < hi, j = 2:n.
# endpt = right     Right Radau  lo < x[j] < x[n] = hi, j = 1:n-1.
# endpt = both      Lobatto      lo = x[1] < x[j] < x[n] = hi, j = 2:n-1.
#
# These labels make up an enumeration of type EndPt.
#
# The code uses the Golub and Welsch algorithm, in which the abscissae
# x[j] are the eigenvalues of a symmetric tridiagonal matrix whose
# entries depend on the coefficients in the 3-term recurrence relation
# for the othonormal polynomials generated by the weighted inner product.
#
# References:
#
#   1.  Golub, G. H., and Welsch, J. H., Calculation of Gaussian
#       quadrature rules, Mathematics of Computation 23 (April,
#       1969), pp. 221-230.
#   2.  Golub, G. H., Some modified matrix eigenvalue problems,
#       Siam Review 15 (april, 1973), pp. 318-334 (section 7).
#   3.  Stroud and Secrest, Gaussian Quadrature Formulas, Prentice-
#       Hall, Englewood Cliffs, N.J., 1966.

export neither, left, right, both
export legendre, legendre_coefs
export chebyshev, chebyshev_coefs
export jacobi, jacobi_coefs
export laguerre, laguerre_coefs
export hermite, hermite_coefs
export shifted_legendre_coefs
export logweight, logweight_coefs
export modified_moments, modified_chebyshev
export custom_gauss_rule, orthonormal_poly
export special_eigenproblem!

# Enumeration type used to specify which endpoints of the integration
# interval should be included amongst the quadrature points: neither,
# left, right or both.
struct EndPt
    label :: Char
end

const neither = EndPt('N')
const left    = EndPt('L')
const right   = EndPt('R')
const both    = EndPt('B')

#include("to_be_removed.jl")

# Maximum number of QL iterations used by steig!.
# You might need to increase this.
maxiterations = Dict(Float32 => 30, Float64 => 30, BigFloat => 40)

"""
    x, w = legendre(T, n, endpt=neither)

Returns points `x` and weights `w` for the `n`-point Gauss-Legendre rule
for the interval `-1 < x < 1` with weight function `w(x) = 1`.

Use `endpt=left`, `right` or `both` for the left Radau, right Radau or
Lobatto rules, respectively.
"""
function legendre(::Type{T}, n::Integer,
                  endpt::EndPt=neither) where {T<:AbstractFloat}
    @assert n ≥ 1
    a, b = legendre_coefs(T, n)
    return custom_gauss_rule(-one(T), one(T), a, b, endpt)
end

"""
Convenience function with type `T = Float64`:

    x, w = legendre(n, endpt=neither)
"""
legendre(n, endpt=neither) = legendre(Float64, n, endpt)

function legendre_coefs(::Type{T}, n::Integer) where {T<:AbstractFloat}
    a = zeros(T, n)
    b = zeros(T, n+1)
    b[1] = sqrt(convert(T, 2))
    for k = 2:n+1
        b[k] = (k-1) / sqrt(convert(T, (2k-1)*(2k-3)))
    end
    return a, b
end

"""
    x, w = lobatto(T, n)

Returns points `x` and 	weights `w` for the `n`-point Gauss-Lobatto rule
for the interval `-1 < x < 1`
"""
function lobatto(::Type{T}, n::Integer) where {T<:AbstractFloat}
	a, b = legendre(T, n, both)
	return a, b
end

"""
Convenience function with type `T = Float64`:

    x, w = lobatto(n)
"""
lobatto(n) = lobatto(Float64, n)

"""
    x, w = chebyshev(T, n, kind=1, endpt=neither)

Returns points `x` and weights `w` for the `n`-point Gauss-Chebyshev rule
for the interval `-1 < x < 1` with weight function

    w(x) = 1 / sqrt(1-x²)   if kind=1
    w(x) = sqrt(1-x²)       if kind=2.

Use `endpt=left`, `right` or `both` for the left Radau, right Radau or
Lobatto rules, respectively.
"""
function chebyshev(::Type{T}, n::Integer, kind::Integer=1,
                   endpt::EndPt=neither) where {T<:AbstractFloat}
    @assert n ≥ 1
    a, b = chebyshev_coefs(T, n, kind)
    return custom_gauss_rule(-one(T), one(T), a, b, endpt)
end

"""
Convenience function with type `T = Float64`:

    x, w = chebyshev(n, kind=1, endpt=neither)

"""
chebyshev(n, kind=1, endpt=neither) = chebyshev(Float64, n, kind, endpt)

function chebyshev_coefs(::Type{T}, n::Integer,
                         kind::Integer) where {T<:AbstractFloat}
    half = convert(T, 1//2)
    a = zeros(T, n)
    b = fill(half, n+1)
    if kind == 1
        b[1] = sqrt(convert(T, pi))
	if n >= 2
            b[2] = sqrt(half)
        end
    elseif kind == 2
        b[1] = sqrt(half * convert(T, pi))
    else
        error("Unsupported value for kind")
    end
    return a, b
end

"""
    x, w = jacobi(n, α, β, endpt=neither)

Returns points `x` and weights `w` for the `n`-point Gauss-Jacobi rule
for the interval `-1 < x < 1` with weight function

    w(x) = (1-x)ᵅ (1+x)ᵝ.

Use `endpt=left`, `right` or `both` for the left Radau, right Radau or
Lobatto rules, respectively.
"""
function jacobi(n::Integer, α::T, β::T,
                endpt::EndPt=neither) where {T<:AbstractFloat}
    @assert n ≥ 1
    @assert α > -1.0 && β > -1.0
    a, b = jacobi_coefs(n, α, β)
    custom_gauss_rule(-one(T), one(T), a, b, endpt)
end

function jacobi_coefs(n::Integer, α::T, β::T) where {T<:AbstractFloat}
    a = zeros(T, n)
    b = zeros(T, n+1)
    ab = α + β
    abi = ab + 2
    b[1] = 2^((ab+1)/2) * exp(
             ( loggamma(α+1) + loggamma(β+1) - loggamma(abi) )/2 )
    a[1] = ( β - α ) / abi
    b[2] = sqrt( 4*(α+1)*(β+1) / ( (ab+3)*abi*abi ) )
    a2b2 = β*β - α*α
    for i = 2:n
        abi = ab + 2i
        a[i]   = a2b2 / ( (abi-2)*abi )
        b[i+1] = sqrt( 4i*(α+i)*(β+i)*(ab+i) /
                     ( (abi*abi-1)*abi*abi ) )
    end
    return a, b
end

"""
    x, w = laguerre(n, α, endpt=neither)

Returns points `x` and weights `w` for the `n`-point Gauss-Laguerre rule
for the interval `0 < x < ∞` with weight function

    w(x) = xᵅ exp(-x),   α > -1.

Use `endpt=left` for the left Radau rule.
"""
function laguerre(n::Integer, α::T,
                  endpt::EndPt=neither) where {T<:AbstractFloat}
    @assert n ≥ 1
    @assert α > -1.0
    @assert endpt in [neither, left]
    a, b = laguerre_coefs(n, α)
    custom_gauss_rule(zero(T), convert(T, Inf), a, b, endpt)
end

function laguerre_coefs(n::Integer, α::T) where {T<:AbstractFloat}
    a = zeros(T, n)
    b = zeros(T, n+1)
    b[1] = sqrt(gamma(α+1))
    for i = 1:n
        a[i] = 2i - 1 + α
        b[i+1] = sqrt( i*(α+i) )
    end
    return a, b
end

"""
    x, w = hermite(T, n)

Returns points `x` and weights `w` for the `n`-point Gauss-Laguerre rule
for the interval `-∞ < x < ∞` with weight function

    w(x) = exp(-x²).
"""
function hermite(::Type{T}, n::Integer) where {T<:AbstractFloat}
    @assert n ≥ 1
    a, b = hermite_coefs(T, n)
    custom_gauss_rule(convert(T, -Inf), convert(T, Inf), a, b, neither)
end

"""
Convenience function with type `T = Float64`:

    x, w = hermite(n)
"""
hermite(n) = hermite(Float64, n)

function hermite_coefs(::Type{T}, n::Integer) where {T<:AbstractFloat}
    a = zeros(T, n)
    b = zeros(T, n+1)
    b[1] = sqrt(sqrt(convert(T, pi)))
    for i = 1:n
        iT = convert(T, i)
        b[i+1] = sqrt(iT/2)
    end
    return a, b
end

"""
    x, w = logweight(T, n, r=0, endpt=neither)

Returns points `x` and weights `w` for the n-point Gauss rule on
the interval `0 < x < 1` with weight function

    w(x) = xʳ log(1/x),    r ≥ 0.
"""
function logweight(::Type{T}, n::Integer, r::Integer,
                   endpt::EndPt=neither) where {T<:AbstractFloat}
    @assert n ≥ 1
    @assert r ≥ 0
    α, β = logweight_coefs(T, n, r)
    custom_gauss_rule(zero(T), one(T), α, β, endpt)
end

"""
Convenience function with type `T = Float64`:

    x, w = logweight(n, r=0, endpt=neither)
"""
logweight(n, r=0, endpt=neither) = logweight(Float64, n, r, endpt)

"""
More general method works when `w(x) = x^ρ log(1/x)` for real `ρ > -1`:

    x, w = logweight(n, ρ, endpt=neither)
"""
function logweight(n::Integer, ρ::T,
                   endpt::EndPt=neither) where {T<:AbstractFloat}
    @assert n ≥ 1
    @assert ρ > -1
    α, β = logweight_coefs(n, ρ)
    custom_gauss_rule(zero(T), one(T), α, β, endpt)
end

function logweight_coefs(::Type{T}, n::Integer,
                         r::Integer) where {T<:AbstractFloat}
    a, b = shifted_legendre_coefs(T, 2n)
    ν = modified_moments(T, n, r)
    α, β, σ = modified_chebyshev(a, b, ν)
    return α, β
end

function logweight_coefs(n::Integer, ρ::T) where {T<:AbstractFloat}
    a, b = shifted_legendre_coefs(T, 2n)
    ν = modified_moments(n, ρ)
    α, β, σ = modified_chebyshev(a, b, ν)
    return α, β
end

function modified_moments(::Type{T}, n::Integer,
                          r::Integer) where {T<:AbstractFloat}
    @assert r ≥ 0
    @assert n ≥ 0
    m = min(2n, r+1)
    rrp1 = 1 / convert(T, r+1) # reciprocal r+1
    B = one(T)
    S = rrp1
    ν = zeros(T, 2n)
    ν[1] = rrp1 * S
    for l = 2:m
        j = l - 1
	rrpj = 1 / convert(T, r + 1 + j)
        rmj = convert(T, r + 1 - j)
	rrmj = 1 / rmj
        B *= rmj * rrpj
        S +=  rrpj - rrmj
        tlm1 = convert(T, 2l-1)
        ν[l] = rrp1 * B * S * sqrt(tlm1)
    end
    if 2n > r+1
        p = one(T)
        for j = 1:r
            p *= j / convert(T, 2(2j+1))
        end
        ν[r+2] = - sqrt(convert(T, 2r+3)) *p / ( 2(r+1) )
        for l = r+2:2n-1
            Tl = convert(T, l)
            ν[l+1] = - ν[l] * ( (Tl-r-1)/(Tl+r+1) ) * sqrt((2Tl+1)/(2Tl-1) )
        end
    end
    return ν
end

function modified_moments(n::Integer, ρ::T) where {T<:AbstractFloat}
    @assert ρ > -1
    @assert n ≥ 0
    r = (ρ<0) ? 0 : round(Integer, ρ)
    m = min(2n, r+1)
    S = 1 / ( 1 + ρ )
    B = one(T)
    ν = zeros(T, 2n)
    ν[1] = S / (1+ρ)
    for l = 2:m
        j = l - 1
        B *= (ρ+1-j) / (ρ+1+j)
	S += 1 / (ρ+1+j) - 1 / (ρ+1-j)
        ν[l] = B * S * sqrt(convert(T,2l-1))
    end
    if 2n > r+1
        l = r + 2
	j = l - 1
	X = ( (ρ-r) / (ρ+r+2) - 1 ) / (ρ+r+2)
        tlm1 = convert(T, 2l-1)
	ν[l] = ( B / (1+ρ) ) * ( X + ( (ρ-r)/(ρ+r+2) ) * S ) * sqrt(tlm1)
        for l = r+3:2n
	    j = l - 1
            B *= (ρ+1-j) / (ρ+1+j)
            S += 1 / (ρ+1+j) - 1 / (ρ+1-j)
        tlm1 = convert(T, 2l-1)
	    ν[l] = ( B / (1+ρ) ) * ( X + ( (ρ-r)/(ρ+r+2) ) * S ) * sqrt(tlm1)
        end
    end
    return ν
end

function shifted_legendre_coefs(T, n)
    a = zeros(T, n)
    b = zeros(T, n+1)
    fill!(a, 1/convert(T,2))
    b[1] = one(T)
    for k = 2:n+1
        b[k] = (k-1) / ( 2 * sqrt( convert(T, (2k-1)*(2k-3)) ) )
    end
    return a, b
end

"""
    x, w = custom_gauss_rule(lo, hi, a, b, endpt, maxits=maxiterations[T])

Generates the points `x` and weights `w` for a Gauss rule with weight
function `w(x)` on the interval `lo < x < hi`.

The arrays `a` and `b` hold the coefficients (as given, for instance, by
`legendre_coeff`) in the three-term recurrence relation for the monic
orthogonal polynomials `p(0,x)`, `p(1,x)`, `p(2,x)`, ... , that is,

    p(k, x) = (x-a[k]) p(k-1, x) - b[k]² p(k-2, x),    k ≥ 1,

where `p(0, x) = 1` and, by convention, `p(-1, x) = 0` with

              hi
    b[1]^2 = ∫  w(x) dx.
             lo

Thus, `p(k, x) = xᵏ + lower degree terms` and

     hi
    ∫  p(j, x) p(k, x) w(x) dx = 0 if j ≠ k.
    lo
"""
function custom_gauss_rule(lo::T, hi::T,
             a::Array{T,1}, b::Array{T,1}, endpt::EndPt,
             maxits::Integer=maxiterations[T]) where {T<:AbstractFloat}
    n = length(a)
    @assert length(b) == n+1
    if endpt == left
        if n == 1
            a[1] = lo
        else
            a[n] = solve(n, lo, a, b) * b[n]^2 + lo
        end
    elseif endpt == right
        if n == 1
            a[1] = hi
        else
            a[n] = solve(n, hi, a, b) * b[n]^2 + hi
        end
    elseif endpt == both
        if n == 1
            error("Must have at least two points for both ends.")
        end
        g = solve(n, lo, a, b)
        t1 = ( hi - lo ) / ( g - solve(n, hi, a, b) )
        b[n] = sqrt(t1)
        a[n] = lo + g * t1
    end
    w = zero(a)
    special_eigenproblem!(a, b, w, maxits)
    for i = 1:n
        w[i] = (b[1] * w[i])^2
    end
    idx = sortperm(a)
    # Ensure end point values are exact.
    if endpt in (left, both)
        a[idx[1]] = lo
    end
    if endpt in (right, both)
        a[idx[n]] = hi
    end
    return a[idx], w[idx]
end

"""
    α, β, σ = modified_chebyshev(a, b, ν)

Implements the modified Chebyshev algorithm described in `doc/notes.tex`
and used in `logweight_coefs`.
"""
function modified_chebyshev(a::Vector{T}, b::Vector{T},
                            ν::Vector{T}) where {T<:AbstractFloat}
    m = length(ν)
    @assert m % 2 == 0 && m >= 2
    n = div(m, 2)
    @assert length(a) >= max(1, 2n-1)
    @assert length(b) >= max(1, 2n-1)
    α = zeros(T, n)
    β = zeros(T, n+1)
    β[1] = sqrt(ν[1])
    σ = zeros(T, 2n, n)
    for l = 1:2n
        σ[l,1] = ν[l] / β[1]
    end
    α[1] = a[1] + b[2] * ( σ[2,1] / σ[1,1] )
    if n >= 2
        # handle k=1 separately since we have omitted σ[l,0]=0.
        t = ( 1 + (b[3]/b[2]) * (σ[3,1]/σ[1,1])
                + ( (a[2]-α[1])/b[2] ) * (σ[2,1]/σ[1,1]) )
        if t < 0
            error("modified Chebyshev algorithm failed at k = 1")
        end
        β[2] = b[2] * sqrt(t)
        for l = 1:2n-2
            σ[l+1,2] = ( (b[l+2]/β[2])*σ[l+2,1]
                       + ((a[l+1]-α[1])/β[2]) * σ[l+1,1]
  	               + (b[l+1]/β[2]) * σ[l,1] )
        end
        α[2] = a[2] + b[3] * (σ[3,2]/σ[2,2]) - β[2] * (σ[2,1]/σ[2,2])
        # general k
        for k = 2:n-1
            t = ( 1 + (b[k+2]/b[k+1]) * (σ[k+2,k]/σ[k,k])
                    + ( (a[k+1]-α[k])/b[k+1] ) * (σ[k+1,k]/σ[k,k])
                    - (β[k]/b[k+1]) * (σ[k+1,k-1]/σ[k,k]) )
            β[k+1] = b[k+1] * sqrt(t)
            if t < 0
                error("modified Chebyshev algorithm failed at k = $k")
            end
            for l = k:2n-k-1
                σ[l+1,k+1] = ( (b[l+2]/β[k+1]) * σ[l+2,k]
                             + ( (a[l+1]-α[k])/β[k+1] ) * σ[l+1,k]
                             + (b[l+1]/β[k+1]) * σ[l,k]
                             - (β[k]/β[k+1]) * σ[l+1,k-1] )
            end
	    α[k+1] = ( a[k+1] + b[k+2] * (σ[k+2,k+1]/σ[k+1,k+1])
                              - β[k+1] * (σ[k+1,k]/σ[k+1,k+1]) )
        end
    end
    return α, β, σ
end

function solve(n::Integer, shift::T, a::Array{T,1},
               b::Array{T,1}) where {T<:AbstractFloat}
    #
    # Perform elimination to find the nth component s = delta[n]
    # of the solution to the nxn linear system
    #
    #     ( J_n - shift I_n ) delta = e_n,
    #
    # where J_n is the symmetric tridiagonal matrix with diagonal
    # entries a[i] and off-diagonal entries b[i], and e_n is the nth
    # standard basis vector.
    #
    t = a[1] - shift
    for i = 2:n-1
        t = a[i] - shift - b[i]^2 / t
    end
    return one(t) / t
end

function special_eigenproblem!(d::Array{T,1}, e::Array{T,1}, z::Array{T,1},
                               maxits::Integer) where {T<:AbstractFloat}
    #
    # Finds the eigenvalues and first components of the normalised
    # eigenvectors of a symmetric tridiagonal matrix by the implicit
    # QL method.
    #
    # d[i]   On entry, holds the ith diagonal entry of the matrix.
    #        On exit, holds the ith eigenvalue.
    #
    # e[i]   On entry, holds the [i,i-1] entry of the matrix for
    #        i = 2, 3, ..., n.  (The value of e[1] is not used.)
    #        On exit, e is overwritten.
    #
    # z[i]   On exit, holds the first component of the ith normalised
    #        eigenvector associated with d[i].
    #
    # maxits The maximum number of QL iterations.
    #
    # Martin and Wilkinson, Numer. Math. 12: 377-383 (1968).
    # Dubrulle, Numer. Math. 15: 450 (1970).
    # Handbook for Automatic Computation, Vol ii, Linear Algebra,
    #        pp. 241-248, 1971.
    #
    # This is a modified version of the Eispack routine imtql2.
    #
    n = length(z)
    z[1] = one(T)
    z[2:n] .= zero(T)
    e[n+1] = zero(T)

    if n == 1 # Nothing to do for a 1x1 matrix.
        return
    end
    for l = 1:n
        for j = 1:maxits
            # Look for small off-diagonal elements.
            m = n
            for i = l:n-1
                if abs(e[i+1]) <= eps(T) * ( abs(d[i]) + abs(d[i+1]) )
                    m = i
                    break
                end
            end
            p = d[l]
            if m == l
                continue
            end
            if j == maxits
                msg = string("No convergence after ", j, " iterations",
                             " (try increasing maxits)")
                error(msg)
            end
            # Form shift
            g = ( d[l+1] - p ) / ( 2 * e[l+1] )
            r = hypot(g, one(T))
            g = d[m] - p + e[l+1] / ( g + copysign(r, g) )
            s = one(T)
            c = one(T)
            p = zero(T)
            for i = m-1:-1:l
                f = s * e[i+1]
                b = c * e[i+1]
                if abs(f) <  abs(g)
                    s = f / g
                    r = hypot(s, one(T))
                    e[i+2] = g * r
                    c = one(T) / r
                    s *= c
                else
                    c = g / f
                    r = hypot(c, one(T))
                    e[i+2] = f * r
                    s = one(T) / r
                    c *= s
                end
                g = d[i+1] - p
                r = ( d[i] - g ) * s + 2 * c * b
                p = s * r
                d[i+1] = g + p
                g = c * r - b
                # Form first component of vector.
                f = z[i+1]
                z[i+1] = s * z[i] + c * f
                z[i]   = c * z[i] - s * f
            end # loop over i
            d[l] -= p
            e[l+1] = g
            e[m+1] = zero(T)
        end # loop over j
    end # loop over l
end

function orthonormal_poly(x::AbstractVector{T}, a::AbstractVector{T},
                          b::AbstractVector{T}) where {T<:AbstractFloat}
    # p[i,j] = value at x[i] of orthonormal polynomial of degree j-1.
    m = length(x)
    n = length(a)
    p = zeros(T, m, n+1)
    rb1 = one(T) / b[1]
    if n == 0
        for i = 1:m
            p[i,1] = rb1
        end
        return p
    end
    rb2 = one(T) / b[2]
    for i = 1:m
        p[i,1] = rb1
        p[i,2] = rb2 * ( x[i] - a[1] ) * p[i,1]
    end
    for j = 2:n
        rb = one(T) / b[j+1]
        for i = 1:m
            p[i,j+1] = rb * ( (x[i]-a[j]) * p[i,j]
                              - b[j] * p[i,j-1] )
        end
    end
    return p
end

end
