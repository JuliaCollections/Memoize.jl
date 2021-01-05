# Memoize.jl

[![Build Status][ci-img]][ci-url]
[![Coverage Status](https://coveralls.io/repos/github/JuliaCollections/Memoize.jl/badge.svg?branch=master)](https://coveralls.io/github/JuliaCollections/Memoize.jl?branch=master)

[ci-img]: https://github.com/JuliaCollections/Memoize.jl/workflows/CI/badge.svg
[ci-url]: https://github.com/JuliaCollections/Memoize.jl/actions

Easy method memoization for Julia.

## Usage

```julia
using Memoize
@memoize function x(a)
	println("Running")
	2a
end
```

```
julia> x(1)
Running
2

julia> memories(x)
1-element Array{Any,1}:
 IdDict{Tuple{Any},Any}((1,) => 2)

julia> x(1)
2

julia> map(empty!, memories(x))
1-element Array{IdDict{Tuple{Any},Any},1}:
 IdDict()

julia> x(1)
Running
2

julia> x(1)
2
```

By default, Memoize.jl uses an [`IdDict`](https://docs.julialang.org/en/v1/base/collections/#Base.IdDict) as a cache, but it's also possible to specify your own cache that supports the methods `Base.get!` and `Base.empty!`. If you want to cache vectors based on the values they contain, you probably want this:

```julia
using Memoize
@memoize Dict() function x(a)
	println("Running")
	a
end
```

You can also specify the full expression for constructing the cache. The variables `__Key__` and `__Val__` are available to the constructor expression, containing the syntactically determined type bounds on the keys and values used by Memoize.jl.  For example, to use LRUCache.jl:

```julia
using Memoize
using LRUCache
@memoize LRU{__Key__,__Val__}(maxsize=2) function x(a, b)
    println("Running")
    a + b
end
```

```julia
julia> x(1,2)
Running
3

julia> x(1,2)
3

julia> x(2,2)
Running
4

julia> x(2,3)
Running
5

julia> x(1,2)
Running
3

julia> x(2,3)
5
```

Memoize works on *almost* every method declaration in global and local scope, including lambdas and callable objects. When only the type of an argument is given, memoize caches the type.

julia```
struct F{A}
	a::A
end
@memoize function (::F{A})(b, ::C) where {A, C}
	println("Running")
	(A, b, C)
end
```

```
julia> F(1)(1, 1)
Running
(Int64, 1, Int64)

julia> F(1)(1, 2)
(Int64, 1, Int64)

julia> F(1)(2, 2)
Running
(Int64, 2, Int64)

julia> F(2)(2, 2)
(Int64, 2, Int64)

julia> F(false)(2, 2)
Running
(Bool, 2, Int64)
```
