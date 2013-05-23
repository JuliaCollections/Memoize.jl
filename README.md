# Memoize.jl

Easy memoization for Julia.

## Usage

```julia
using Memoize
@memoize function x(a)
	println("Running")
	a
end
```

```
julia> x(1)
Running
1

julia> x(1)
1
```

By default, Memoize.jl uses an `ObjectIdDict` as a cache, but it's also possible to specify the type of the cache. If you want to cache vectors based on the values they contain, you probably want this:

```julia
using Memoize
@memoize Dict function x(a)
	println("Running")
	a
end
```

## Implementation notes

- Type inference will not work for memoized functions. If performance is critical, consider annotating the type of the output of the memoized function.