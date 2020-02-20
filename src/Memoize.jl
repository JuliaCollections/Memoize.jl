module Memoize
using MacroTools: combinedef, namify, splitarg, splitdef
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
    fcache = isdefined(mod, fcachename) ?
             getfield(mod, fcachename) :
             Core.eval(mod, :(const $fcachename = ($dicttype)()))

    if length(kws) == 0
        lookup = :($fcache[($(tup...),)]::Core.Compiler.return_type($u, typeof(($(identargs...),))))
    else
        lookup = :($fcache[($(tup...),)])
    end

    def_dict[:body] = quote
        haskey($fcache, ($(tup...),)) ? $lookup :
        ($fcache[($(tup...),)] = $u($(identargs...),; $(identkws...)))
    end
    esc(quote
        $(combinedef(def_dict_unmemoized))
        empty!($fcache)
        Base.@__doc__ $(combinedef(def_dict))
    end)

end
end
