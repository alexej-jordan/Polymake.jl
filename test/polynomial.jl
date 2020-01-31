using SparseArrays
@testset "Polymake.Polynomial" begin
    IntTypes = [Int32, Int64, UInt64, BigInt]
    FloatTypes = [Float32, Float64, BigFloat]
    RationalTypes = [Rational{I} for I in IntTypes]

    for C in [Int64, Polymake.Integer, Polymake.Rational, Float64]
        @test Polymake.Polynomial{C,Int64} <: Any
        @test Polymake.Polynomial{C,Int64}([1, 2],[3 4 5; 6 7 8]) isa Any
        @test Polymake.Polynomial{C,Int64}([1, 2],[3 4 5; 6 7 8]) isa Polymake.Polynomial
        @test Polymake.Polynomial{C,Int64}([1, 2],[3 4 5; 6 7 8]) isa Polymake.Polynomial{C,Int64}
    end

    jl_v = [1, 2]
    jl_m = [3 4 5; 6 7 0]
    @testset "Constructors/Converts" begin
        for C in [Int64, Polymake.Integer, Polymake.Rational, Float64]
            @test Polymake.Polynomial(C.(jl_v), jl_m) isa Polymake.Polynomial{C,Int64}
            @test Polymake.Polynomial{Float64}(C.(jl_v), jl_m) isa Polymake.Polynomial{Float64,Int64}
            @test Polymake.Polynomial{Polymake.Rational,Int64}(C.(jl_v), jl_m) isa Polymake.Polynomial{Polymake.Rational,Int64}
        end
    end

    @testset "Low-level operations" begin
        for (C,s) in [(Int64, "long"), (Polymake.Integer, "pm::Integer"), (Polymake.Rational, "pm::Rational"), (Float64, "double")]
            p = Polymake.Polynomial(C.(jl_v),jl_m)
            @test Polymake.nvars(p) == size(jl_m)[2]
            @test string(p) == string("pm::Polynomial<", s, ", long>\n2*x_0^6*x_1^7 + x_0^3*x_1^4*x_2^5")
            Polymake.set_var_names(p,["x", "y", "z"])
            @test Polymake.get_var_names(p) == ["x", "y", "z"]
            @test string(p) == string("pm::Polynomial<", s, ", long>\n2*x^6*y^7 + x^3*y^4*z^5")
            @test Polymake.coefficients_as_vector(p) isa Polymake.Vector
            @test Polymake.coefficients_as_vector(p) isa Polymake.Vector{C}
            v = Polymake.coefficients_as_vector(p)
            perm1 = sortperm(jl_v)
            perm2 = sortperm(v)
            @test  v[perm2] == jl_v[perm1]
            @test Polymake.monomials_as_matrix(p) isa Polymake.SparseMatrix
            @test Polymake.monomials_as_matrix(p) isa Polymake.SparseMatrix{Int64}
            m = Polymake.monomials_as_matrix(p)
            @test m[perm2, :] == jl_m[perm1, :]
        end
    end

    @testset "Equality" begin
        for C1 in [Int64, Polymake.Integer, Polymake.Rational, Float64], C2 in [Int64, Polymake.Integer, Polymake.Rational, Float64]
            @test Polymake.Polynomial(C1.(jl_v),jl_m) == Polymake.Polynomial(C2.(jl_v),jl_m)
        end
    end

    @testset "Arithmetic" begin
        jl_v2 = [5, 6]
        jl_m2 = [3 4 5; 6 7 8]
        for C1 in [Int64, Polymake.Integer, Polymake.Rational, Float64]
            p = Polymake.Polynomial{C1}(jl_v,jl_m)
            for C2 in [Int64, Polymake.Integer, Polymake.Rational, Float64]
                q = Polymake.Polynomial{C2}(jl_v2,jl_m2)
                @test p + q isa Polymake.Polynomial{promote_type(C1,C2)}
                @test p + q == Polymake.Polynomial([6, 2, 6],[3 4 5; 6 7 0; 6 7 8])
                @test p * q isa Polymake.Polynomial{promote_type(C1,C2)}
                @test p * q == Polymake.Polynomial([12, 6, 10, 5],[12 14 8; 9 11 13; 9 11 5; 6 8 10])
                @test p - q isa Polymake.Polynomial{promote_type(C1,C2)}
                @test p - q == Polymake.Polynomial([-4, 2, -6],[3 4 5; 6 7 0; 6 7 8])
            end
            @test p^3 isa Polymake.Polynomial{C1}
            @test p^3 == Polymake.Polynomial([8, 12, 6, 1],[18 21 0; 15 18 5; 12 15 10; 9 12 15])
            # @test p/2 isa Polymake.Polynomial{C1}
            # @test p/2 == Polymake.Polynomial{C1}(jl_v/2,jl_m)
            # @test -p isa Polymake.Polynomial{C1}
            # @test -p == Polymake.Polynomial(-jl_v,-jl_m)
            # @test p + 8 isa Polymake.Polynomial{C1}
            # @test 8 + p isa Polymake.Polynomial{C1}
            # @test p + 8 == Polymake.Polynomial(jl_v2, jl_m2)
            # @test 8 + p == Polymake.Polynomial(jl_v2, jl_m2)
        end
    end

end