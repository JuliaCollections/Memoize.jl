module Memoize
using MacroTools: isexpr, combinedef, namify, splitarg, splitdef
export @memoize, memories

# which(signature::Tuple) is only on 1.6, but previous julia versions
# use the following code under the hood anyway.
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
    @gensym meth

    sig = :(Tuple{typeof($(def_dict[:name])), $((splitarg(arg)[2] for arg in def_dict[:args])...)} where {$(def_dict[:whereparams]...)})

    esc(quote
        # The `local` qualifier will make this performant even in the global scope.
        local $cache = $cache_dict
        local $world = Base.get_world_counter()

        $(combinedef(def_dict_unmemoized))
        local $result = Base.@__doc__($(combinedef(def_dict)))

        if !@isdefined(__memories__)
            __memories__ = Dict()
        end
        
        # If overwriting a method, empty the old cache.
        # Notice that methods are hashed by their stored signature
        local $meth = $_which($sig, $world)
        if $meth !== nothing && $meth.sig == $sig
            if $meth.module == $__module__ && @isdefined(__memories__)
                empty!(pop!(__memories__, $meth.sig, []))
            elseif isdefined($meth.module, :__memories__)
                empty!(pop!($meth.module.__memories__, $meth.sig, []))
            end
        end

        # Store the cache so that it can be emptied later
        local $meth = $_which($sig)
        @assert $meth !== nothing
        __memories__[$meth.sig] = $cache

        $result
    end)
end

"""
    memories(f, [types], [module])
    
    Return an array containing all the memoized method caches for the function f
    defined at global scope. May also contain caches of overwritten methods.
    
    This function takes the same arguments as the method methods.
"""
memories(f, args...) = _memories(methods(f, args...))

function _memories(ms::Base.MethodList)
    caches = []
    for m in ms
        cache = memories(m)
        cache !== nothing && push!(caches, cache)
    end
    return caches
end

"""
    memories(m::Method)
    
    If m, defined at global scope, has not been overwritten, return it's
    memoized cache. Otherwise, return nothing or the cache of an overwritten
    method.
"""
function memories(m::Method)
    if isdefined(m.module, :__memories__)
        return get(m.module.__memories__, m.sig, nothing)
    end
    return nothing
end

end
