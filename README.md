# Memoize.jl

[![Build Status][ci-img]][ci-url]
[![Coverage Status](https://coveralls.io/repos/github/JuliaCollections/Memoize.jl/badge.svg?branch=master)](https://coveralls.io/github/JuliaCollections/Memoize.jl?branch=master)

[ci-img]: https://github.com/JuliaCollections/Memoize.jl/workflows/CI/badge.svg
[ci-url]: https://github.com/JuliaCollections/Memoize.jl/actions

Easy memoization for Julia.

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

julia> memoize_cache(x)
IdDict{Any,Any} with 1 entry:
  (1,) => 2

julia> x(1)
2

julia> empty!(memoize_cache(x))
IdDict{Any,Any}()

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

## Notes

Note that the `@memoize` macro treats the type argument differently depending on its syntactical form: in the expression
```julia
@memoize CacheType function x(a, b)
    # ...
end
```
the expression `CacheType` must be either a non-function-call that evaluates to a type, or a function call that evaluates to an _instance_ of the desired cache type.  Either way, the methods `Base.get!` and `Base.empty!` must be defined for the supplied cache type.
