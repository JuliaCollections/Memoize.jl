module Memoize
using MacroTools: isexpr, combinearg, combinedef, namify, splitarg, splitdef, @capture
export @memoize, function_memories, method_memories

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

const _memories = Dict()

macro memoize(args...)
    if length(args) == 1
        cache_constructor = :(IdDict())
        ex = args[1]
    elseif length(args) == 2
        (cache_constructor, ex) = args
    else
        error("Memoize accepts at most two arguments")
    end

    def = try
        splitdef(ex)
    catch
        error("@memoize must be applied to a method definition")
    end

    # Set up arguments for memo key
    key_args = []
    key_arg_types = []

    # Ensure that all args have names that can be passed to the inner function
    function tag_arg(arg)
        arg_name, arg_type, slurp, default = splitarg(arg)
        if arg_name === nothing
            arg_name = gensym()
            push!(key_args, arg_type)
            push!(key_arg_types, :(Type{$arg_type}))
        else
            push!(key_args, arg_name)
            push!(key_arg_types, arg_type)
        end
        return combinearg(arg_name, arg_type, slurp, default)
    end
    args = def[:args] = map(tag_arg, def[:args])
    kwargs = def[:kwargs] = map(tag_arg, def[:kwargs])

    # Get argument types for function signature
    arg_sigs = Vector{Any}(map(def[:args]) do arg
        arg_name, arg_type, slurp, default = splitarg(arg)
        if slurp
            return :(Vararg{$arg_type})
        else
            return arg_type
        end
    end)

    # Set up identity arguments to pass to unmemoized function
    pass_args = Vector{Any}(map(args) do arg
        arg_name, arg_type, slurp, default = splitarg(arg)
        if slurp || namify(arg_type) === :Vararg
            Expr(:..., arg_name)
        else
            arg_name
        end
    end)
    pass_arg_types = copy(arg_sigs)
    pass_kwargs = Vector{Any}(map(kwargs) do kwarg
        kwarg_name, kwarg_type, slurp, default = splitarg(kwarg)
        if slurp
            Expr(:..., kwarg_name)
        else
            Expr(:kw, kwarg_name, kwarg_name)
        end
    end)

    @gensym inner
    inner_def = deepcopy(def)
    inner_def[:name] = inner
    pop!(inner_def, :params, nothing)

    @gensym result

    # If this is a method of a callable object, the definition returns nothing.
    # Thus, we must construct the type of the method on our own.
    if haskey(def, :name)
        if haskey(def, :params)
            cstr_type = :($(def[:name]){$(def[:params]...)})
            sig = :(Tuple{$cstr_type, $(arg_sigs...)} where {$(def[:whereparams]...)})
            pushfirst!(inner_def[:args], gensym())
            pushfirst!(pass_args, cstr_type)
            pushfirst!(pass_arg_types, :(Type{cstr_type}))
            pushfirst!(key_args, cstr_type)
            pushfirst!(key_arg_types, :(Type{cstr_type}))
        elseif @capture(def[:name], obj_::obj_type_ | ::obj_type_)
            obj_type === nothing && (obj_type = Any)
            if obj === nothing
                obj = gensym()
                pushfirst!(key_args, obj_type)
                pushfirst!(key_arg_types, :(Type{$obj_type}))
            else
                pushfirst!(key_args, obj)
                pushfirst!(key_arg_types, obj_type)
            end
            def[:name] = :($obj::$obj_type)
            sig = :(Tuple{$obj_type, $(arg_sigs...)} where {$(def[:whereparams]...)})
            pushfirst!(inner_def[:args], :($obj::$obj_type))
            pushfirst!(pass_args, obj)
            pushfirst!(pass_arg_types, obj_type)
        else
            sig = :(Tuple{typeof($(def[:name])), $(arg_sigs...)} where {$(def[:whereparams]...)})
        end
    else
        sig = :(Tuple{typeof($result), $(arg_sigs...)} where {$(def[:whereparams]...)})
    end

    @gensym cache

    def[:body] = quote
        $(combinedef(inner_def))
        get!($cache, ($(key_args...),)) do
            $inner($(pass_args...); $(pass_kwargs...))
        end
    end

    # A return type declaration of Any is a No-op because everything is <: Any
    return_type = get(def, :rtype, Any)

    if length(kwargs) == 0
        def[:body] = quote
            $(def[:body])::Core.Compiler.return_type($inner, typeof(($(pass_args...),)))
        end
    end

    @gensym world
    @gensym old_meth
    @gensym meth

    res = esc(quote
        # The `local` qualifier will make this performant even in the global scope.
        local $cache = $cache_constructor

        $world = Base.get_world_counter()

        $result = Base.@__doc__($(combinedef(def)))
        
        # If overwriting a method, empty the old cache.
        $old_meth = $_which($sig, $world)
        if $old_meth !== nothing
            empty!(pop!($_memories, $old_meth, []))
        end

        # Store the cache so that it can be emptied later
        $meth = $_which($sig)
        @assert $meth !== nothing
        $_memories[$meth] = $cache
        $result
    end)
    #println(res)
    res
end

function_memories(f) = _function_memories(methods(f))
function_memories(f, types) = _function_memories(methods(f, types))
function_memories(f, types, mod) = _function_memories(methods(f, types, mod))

function _function_memories(ms)
    memories = []
    for m in ms
        memory = method_memory(m)
        if memory !== nothing
            push!(memories, memory)
        end
    end
    return memories
end

function method_memory(m::Method)
    return get(_memories, m, nothing)
end

end