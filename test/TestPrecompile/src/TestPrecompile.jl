module TestPrecompile
    using Memoize
    @memoize forgetful(x) = true
    forgetful(true)
end # module