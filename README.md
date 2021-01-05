# Memoize.jl

[![Build Status](https://travis-ci.org/JuliaCollections/Memoize.jl.png?branch=master)](https://travis-ci.org/JuliaCollections/Memoize.jl) [![Coverage Status](https://coveralls.io/repos/github/JuliaCollections/Memoize.jl/badge.svg?branch=master)](https://coveralls.io/github/JuliaCollections/Memoize.jl?branch=master)

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
 IdDict{Any,Any}((1,) => 2)

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

By default, Memoize.jl uses an [`IdDict`](https://docs.julialang.org/en/v1/base/collections/#Base.IdDict) as a cache, but it's also possible to specify the type of the cache. If you want to cache vectors based on the values they contain, you probably want this:

```julia
using Memoize
@memoize Dict function x(a)
	println("Running")
	a
end
```

You can also specify the full function call for constructing the dictionary. For example, to use LRUCache.jl:

```julia
using Memoize
using LRUCache
@memoize LRU{Tuple{Any,Any},Any}(maxsize=2) function x(a, b)
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
