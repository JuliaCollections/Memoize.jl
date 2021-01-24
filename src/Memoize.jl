module Memoize
using MacroTools: isexpr, combinedef, namify, splitarg, splitdef
export @memoize, forget!

macro memoize(args...)
    if length(args) == 1
        dicttype = :(IdDict)
        ex = args[1]
    elseif length(args) == 2
        (dicttype, ex) = args
    else
        error("Memoize accepts at most two arguments")
    end

    cache_dict = isexpr(dicttype, :call) ? dicttype : :(($dicttype)())

    def_dict = try
        splitdef(ex)
    catch
        error("@memoize must be applied to a method definition")
    end

    # a return type declaration of Any is a No-op because everything is <: Any
    rettype = get(def_dict, :rtype, Any)
    f = def_dict[:name]
    def_dict_unmemoized = copy(def_dict)
    def_dict_unmemoized[:name] = u = Symbol("##", f, "_unmemoized")

    args = def_dict[:args]
    kws = def_dict[:kwargs]
    # Set up arguments for tuple
    tup = [splitarg(arg)[1] for arg in vcat(args, kws)]

    @gensym result

    # Set up identity arguments to pass to unmemoized function
    identargs = map(args) do arg
        arg_name, typ, slurp, default = splitarg(arg)
        if slurp || namify(typ) === :Vararg
            Expr(:..., arg_name)
        else
            arg_name
        end
    end
    identkws = map(kws) do kw
        arg_name, typ, slurp, default = splitarg(kw)
        if slurp
            Expr(:..., arg_name)
        else
            Expr(:kw, arg_name, arg_name)
        end
    end

    cache = gensym(:__cache__)
    mod = __module__

    body = quote
        get!($cache[2], ($(tup...),)) do
            $u($(identargs...); $(identkws...))
        end
    end

    if length(kws) == 0
        def_dict[:body] = quote
            $(body)::Core.Compiler.return_type($u, typeof(($(identargs...),)))
        end
    else
        def_dict[:body] = body
    end

    f = def_dict[:name]
    sig = :(Tuple{typeof($f), $((splitarg(arg)[2] for arg in def_dict[:args])...)} where {$(def_dict[:whereparams]...)})
    tail = :(Tuple{$((splitarg(arg)[2] for arg in def_dict[:args])...)} where {$(def_dict[:whereparams]...)})

    scope = gensym()
    meth = gensym("meth")

    esc(quote
        # The `local` qualifier will make this performant even in the global scope.
        local $cache = ($tail, $cache_dict)

        $scope = nothing

        if isdefined($__module__, $(QuoteNode(scope)))
            function $f end

            # If overwriting a method, empty the old cache.
            # Notice that methods are hashed by their stored signature
            try
                local $meth = which($f, $tail)
                if $meth.sig == $sig && isdefined($meth.module, :__memories__)
                    empty!(pop!($meth.module.__memories__, $meth.sig, (nothing, []))[2])
                end
            catch
            end
        end

        $(combinedef(def_dict_unmemoized))
        local $result = Base.@__doc__($(combinedef(def_dict)))

        if isdefined($__module__, $(QuoteNode(scope)))
            if !@isdefined __memories__
                __memories__ = Dict()
            end
            # Store the cache so that it can be emptied later
            local $meth = $which($f, $tail)
            __memories__[$meth.sig] = $cache
        end

        $result
    end)
end

"""
    forget!(f, types)
    
    If the method `which(f, types)`, is memoized, `empty!` its cache in the
    scope of `f`.
"""
function forget!(f, types)
    for name in propertynames(f) #if f is a closure, we walk its fields
        if first(string(name), length("##__cache__")) == "##__cache__"
            cache = getproperty(f, name)
            if cache isa Core.Box
                cache = cache.contents
            end
            (cache[1] == types) && empty!(cache[2])
        end
    end
    forget!(which(f, types)) #otherwise, a method would suffice
end

"""
    forget!(m::Method)
    
    If m, defined at global scope, is a memoized function, `empty!` its
    cache.
"""
function forget!(m::Method)
    if isdefined(m.module, :__memories__)
        empty!(get(m.module.__memories__, m.sig, (nothing, []))[2])
    end
end

end
