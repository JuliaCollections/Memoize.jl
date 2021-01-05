module Memoize
using MacroTools: isexpr, combinearg, combinedef, namify, splitarg, splitdef, @capture
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

"""
    @memoize [cache] declaration
    
    Transform any method declaration `declaration` (except for inner constructors) so that calls to the original method are cached by their arguments. When an argument is unnamed, its type is treated as an argument instead.
    
    `cache` should be an expression which evaluates to a dictionary-like type that supports `get!` and `empty!`, and may depend on the local variables `__Key__` and `__Value__`, which evaluate to syntactically-determined bounds on the required key and value types the cache must support.

    If the given cache contains values, it is assumed that they will agree with the values the method returns. Specializing a method will not empty the cache, but overwriting a method will. The caches corresponding to methods can be determined with `memory` or `memories.`
"""
macro memoize(args...)
    if length(args) == 1
        cache_constructor = :(IdDict{__Key__}{__Value__}())
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
    
    function split(arg, iskwarg=false)
        arg_name, arg_type, slurp, default = splitarg(arg)
        trait = arg_name === nothing
        trait && (arg_name = gensym())
        vararg = namify(arg_type) === :Vararg
        return (
            arg_name = arg_name,
            arg_type = arg_type,
            arg_value = arg_name,
            slurp = slurp,
            vararg = vararg,
            default = default,
            trait = trait,
            iskwarg = iskwarg)
    end

    combine(arg) = combinearg(arg.arg_name, arg.arg_type, arg.slurp, arg.default)

    pass(arg) =
        (arg.slurp || arg.vararg) ? Expr(:..., arg.arg_name) :
            arg.iskwarg ? Expr(:kw, arg.arg_name, arg.arg_name) : arg.arg_name

    dispatch(arg) = arg.slurp ? :(Vararg{$(arg.arg_type)}) : arg.arg_type

    args = split.(def[:args])
    kwargs = split.(def[:kwargs], true)
    def[:args] = combine.(args)
    def[:kwargs] = combine.(kwargs)
    @gensym inner
    inner_def = deepcopy(def)
    inner_def[:name] = inner
    inner_args = copy(args)
    inner_kwargs = copy(kwargs)
    pop!(inner_def, :params, nothing)

    @gensym result

    # If this is a method of a callable type or object, the definition returns nothing.
    # Thus, we must construct the type of the method on our own.
    # We also need to pass the object to the inner function
    if haskey(def, :name)
        if haskey(def, :params) # Callable type
            typ = :($(def[:name]){$(pop!(def, :params)...)})
            inner_args = [split(:(::Type{$typ})), inner_args...]
            def[:name] = combine(inner_args[1])
            head = :(Type{$typ})
        elseif @capture(def[:name], obj_::obj_type_ | ::obj_type_) # Callable object
            inner_args = [split(def[:name]), inner_args...]
            def[:name] = combine(inner_args[1])
            head = obj_type
        else # Normal call
            head = :(typeof($(def[:name])))
        end
    else # Anonymous function
        head = :(typeof($result))
    end
    inner_def[:args] = combine.(inner_args)

    # Set up arguments for memo key
    key_names = map([inner_args; inner_kwargs]) do arg
        arg.trait ? arg.arg_type : arg.arg_name
    end
    key_types = map([inner_args; inner_kwargs]) do arg
        arg.trait ? DataType :
        arg.vararg ? :(Tuple{$(arg.arg_type)}) :
            arg.arg_type
    end

    @gensym cache

    pass_args = pass.(inner_args)
    pass_kwargs = pass.(inner_kwargs)
    def[:body] = quote
        $(combinedef(inner_def))
        get!($cache, ($(key_names...),)) do
            $inner($(pass_args...); $(pass_kwargs...))
        end
    end

    # A return type declaration of Any is a No-op because everything is <: Any
    return_type = get(def, :rtype, Any)

    if length(kwargs) == 0
        def[:body] = quote
            $(def[:body])::Core.Compiler.widenconst(Core.Compiler.return_type($inner, typeof(($(pass_args...),))))
        end
    end

    @gensym world
    @gensym old_meth
    @gensym meth
    @gensym brain

    sig = :(Tuple{$head, $(dispatch.(args)...)} where {$(def[:whereparams]...)})

    return esc(quote
        # The `local` qualifier will make this performant even in the global scope.
        local $cache = begin
            local __Key__ = (Tuple{$(key_types...)} where {$(def[:whereparams]...)})
            local __Value__ = ($return_type where {$(def[:whereparams]...)})
            $cache_constructor
        end

        local $world = Base.get_world_counter()

        local $result = Base.@__doc__($(combinedef(def)))

        local $brain = if isdefined($__module__, :__Memoize_brain__)
            brain = getfield($__module__, :__Memoize_brain__)
        else
            global __Memoize_brain__ = Dict()
        end
        
        # If overwriting a method, empty the old cache.
        # Notice that methods are hashed by their stored signature
        local $old_meth = $_which($sig, $world)
        if $old_meth !== nothing && $old_meth.sig == $sig
            empty!(pop!($brain, $old_meth.sig, []))
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
        if isdefined(m.module, :__Memoize_brain__)
            brain = getfield(m.module, :__Memoize_brain__)
            memory = get(brain, m.sig, nothing)
            if memory !== nothing
                push!(memories, memory)
            end
        end
    end
    return memories
end

"""
    memory(m)
    
    Return the memoized cache for the method m, or nothing if no such method exists
"""
function memory(m::Method)
    if isdefined(m.module, :__Memoize_brain__)
        brain = getfield(m.module, :__Memoize_brain__)
        return get(brain, m.sig, nothing)
    end
end

end