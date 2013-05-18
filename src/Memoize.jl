module Memoize
export @memoize

macro memoize(ex)
    if !isa(ex,Expr) || (ex.head != :function && ex.head != symbol("=")) ||
       isempty(ex.args) || ex.args[1].head != :call || isempty(ex.args[1].args)
        error("@memoize must be applied to a method definition")
    end
    f = ex.args[1].args[1]
    ex.args[1].args[1] = u = symbol(string(f,"_unmemoized"))

    args = ex.args[1].args[2:end]

    # Extract keywords/defaults from AST
    kws = {}
    defaults = {}
    vals = copy(args)
    if length(vals) > 0 && isa(vals[1], Expr) && vals[1].head == :keywords
        defaults = shift!(vals).args
    end
    if length(vals) > 0 && isa(vals[1], Expr) && vals[1].head == :parameters
        kws = shift!(vals).args
    end

    # Set up arguments for tuple to encode keywords/defaults
    tup = Array(Any, length(kws)+length(defaults)+length(vals))
    i = 1
    for kw in vcat(kws, defaults)
        if isa(kw, Expr) && (kw.head == :(=) || kw.head == :...)
            tup[i] = kw.args[1]
        else
            error("@memoize did not understand method syntax")
        end
        i += 1
    end

    # Handle ellipses in arguments
    tup[i:end] = [(isa(val, Expr) && val.head === :...) ? val.args[1] : val for val in vals]

    # Set up identity arguments to pass to unmemoized function
    identargs = Array(Any, (length(kws) > 0)+length(defaults)+length(vals))
    i = (length(kws) > 0) + 1
    for val in vcat(defaults, vals)
        if isa(val, Expr)
            if val.head == :(=)
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
            if kw.head == :(=)
                key = kw.args[1]
                if isa(key, Expr) && key.head == :(::)
                    key = key.args[1]
                end
                :($key=$key)
            else
                kw
            end
        end
        identargs[1] = Expr(:keywords, identkws...)
    end

    fcache = symbol(string(f,"_cache"))
    # Generate function
    esc(quote
        $(ex)
        let
            local fcache = (Tuple=>Any)[]
            global $(f)
            $(f)($(args...),) = 
                haskey(fcache, ($(tup...),)) ? fcache[($(tup...),)] :
                (fcache[($(tup...),)] = $(u)($(identargs...),))
        end
    end)
end
end
