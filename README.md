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