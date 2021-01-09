module TestPrecompile
    using Memoize
    run = 0
    @memoize function forgetful(x)
        global run += 1
        return true
    end
        
    forgetful(1)
end # module
