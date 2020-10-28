module Memoize
using MacroTools: isexpr, combinedef, namify, splitarg, splitdef
export @memoize

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

    fcachename = Symbol("##", f, "_memoized_cache")
    mod = __module__

    if length(kws) == 0
        lookup = :($fcachename[($(tup...),)]::Core.Compiler.return_type($u, typeof(($(identargs...),))))
    else
        lookup = :($fcachename[($(tup...),)])
    end

    def_dict[:body] = quote
        haskey($fcachename, ($(tup...),)) ? $lookup :
        ($fcachename[($(tup...),)] = $u($(identargs...),; $(identkws...)))
    end
    esc(quote
        $fcachename = $cache_dict  # this should be `const` for performance, but then this
                                   # fails the local-function cache test.
        $(combinedef(def_dict_unmemoized))
        empty!($fcachename)
        Base.@__doc__ $(combinedef(def_dict))
    end)

end
end
