module Memoize
export @memoize

macro memoize(args...)
    if length(args) == 1
        dicttype = :(ObjectIdDict)
        ex = args[1]
    elseif length(args) == 2
        (dicttype, ex) = args
    else
        error("Memoize accepts at most two arguments")
    end

    if !isa(ex,Expr) || (ex.head != :function && ex.head != symbol("=")) ||
       isempty(ex.args) || ex.args[1].head != :call || isempty(ex.args[1].args)
        error("@memoize must be applied to a method definition")
    end
    f = ex.args[1].args[1]
    ex.args[1].args[1] = u = symbol(string(f,"_unmemoized"))

    args = ex.args[1].args[2:end]

    # Extract keywords from AST
    kws = {}
    vals = copy(args)
    if length(vals) > 0 && isa(vals[1], Expr) && vals[1].head == :parameters
        kws = shift!(vals).args
    end

    # Set up arguments for tuple to encode keywords
    tup = Array(Any, length(kws)+length(vals))
    i = 1
    for val in vals
        tup[i] = if isa(val, Expr)
                if val.head == :... || val.head == :kw
                    val.args[1]
                elseif val.head == :(::)
                    val
                else
                    error("@memoize did not understand method syntax $val")
                end
            else
                val
            end
        i += 1
    end

    for kw in kws
        if isa(kw, Expr) && (kw.head == :kw || kw.head == :...)
            tup[i] = kw.args[1]
        else
            error("@memoize did not understand method syntax")
        end
        i += 1
    end

    # Set up identity arguments to pass to unmemoized function
    identargs = Array(Any, (length(kws) > 0)+length(vals))
    i = (length(kws) > 0) + 1
    for val in vals
        if isa(val, Expr)
            if val.head == :kw
                val = val.args[1]
            end
            if isa(val, Expr) && val.head == :(::)
                val = val.args[1]
            end
        end
        identargs[i] = val
        i += 1
    end
    if length(kws) > 0
        identkws = map(kws) do kw
            if kw.head == :kw
                key = kw.args[1]
                if isa(key, Expr) && key.head == :(::)
                    key = key.args[1]
                end
                Expr(:kw, key, key)
            else
                kw
            end
        end
        identargs[1] = Expr(:parameters, identkws...)
    end

    # Generate function
    # This construction is bizarre, but it was the only thing I could devise
    # that passes the tests included with this package and also frees the cache
    # when a function is reloaded. Improvements are welcome.
    quote
        $(esc(ex))
        isdef = false
        try
            $(esc(f))
            isdef = true
        end
        if isdef
            for i = 1
                $(esc(quote
                    local fcache
                    const fcache = ($dicttype)()
                    $(f)($(args...),) = 
                        haskey(fcache, ($(tup...),)) ? fcache[($(tup...),)] :
                        (fcache[($(tup...),)] = $(u)($(identargs...),))
                end))
            end
        else
            $(esc(quote
                const $(f) = let
                    local fcache, $f
                    const fcache = ($dicttype)()
                    $(f)($(args...),) = 
                        haskey(fcache, ($(tup...),)) ? fcache[($(tup...),)] :
                        (fcache[($(tup...),)] = $(u)($(identargs...),))
                end
            end))
        end
    end
end
end
