module Meta
import JSON
import Polymake: appname_module_dict, module_appname_dict

pm_name_qualified(app_name, func_name) = "$app_name::$func_name"

function pm_name_qualified(app_name, func_name, templates)
    qname = pm_name_qualified(app_name, func_name)
    templs = length(templates) > 0 ? "<$(join(templates, ","))>" : ""
    return qname*templs
end

function get_polymake_app_name(mod::Symbol)
    haskey(module_appname_dict, mod) || throw("Module '$mod' not registered in Polymake.jl.")
    polymake_app = module_appname_dict[mod]
    return polymake_app
end

############### macro helpers

function parse_function_call(expr)
    @assert expr.head == :call
    func = expr.args[1] # called function
    args = expr.args[2:end] # its arguments

    templates = Symbol[]
    # grab template parameters if present
    if func.head == :curly
        templates = func.args[2:end]
        func = func.args[1]
    end

    @assert func.head == Symbol('.')
    module_name = func.args[1]
    func_name = func.args[2].value

    kwargs = Expr[]
    kwar_idx = findfirst(a -> a isa Expr && a.head == :kw, args)
    if kwar_idx != nothing
        kwargs = args[kwar_idx:end]
        args = args[1:kwar_idx-1]
    end

    return module_name, func_name, templates, args, kwargs
end

############### json parsing

########## structs

abstract type PolymakeCallable end

struct PolymakeFunction <: PolymakeCallable
    jl_function::Symbol
    pm_name::String
    app_name::String
    json::Dict{String, Any}

    PolymakeFunction(pm_name::String, app_name::String) =
        new(Symbol(pm_name), pm_name, app_name)
    PolymakeFunction(jl_name::Symbol, pm_name::String, app_name::String) =
        new(jl_name, pm_name, app_name)
    PolymakeFunction(jl_name::Symbol, pm_name::String, app_name::String, json_dict) =
        new(jl_name, pm_name, app_name, json_dict)
end

struct PolymakeMethod <: PolymakeCallable
    jl_function::Symbol
    pm_name::String
    app_name::String
    json::Dict{String, Any}

    PolymakeMethod(pm_name::String) =
        new(Symbol(pm_name), pm_name)
    PolymakeMethod(jl_name::Symbol, pm_name::String) =
        new(jl_name, pm_name)
    PolymakeMethod(jl_name::Symbol, pm_name::String, app_name, json_dict) =
        new(jl_name, pm_name, app_name, json_dict)
end

struct PolymakeApp
    jl_module::Symbol
    pm_name::String
    callables::Vector{PolymakeCallable}
end

########## constructors

function PolymakeCallable(app_name::String, dict::Dict{String, Any},
    polymake_name=dict["name"], julia_name=Symbol(polymake_name))

    if haskey(dict, "method_of")
        return PolymakeMethod(julia_name, polymake_name, app_name, dict)
    else
        return PolymakeFunction(julia_name, polymake_name, app_name, dict)
    end
end

function PolymakeApp(app_json::Dict{String, Any})
    app_name = app_json["app"]
    jl_module = appname_module_dict[Symbol(app_json["app"])]

    for f in app_json["functions"]
        if !haskey(f, "name")
            @warn "No 'name' field in json node. Malformed json for application '$app_name'?\n node = $f"
        end
    end

    callables = [PolymakeCallable(app_name,f) for f in app_json["functions"] if haskey(f, "name")]

    callables = unique(pc -> pm_name(pc), callables)

    return PolymakeApp(jl_module, app_name, callables)
end

function PolymakeApp(module_name::Symbol, json_file::String, module_file::String)
    @assert isfile(json_file)
    app_json = JSON.Parser.parsefile(json_file)
    return PolymakeApp(app_json)
end

########## utils

pm_name(pc::PolymakeCallable) = pc.pm_name
pm_name_qualified(pc::PolymakeCallable) = pm_name_qualified(pc.app_name, pc.pm_name)
jl_module_name(pa::PolymakeApp) = pa.jl_module

push!(pa::PolymakeApp, pc::PolymakeCallable) = push!(pa.callables, pc)

callable(::PolymakeFunction) = :internal_call_function
callable(::PolymakeMethod) = :internal_call_method
callable_void(::PolymakeFunction) = :internal_call_function_void
callable_void(::PolymakeMethod) = :internal_call_method_void

function push!(pa::PolymakeApp, func_json::Dict{String, Any})
    pc = PolymakeCallable(pm_name(pa), func_json)
    push!(pa, pc)
end

function Base.show(io::IO, pc::PolymakeCallable)
    println(io, typeof(pc), ":")
    for name in fieldnames(typeof(pc))
        if isdefined(pc, name)
            c = getfield(pc, name)
            content = "[$(typeof(c))] $c"
        else
            content = "#undef"
        end
        println(io, " • ", name, " → ", content)
    end
end

function Base.show(io::IO, pa::PolymakeApp)
    println(io, "Parsed Polymake Application $(pm_name(pa)) as Polymake.$jl_module_name")
    println(io, "Contains $(length(pa.functions)) functions:")
    println(io, [f.jl_function for f in pa.functions])
end

########## code generation

function jl_code(pf::PolymakeFunction)
    func_name = pm_name_qualified(pf)
    :(
        function $(pf.jl_function)(args...; template_parameters::Array{String,1}=String[], keep_PropertyValue=false, call_as_void=false, kwargs...)
            if call_as_void
                $(callable_void(pf))($func_name, template_parameters,
                    c_arguments(args...; kwargs...))
                return nothing
            else
                return_value = $(callable(pf))($func_name, template_parameters,
                    c_arguments(args...; kwargs...))
                if keep_PropertyValue
                    return return_value
                else
                    return convert_from_property_value(return_value)
                end
            end
        end;
        $(Base.Docs).getdoc(::typeof($(pf.jl_function))) =
            Markdown.parse(join(get_docs($func_name, full=true), "="^76));
        export $(pf.jl_function);
    )
end

function jl_code(pf::PolymakeMethod)
    func_name = pf.pm_name

    :(
        function $(pf.jl_function)(object::pm_perl_Object, args...; keep_PropertyValue=false, call_as_void=false, kwargs...)
            if call_as_void
                $(callable_void(pf))($func_name, object, c_arguments(args...; kwargs...))
                return nothing
            else
                return_value =
                $(callable(pf))($func_name, object, c_arguments(args...; kwargs...))
                if keep_PropertyValue
                    return return_value
                else
                    return convert_from_property_value(return_value)
                end
            end
        end;
        export $(pf.jl_function);
    )
end


module_imports() = :(import Polymake:
    internal_call_function, internal_call_method,
    internal_call_function_void, internal_call_method_void,
    convert_from_property_value, c_arguments, pm_perl_Object, get_docs;
    import Markdown;
    )

function jl_code(pa::PolymakeApp)
    fn_code = jl_code.(pa.callables)
    :(
        module $(jl_module_name(pa))
        $(module_imports())
        $(fn_code...)
        end
    )
end

########## Compat

function compat_statement(app, mod)
    quote
        import ..($mod)
        const $app = $mod
        export $app
    end
end

end # of module Meta
