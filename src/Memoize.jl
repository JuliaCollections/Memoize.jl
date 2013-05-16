module Memoize
export @memoize

macro memoize(ex)
    if !isa(ex,Expr) || (ex.head != :function && ex.head != symbol("=")) ||
       isempty(ex.args) || ex.args[1].head != :call || isempty(ex.args[1].args)
        error("@memoize must be applied to a method definition")
    end
    f = ex.args[1].args[1]
    u = symbol(string(f,"_unmemoized"))

    args = ex.args[1].args[2:end]

    # Extract keywords/defaults from AST
    if length(args) >= 2 &&
       isa(args[1], Expr) && args[1].head == :keywords
        kws = [args[1].args..., args[2].args...]
        vals = args[3:end]
    elseif length(args) >= 1 && isa(args[1], Expr) &&
           (args[1].head == :keywords || args[1].head == :parameters)
        kws = args[1].args
        vals = args[2:end]
    else
        kws = []
        vals = args
    end

    # Set up arguments for tuple to encode keywords/defaults
    tup = Array(Any, length(kws)+length(vals))
    for i = 1:length(kws)
        kw = kws[i]
        if isa(kw, Expr) && (kw.head == :(=) || kw.head == :...)
            tup[i] = kw.args[1]
        else
            error("@memoize did not understand method syntax")
        end
    end

    # Handle ellipses in arguments
    for i = 1:length(vals)
        val = vals[i]
        tup[length(kws)+i] = isa(val, Expr) && val.head === :... ?
            val.args[1] : val
    end

    # Simplify arguments to unmemoized function to remove keywords/defaults
    ex.args[1].args = Any[u, tup...]

    f_cache = symbol(string(f,"_cache"))
    quote
        $(esc(ex))
        const ($(esc(f_cache))) = (Tuple=>Any)[]
        $(esc(quote
            $(f)($(args...),) = 
            haskey(($f_cache),($(tup...),)) ? ($f_cache)[($(tup...),)] :
            ($(f_cache)[($(tup...),)] = $(u)($(tup...),))
        end))
    end
end
end
