module Memoize
using MacroTools: isexpr, combinedef, namify, splitarg, splitdef
export @memoize, memories, memory

# I would call which($sig) but it's only on 1.6 I think
function _which(tt, world = typemax(UInt))
    meth = ccall(:jl_gf_invoke_lookup, Any, (Any, UInt), tt, world)
    if meth !== nothing
        if meth isa Method
            return meth::Method
        else
            meth = meth.func
            return meth::Method
        end
    end
end

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

    @gensym cache
    mod = __module__

    body = quote
        get!($cache, ($(tup...),)) do
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

    @gensym world
    @gensym old_meth
    @gensym meth
    @gensym brain
    @gensym old_brain

    sig = :(Tuple{typeof($(def_dict[:name])), $((splitarg(arg)[2] for arg in def_dict[:args])...)} where {$(def_dict[:whereparams]...)})

    esc(quote
        # The `local` qualifier will make this performant even in the global scope.
        local $cache = $cache_dict
        local $world = Base.get_world_counter()

        $(combinedef(def_dict_unmemoized))
        local $result = Base.@__doc__($(combinedef(def_dict)))

        if isdefined($__module__, :__Memoize_brain__)
            local $brain = $__module__.__Memoize_brain__
        else
            global __Memoize_brain__ = Dict()
            local $brain = __Memoize_brain__
            $__module__
        end
        
        # If overwriting a method, empty the old cache.
        # Notice that methods are hashed by their stored signature
        local $old_meth = $_which($sig, $world)
        if $old_meth !== nothing && $old_meth.sig == $sig
            if isdefined($old_meth.module, :__Memoize_brain__)
                $old_brain = $old_meth.module.__Memoize_brain__
                empty!(pop!($old_brain, $old_meth.sig, []))
            end
        end

        # Store the cache so that it can be emptied later
        local $meth = $_which($sig)
        @assert $meth !== nothing
        $brain[$meth.sig] = $cache

        $result
    end)
end

"""
    memories(f, [types], [module])
    
    Return an array of memoized method caches for the function f.
    
    This function takes the same arguments as the method methods.
"""
memories(f, args...) = _memories(methods(f, args...))

function _memories(ms::Base.MethodList)
    memories = []
    for m in ms
        cache = memory(m)
        cache !== nothing && push!(memories, cache)
    end
    return memories
end

"""
    memory(m)
    
    Return the memoized cache for the method m, or nothing if no such method exists
"""
function memory(m::Method)
    if isdefined(m.module, :__Memoize_brain__)
        brain = m.module.__Memoize_brain__
        return get(brain, m.sig, nothing)
    end
    return nothing
end

end
