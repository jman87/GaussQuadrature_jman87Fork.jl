module GaussQuadrature

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
#          ---
#          \
#           |  w[j] f(x[j])
#          /
#          ---
#          j=1
#
# approximates
#
#          / hi
#          |
#          |    f(x) w(x) dx
#          |
#          / lo
#
# where the weight function w(x) and interval lo < x < hi are as shown
# in the table below.
#
# Name                      Interval     Weight Function
#
# Legendre                 -1 < x < 1          1      
# Chebyshev (first kind)   -1 < x < 1     1 / sqrt(1-x^2)        
# Chebyshev (second kind)  -1 < x < 1       sqrt(1-x^2)          
# Jacobi                   -1 < x < 1   (1-x)^alpha (1+x)^beta  
# Laguerre                 0 < x < oo     x^alpha exp(-x)
# Hermite                 -oo < x < oo      exp(-x^2)
#
# For the Jacobi and Laguerre rules we require alpha > -1 and
# beta > -1, so that the weight function is integrable.
#
# Use the endpt argument to include one or both of the end points
# of the interval of integration as an abscissa in the quadrature 
# rule, as follows.
# 
# endpt = neither   Default      a < x[j] < b, j = 1:n.
# endpt = left      Left Radau   a = x[1] < x[j] < b, j = 2:n.
# endpt = right     Right Radau  a < x[j] < x[n] = b, j = 1:n-1.
# endpt = both      Lobatto      a = x[1] < x[j] < x[n] = b, j = 2:n-1.
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
export legendre, legendre_coeff
export chebyshev, chebyshev_coeff
export jacobi, jacobi_coeff
export laguerre, laguerre_coeff 
export hermite, hermite_coeff
export custom_gauss_rule, orthonormal_poly
export steig!

"""
Enumeration type used to specify which endpoints of the integration
interval should be included amongst the quadrature points: neither,
left, right or both.
"""
immutable EndPt
    label :: Char
end

const neither = EndPt('N')
const left    = EndPt('L')
const right   = EndPt('R')
const both    = EndPt('B')

# Maximum number of QL iterations used by steig!.
# You might need to increase this.
maxiterations = Dict(Float32 => 30, Float64 => 30, BigFloat => 40)

"""
x, w = legendre(T, n, endpt=neither)

Returns points x and weights w for the n-point Gauss-Legendre rule
for the interval -1 < x < 1 with weight function w(x) = 1.

Use endpt=left, right, both for the left Radau, right Radau, Lobatto 
rules.
"""
function legendre{T<:AbstractFloat}(::Type{T}, 
                 n::Integer, endpt::EndPt=neither)
    a, b = legendre_coeff(T, n)
    return custom_gauss_rule(-one(T), one(T), a, b, endpt)
#    a, b, μ0 = legendre_coeff(T, n, endpt)
#    return custom_gauss_rule(-one(T), one(T), a, b, μ0, endpt)
end

"""
x, w = legendre(n, endpt=neither)

Convenience function with type T = Float64.
"""
legendre(n, endpt=neither) = legendre(Float64, n, endpt)

function legendre_coeff{T<:AbstractFloat}(::Type{T}, n::Integer)
    a = zeros(T, n)
    b = zeros(T, n)
    b[1] = sqrt(convert(T, 2))
    for k = 2:n
        b[k] = (k-1) / sqrt(convert(T, (2k-1)*(2k-3)))
    end
    return a, b
end

function legendre_coeff{T<:AbstractFloat}(::Type{T},
                       n::Integer, endpt::EndPt)
    warn("This method will be removed in GaussQuadrature 0.4")
    μ0 = convert(T, 2.0)
    a = zeros(T, n)
    b = zeros(T, n)
    for i = 1:n
        b[i] = i / sqrt(convert(T, 4*i^2-1))
    end
    return a, b, μ0
end

"""
x, w = chebyshev(T, n, kind=1, endpt=neither)

Returns points x and weights w for the n-point Gauss-Chebyshev rule
for the interval -1 < x < 1 with weight function

    w(x) = 1 / sqrt(1-x^2) if kind=1
    w(x) = sqrt(1-x^2)     if kind=2.

Use endpt=left, right, both for the left Radau, right Radau, Lobatto 
rules.
"""
function chebyshev{T<:AbstractFloat}(::Type{T},
                  n::Integer, kind::Integer=1, endpt::EndPt=neither)
    a, b, μ0 = chebyshev_coeff(T, n, kind, endpt)
    return custom_gauss_rule(-one(T), one(T), a, b, μ0, endpt)
end

"""
x, w = chebyshev(n, kind=1, endpt=neither)

Convenience function with type T = Float64.
"""
chebyshev(n, kind=1, endpt=neither) = chebyshev(Float64, n, kind, 
                                                endpt)

function chebyshev_coeff{T<:AbstractFloat}(::Type{T},
                        n::Integer, kind::Integer, endpt::EndPt)
    μ0 = convert(T, pi)
    half = convert(T, 0.5)
    a = zeros(T, n)
    b = fill(half, n)
    if kind == 1
        b[1] = sqrt(half)
    elseif kind == 2
        μ0 /= 2
    else
        error("Unsupported value for kind")
    end
    return a, b, μ0
end

"""
x, w = jacobi(n, alpha, beta, endpt=neither)

Returns points x and weights w for the n-point Gauss-Jacobi rule
for the interval -1 < x < 1 with weight function

    w(x) = (1-x)^alpha (1+x)^beta.

Use endpt=left, right, both for the left Radau, right Radau, Lobatto 
rules.
"""
function jacobi{T<:AbstractFloat}(n::Integer, alpha::T, beta::T, 
                                  endpt::EndPt=neither)
    @assert alpha > -1.0 && beta > -1.0
    a, b, μ0 = jacobi_coeff(n, alpha, beta, endpt)
    custom_gauss_rule(-one(T), one(T), a, b, μ0, endpt)
end

function jacobi_coeff{T<:AbstractFloat}(n::Integer, alpha::T, 
                                        beta::T, endpt::EndPt)
    ab = alpha + beta
    i = 2
    abi = ab + 2
    μ0 = 2^(ab+1) * exp(
             lgamma(alpha+1) + lgamma(beta+1) - lgamma(abi) )
    a = zeros(T, n)
    b = zeros(T, n)
    a[1] = ( beta - alpha ) / abi
    b[1] = sqrt( 4*(alpha+1)*(beta+1) / ( (ab+3)*abi*abi ) )
    a2b2 = beta*beta - alpha*alpha
    for i = 2:n
        abi = ab + 2i
        a[i] = a2b2 / ( (abi-2)*abi )
        b[i] = sqrt( 4i*(alpha+i)*(beta+i)*(ab+i) /
                     ( (abi*abi-1)*abi*abi ) )
    end   
    return a, b, μ0
end

"""
x, w = laguerre(n, alpha, endpt=neither)

Returns points x and weights w for the n-point Gauss-Laguerre rule
for the interval 0 < x < oo with weight function

    w(x) = x^alpha exp(-x)

Use endpt=left for the left Radau rule.
"""
function laguerre{T<:AbstractFloat}(n::Integer, alpha::T, 
                                    endpt::EndPt=neither)
    @assert alpha > -1.0
    a, b, μ0 = laguerre_coeff(n, alpha, endpt)
    custom_gauss_rule(zero(T), convert(T, Inf), a, b, μ0, endpt)
end

function laguerre_coeff{T<:AbstractFloat}(n::Integer, alpha::T, 
                                          endpt::EndPt)
    @assert endpt in [neither, left]
    μ0 = gamma(alpha+1)
    a = zeros(T, n)
    b = zeros(T, n)
    for i = 1:n
        a[i] = 2i - 1 + alpha
        b[i] = sqrt( i*(alpha+i) )
    end
    return a, b, μ0
end

"""
x, w = hermite(T, n)

Returns points x and weights w for the n-point Gauss-Laguerre rule
for the interval -oo < x < oo with weight function

    w(x) = exp(-x^2).
"""
function hermite{T<:AbstractFloat}(::Type{T}, n::Integer)
    a, b, μ0 = hermite_coeff(T, n)
    custom_gauss_rule(convert(T, -Inf), convert(T, Inf), a, b, 
                      μ0, neither)
end

"""
x, w = hermite(n)

Convenience function with type T = Float64.
"""
hermite(n) = hermite(Float64, n)

function hermite_coeff{T<:AbstractFloat}(::Type{T}, n::Integer)
    μ0 = sqrt(convert(T, pi))
    a = zeros(T, n)
    b = zeros(T, n)
    for i = 1:n
        iT = convert(T, i)
        b[i] = sqrt(iT/2)
    end
    return a, b, μ0
end

function logweight_coef{T<:AbstractFloat}(::Type{T}, n::Integer, 
                                          r::Integer, endpt::EndPt)
    a, b, ν0 = legendre_coeff(T, n, endpt)
end

function custom_gauss_rule{T<:AbstractFloat}(lo::T, hi::T, 
         a::Array{T,1}, b::Array{T,1}, endpt::EndPt,
         maxits::Integer=maxiterations[T])
    #
    # On entry:
    #
    # a, b hold the coefficients (as given, for instance, by
    # legendre_coeff) in the three-term recurrence relation
    # for the orthonormal polynomials ̂p₀, ̂p₁, ̂p₂, ... , that is,
    #
    #    b[k+1] ̂p (x) = (x-a[k]) ̂p   (x) - b[k] ̂p   (x).
    #            k                k-1            k-2
    #      
    # where, by convention
    #
    #              / hi
    #             |
    #    b[1]^2 = | w(x) dx.
    #             |
    #             / lo
    #
    # On return:
    #
    # x, w hold the points and weights.
    #
    n = length(a)
    @assert length(b) == n
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
    return a[idx], w[idx]
end

function custom_gauss_rule{T<:AbstractFloat}(lo::T, hi::T, 
         a::Array{T,1}, b::Array{T,1}, μ0::T, endpt::EndPt,
         maxits::Integer=maxiterations[T])
    #
    # On entry:
    #
    # a, b hold the coefficients (as given, for instance, by
    # legendre_coeff) in the three-term recurrence relation
    # for the orthonormal polynomials p_0, p_1, p_2, ... , that is,
    #
    #    b[j] p (x) = (x-a[j]) p   (x) - b[j-1] p   (x).
    #          j                j-1              j-2
    #      
    # μ0 holds the zeroth moment of the weight function, that is
    #
    #          / hi
    #         |
    #    μ0 = | w(x) dx.
    #         |
    #         / lo
    #
    # On return:
    #
    # x, w hold the points and weights.
    #
    warn("This method will be removed in GaussQuadrature 0.4")
    n = length(a)
    @assert length(b) == n
    if endpt == left 
        if n == 1
            a[1] = lo
        else
            a[n] = solve(n, lo, a, b) * b[n-1]^2 + lo
        end
    elseif endpt == right
        if n == 1
            a[1] = hi
        else
            a[n] = solve(n, hi, a, b) * b[n-1]^2 + hi
        end
    elseif endpt == both
        if n == 1 
            error("Must have at least two points for both ends.")
        end 
        g = solve(n, lo, a, b)
        t1 = ( hi - lo ) / ( g - solve(n, hi, a, b) )
        b[n-1] = sqrt(t1)
        a[n] = lo + g * t1
    end
    w = zero(a)
    steig!(a, b, w, maxits)
    for i = 1:n
        w[i] = μ0 * w[i]^2
    end
    idx = sortperm(a)
    return a[idx], w[idx]
end

function modified_chebyshev{T<:AbstractFloat}(
                  a::Vector{T}, b::Vector{T}, μ::Vector{T})
    n = length(a)
    @assert length(b) == n && length(μ) == 2n && n >= 1
    σ = zeros(T, 2n, n)
    for l = 1:2n
        σ[l,1] = μ[l]
    end
    α = zeros(T, n)
    β = zeros(T, n)
    α[1] = a[1] + μ[2]/μ[1]
    β[1] = sqrt(μ[1])
    if n >= 1
        for l = 1:2n-2
            σ[l+1,2] = ( σ[l+2,1] + ( a[l] - α[1] ) * σ[l+1,1]
  	             + b[l]^2 * σ[l,1] )
        end
        α[2] = a[2] + σ[3,2] / σ[2,2] - σ[2,1] / σ[1,1]
        β[2] = sqrt(σ[2,2] / σ[1,1])
        for k = 2:n-1
            for l = k:2n-k-1
                σ[l+1,k+1] = ( σ[l+2,k] + ( a[l] - α[k] ) * σ[l+1,k]
                         + b[l]^2 * σ[l,k] - β[k]^2 * σ[l+1,k-1] )
            end
	    α[k] = a[k] + σ[k+2,k+1] / σ[k+1,k+1] - σ[k+1,k] / σ[k,k]
	    β[k] = sqrt(σ[k+1,k+1] / σ[k,k])
        end
    end
    return α, β
end

function solve{T<:AbstractFloat}(n::Integer, shift::T, 
                                 a::Array{T,1}, b::Array{T,1})
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
        t = a[i] - shift - b[i-1]^2 / t
    end
    return one(t) / t
end

function special_eigenproblem!{T<:AbstractFloat}(d::Array{T,1}, e::Array{T,1}, 
                               z::Array{T,1}, maxits::Integer)
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
    z[1] = 1
    z[2:n] = 0
    e[1] = 0

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
                msg = @sprintf("No convergence after %d iterations", j)
                msg *= " (try increasing maxits)"
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
            e[l] = g
            e[m] = zero(T)
        end # loop over j
    end # loop over l
end

function steig!{T<:AbstractFloat}(d::Array{T,1}, e::Array{T,1}, 
                                  z::Array{T,1}, maxits::Integer)
    #
    # Finds the eigenvalues and first components of the normalised
    # eigenvectors of a symmetric tridiagonal matrix by the implicit
    # QL method.
    #
    # d[i]   On entry, holds the ith diagonal entry of the matrix. 
    #        On exit, holds the ith eigenvalue.
    #
    # e[i]   On entry, holds the [i+1,i] entry of the matrix for
    #        i = 1, 2, ..., n-1.  (The value of e[n] is not used.)
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
    z[1] = 1
    z[2:n] = 0
    e[n] = 0

    if n == 1 # Nothing to do for a 1x1 matrix.
        return
    end
    for l = 1:n
        for j = 1:maxits
            # Look for small off-diagonal elements.
            m = n
            for i = l:n-1
                if abs(e[i]) <= eps(T) * ( abs(d[i]) + abs(d[i+1]) )
                    m = i
                    break   
                end
            end
            p = d[l]
            if m == l
                continue
            end
            if j == maxits
                msg = @sprintf("No convergence after %d iterations", j)
                msg *= " (try increasing maxits)"
                error(msg)
            end
            # Form shift
            g = ( d[l+1] - p ) / ( 2 * e[l] )
            r = hypot(g, one(T))
            g = d[m] - p + e[l] / ( g + copysign(r, g) )
            s = one(T)
            c = one(T)
            p = zero(T)
            for i = m-1:-1:l
                f = s * e[i]
                b = c * e[i]
                if abs(f) <  abs(g)
                    s = f / g
                    r = hypot(s, one(T))
                    e[i+1] = g * r
                    c = one(T) / r
                    s *= c
                else
                    c = g / f
                    r = hypot(c, one(T))
                    e[i+1] = f * r
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
            e[l] = g
            e[m] = zero(T)
        end # loop over j
    end # loop over l
end

function orthonormal_poly{T<:AbstractFloat}(x::Array{T,1}, 
                         a::Array{T,1}, b::Array{T,1}, μ0::T)
    # p[i,j] = value at x[i] of orthonormal polynomial of degree j-1.
    m = length(x)
    n = length(a)
    p = zeros(T, m, n+1)
    c = one(T) / sqrt(μ0)
    rb = one(T) / b[1]
    for i = 1:m
        p[i,1] = c
        p[i,2] = rb * ( x[i] - a[1] ) * c
    end 
    for j = 2:n
       rb = one(T) / b[j]
       for i = 1:m
           p[i,j+1] = rb * ( (x[i]-a[j]) * p[i,j] 
                                - b[j-1] * p[i,j-1] )
       end
    end
    return p
end

end
