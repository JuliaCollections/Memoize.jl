using Memoize, Test

# you can't use test_throws in macros
arun = 0
@memoize function memadd(x::Int, y::Int)::Int
    global arun += 1
    print("evaluating memadd $x $y\n")
    return x + y
end
@test memadd(1,2) == 3
@test memadd(1,4) == 5
@test memadd(1,2) == 3
@test arun == 2

run = 0
@memoize function simple(a)
    global run += 1
    a
end
@test simple(5) == 5
@test run == 1
@test simple(5) == 5
@test run == 1
@test simple(6) == 6
@test run == 2
@test simple(6) == 6
@test run == 2

run = 0
@memoize function typed(a::Int)
    global run += 1
    a
end
@test typed(5) == 5
@test run == 1
@test typed(5) == 5
@test run == 1
@test typed(6) == 6
@test run == 2
@test typed(6) == 6
@test run == 2

run = 0
@memoize function default(a=2)
    global run += 1
    a
end
@test default() == 2
@test run == 1
@test default() == 2
@test run == 1
@test default(2) == 2
@test run == 1
@test default(6) == 6
@test run == 2
@test default(6) == 6
@test run == 2

run = 0
@memoize function default_typed(a::Int=2)
    global run += 1
    a
end
@test default_typed() == 2
@test run == 1
@test default_typed() == 2
@test run == 1
@test default_typed(2) == 2
@test run == 1
@test default_typed(6) == 6
@test run == 2
@test default_typed(6) == 6
@test run == 2

run = 0
@memoize function kw(; a=2)
    global run += 1
    a
end
@test kw() == 2
@test run == 1
@test kw() == 2
@test run == 1
@test kw(a=2) == 2
@test run == 1
@test kw(a=6) == 6
@test run == 2
@test kw(a=6) == 6
@test run == 2

run = 0
@memoize function kw_typed(; a::Int=2)
    global run += 1
    a
end
@test kw_typed() == 2
@test run == 1
@test kw_typed() == 2
@test run == 1
@test kw_typed(a=2) == 2
@test run == 1
@test kw_typed(a=6) == 6
@test run == 2
@test kw_typed(a=6) == 6
@test run == 2

run = 0
@memoize function default_kw(a=1; b=2)
    global run += 1
    (a, b)
end
@test default_kw() == (1, 2)
@test run == 1
@test default_kw() == (1, 2)
@test run == 1
@test default_kw(1, b=2) == (1, 2)
@test run == 1
@test default_kw(1, b=3) == (1, 3)
@test run == 2
@test default_kw(1, b=3) == (1, 3)
@test run == 2
@test default_kw(2, b=3) == (2, 3)
@test run == 3
@test default_kw(2, b=3) == (2, 3)
@test run == 3

run = 0
@memoize function default_kw_typed(a::Int=1; b::Int=2)
    global run += 1
    (a, b)
end
@test default_kw_typed() == (1, 2)
@test run == 1
@test default_kw_typed() == (1, 2)
@test run == 1
@test default_kw_typed(1, b=2) == (1, 2)
@test run == 1
@test default_kw_typed(1, b=3) == (1, 3)
@test run == 2
@test default_kw_typed(1, b=3) == (1, 3)
@test run == 2
@test default_kw_typed(2, b=3) == (2, 3)
@test run == 3
@test default_kw_typed(2, b=3) == (2, 3)
@test run == 3

run = 0
@memoize function ellipsis(a, b...)
    global run += 1
    (a, b)
end
@test ellipsis(1) == (1, ())
@test run == 1
@test ellipsis(1) == (1, ())
@test run == 1
@test ellipsis(1, 2, 3) == (1, (2, 3))
@test run == 2
@test ellipsis(1, 2, 3) == (1, (2, 3))
@test run == 2

run = 0
@memoize Dict function kw_ellipsis(;a...)
    global run += 1
    a
end
@test isempty(kw_ellipsis())
@test run == 1
@test isempty(kw_ellipsis())
@test run == 1
@test kw_ellipsis(a=1) == pairs((a=1,))
@test run == 2
@test kw_ellipsis(a=1) == pairs((a=1,))
@test run == 2
@test kw_ellipsis(a=1, b=2) == pairs((a=1,b=2))
@test run == 3
@test kw_ellipsis(a=1, b=2) == pairs((a=1,b=2))
@test run == 3

run = 0
@memoize function multiple_dispatch(a::Int)
    global run += 1
    1
end
@memoize function multiple_dispatch(a::Float64)
    global run += 1
    2
end
@test multiple_dispatch(1) == 1
@test run == 1
@test multiple_dispatch(1) == 1
@test run == 1
@test multiple_dispatch(1.0) == 2
@test run == 2
@test multiple_dispatch(1.0) == 2
@test run == 2

function outer()
    run = 0
    @memoize function inner(x)
        run += 1
        x
    end
    @memoize function inner(x, y)
        run += 1
        x+y
    end
    @test inner(5) == 5
    @test run == 1
    @test inner(5) == 5
    @test run == 1
    @test inner(6) == 6
    @test run == 2
    @test inner(6) == 6
    @test run == 2
    @test inner(5, 1) == 6
    @test run == 3
    @test inner(5, 1) == 6
    @test run == 3
end
outer()
@test !@isdefined inner

if VERSION >= v"0.5.0-dev+5235"
    @memoize function typeinf(x)
        x + 1
    end
    @inferred typeinf(1)
    @inferred typeinf(1.0)
end

println("The following method rewrite warnings are normal")
finalized = false
@memoize function method_rewrite()
    x = []
    finalizer(x->(global finalized; finalized = true),x)
    x
end
method_rewrite()
@memoize function method_rewrite() end
GC.gc()
@test finalized
