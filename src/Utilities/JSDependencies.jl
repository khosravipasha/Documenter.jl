module JSDependencies
using JSON

struct RemoteLibrary
    name :: String
    url :: String
    # The following become part of the shim
    deps :: Vector{String}
    exports :: Union{Nothing, String}
    function RemoteLibrary(name, url; deps=String[], exports=nothing)
        new(name, url, deps, exports)
    end
end

function shimdict(lib::RemoteLibrary)
    isempty(lib.deps) && (lib.exports === nothing) && return nothing
    shim = Dict{Symbol,Any}()
    if !isempty(lib.deps)
        shim[:deps] = lib.deps
    end
    if lib.exports !== nothing
        shim[:exports] = lib.exports
    end
    return shim
end

struct Snippet
    deps :: Vector{String}
    args :: Vector{String}
    js :: String
end

macro js_str(s)
    return s
end

struct RequireJS
    libraries :: Dict{String, RemoteLibrary}
    snippets :: Vector{Snippet}

    function RequireJS(libraries::AbstractVector{RemoteLibrary}, snippets::AbstractVector{Snippet} = Snippet[])
        r = new(Dict(), [])
        for library in libraries
            push!(r, library)
        end
        for snippet in snippets
            push!(r, snippet)
        end
        return r
    end
end

function shimdict(r::RequireJS)
    shim = Dict{String,Any}()
    for (name, lib) in r.libraries
        @assert name == lib.name
        libshim = shimdict(lib)
        if libshim !== nothing
            shim[name] = libshim
        end
    end
    return shim
end

function Base.push!(r::RequireJS, lib::RemoteLibrary)
    if lib.name in keys(r.libraries)
        error("Library already added.")
    end
    r.libraries[lib.name] = lib
end

Base.push!(r::RequireJS, s::Snippet) = push!(r.snippets, s)

function verify(r::RequireJS)
    isvalid = true
    for s in r.snippets
        for dep in s.deps
            if !(dep in keys(r.libraries))
                @error("$(dep) missing from libraries")
                isvalid = false
            end
        end
    end
    return isvalid
end

function writejs(filename::AbstractString, r::RequireJS)
    open(filename, "w") do io
        writejs(io, r)
    end
end

function writejs(io::IO, r::RequireJS)
    write(io, """
    // Generated by Documenter.jl
    requirejs.config({
      paths: {
    """)
    for (name, lib) in r.libraries
        url = endswith(lib.url, ".js") ? replace(lib.url, r"\.js$" => "") : lib.url
        write(io, """
            '$(lib.name)': '$(url)',
        """) # FIXME: escape bad characters
    end
    write(io, """
      },
    """)

    shim = shimdict(r)
    if !isempty(shim)
        write(io, "  shim: ")
        JSON.print(io, shim, 2) # FIXME: escape JS properly
        write(io, ",\n")
    end


    write(io, """
    });
    """)

    for s in r.snippets
        args = join(s.args, ", ") # FIXME: escapes
        deps = join(("\'$(d)\'" for d in s.deps), ", ") # FIXME: escapes
        write(io, """
        $("/"^80)
        require([$(deps)], function($(args)) {
        $(s.js)
        })
        """)
    end
end

"""
    parse_snippet(filename::AbstractString) -> Snippet
    parse_snippet(io::IO) -> Snippet

Parses a JS snippet file into a [`Snippet`](@ref) object.
"""
function parse_snippet end

parse_snippet(filename::AbstractString; kwargs...) = open(filename, "r") do io
    parse_snippet(io; kwargs...)
end

function parse_snippet(io::IO)
    libraries = String[]
    arguments = String[]
    lineno = 1
    while true
        pos = position(io)
        line = readline(io)
        m = match(r"^//\s*([a-z]+):(.*)$", line)
        if m === nothing
            seek(io, pos) # undo the last readline() call
            break
        end
        if m[1] == "libraries"
            libraries = strip.(split(m[2], ","))
            if any(s -> match(r"^[a-z-_]+$", s) === nothing, libraries)
                error("Unable to parse a library declaration '$(line)' on line $(lineno)")
            end
        elseif m[1] == "arguments"
            arguments = strip.(split(m[2], ","))
        end
        lineno += 1
    end
    snippet = String(read(io))
    Snippet(libraries, arguments, snippet)
end

# struct SnippetParseError
#     key :: String
#     line :: String
#     lineno :: Integer
# end
#
# function Base.showerror(io::IO, err::SnippetParseError)
#     println(io, "SnippetParseError: bad '$(err.key)' declaration on line $(err.lineno)")
#     println(io, "  attempted to parse: '$(err.line)'")
# end

end