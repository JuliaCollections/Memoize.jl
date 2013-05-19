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

## Implementation notes

- `@memoize` currently uses an ordinary Dict to store tuples. An ObjectIdDict might be faster, and a WeakKeyDict might be necessary to avoid memory leaks in some situations. This needs more consideration.
- Type inference will not work for memoized functions. If performance is critical, consider annotating the type of the output of the memoized function.