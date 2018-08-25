# Memoize.jl

[![Build Status](https://travis-ci.org/simonster/Memoize.jl.png?branch=master)](https://travis-ci.org/simonster/Memoize.jl) [![Coverage Status](https://coveralls.io/repos/github/simonster/Memoize.jl/badge.svg?branch=master)](https://coveralls.io/github/simonster/Memoize.jl?branch=master)

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
