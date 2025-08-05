using Base.Meta: isexpr


show_hex(x) = show(x)
show_hex(x::Integer) = show(UInt32(x & 0xffffffff))

macro show_hex(ex)
	return quote
		print($(string(ex, " = ")))
		show_hex($(esc(ex)))
		println()
	end
end



# Base framework
# ==============

abstract type Signal end

abstract type NamedProps end
struct RegisterProps <: NamedProps end
struct WireProps <: NamedProps end

# Mutable to get unique identity
mutable struct NamedSignal{P<:NamedProps} <: Signal
	name::String
	props::P
end

const Register = NamedSignal{RegisterProps}
const Wire     = NamedSignal{WireProps}

register(name) = Register(string(name), RegisterProps())
wire(name) = Wire(string(name), WireProps())
input(name) = wire(name)


# Supply a SignalDict to AST parsing to reuse previously defined NamedSignals created through @reg, @input, or wire assignment.
# Needed to make C++ export work when multiply sources use the same names, makes them refer to the same signal.
const SignalDict = Dict{Symbol,NamedSignal}

function register!(d::SignalDict, name::Symbol)
	if haskey(d, name); return d[name]::Register
	else                return d[name] = register(name)
	end
end

function wire!(d::SignalDict, name::Symbol)
	if haskey(d, name); return d[name]::Wire
	else                return d[name] = wire(name)
	end
end

input!(d::SignalDict, name::Symbol) = wire!(d, name)



code_signaldef(func, name::Symbol) = :($(esc(name)) = $(QuoteNode(func))($(QuoteNode(name))))
code_signaldef(func, names::Tuple{Symbol, Vararg{Symbol}}) = [code_signaldef(func, name) for name in names]
code_signaldef2(func, names::Tuple{Symbol, Vararg{Symbol}}) = (defs = code_signaldef(func, names); quote $(defs...); end)

#=
macro register(args...) code_signaldef2(register, args) end
macro wire(args...)     code_signaldef2(wire, args) end
macro input(args...)    code_signaldef2(input, args) end
=#
#=
macro register(args...)
	#code = [:($(esc(name)) = $(QuoteNode(register))($(QuoteNode(name)))) for name::Symbol in args]
	code = code_signaldef(register, args)
	ex = quote
		$(code...)
	end

	@show ex
	Base.Meta.show_sexpr(ex)
	println()

	#nothing
	ex
end
=#


sym_name_of(signal::NamedSignal, dest=false) = Symbol(signal.name)
sym_name_of(signal::Register, dest=false) = dest ? Symbol("_next_", signal.name) : Symbol(signal.name)


struct Constant <: Signal
	value::Int
end

#Base.promote_rule(::Type{<:Signal}, ::Type{Int}) = Signal
signal(x::Signal)  = x
signal(x::Integer) = Constant(x)

struct Binding
	value::Signal
	line::LineNumberNode
end

struct Graph
	order::Vector{NamedSignal}
	# Bindings to registers take effect at the end of the cycle, all at once (Bindings to next(reg) are represented as bindings to reg)
	bindings::Dict{NamedSignal, Binding}

	Graph() = new(NamedSignal[], Dict{NamedSignal, Binding}())
end

struct Next
	reg::Register
end
next(reg::Register) = Next(reg)

const no_line = LineNumberNode(-1)

bind!(g::Graph, to::Wire, value::Signal, line::LineNumberNode = no_line) = _bind!(g, to, value, line)
bind!(g::Graph, to::Register, value::Signal, line::LineNumberNode = no_line) = error("Tried to bind the value of register ", sym_name_of(to), ". Did you mean next(", sym_name_of(to), ")?")
bind!(g::Graph, to::Next, value::Signal, line::LineNumberNode = no_line) = _bind!(g, to.reg, value, line)

function _bind!(g::Graph, to::NamedSignal, value::Signal, line::LineNumberNode)
	haskey(g.bindings, to) && error("Graph already has a binding for ", to)
	push!(g.order, to)
	g.bindings[to] = Binding(value, line)
	to
end


struct Rewrite
	mcode::Dict
	required::Set{NamedSignal}

	Rewrite(mcode, required=Set{NamedSignal}()) = new(mcode, Set{NamedSignal}(required)) # copy required and make sure it's a set of the right type
end

function rewrite(c::Rewrite, g_in::Graph)
#=
	g = Graph()
	for to in g_in.order
		_bind!(g, to, rewrite(c, g_in.bindings[to]))
	end
=#
	# Go through the bindings in reverse to find the ones that are needed to produce the required outputs (and mark further needed signals in c.required).
	# Next values of registers are always considered as required.
	bindings = Tuple{NamedSignal,Binding}[]
	for to in reverse(g_in.order)
		to isa Register || to in c.required || continue
		b = g_in.bindings[to]
		from = rewrite(c, b.value)
		from != to && push!(bindings, (to, Binding(from, b.line)))
	end
	g = Graph()
	for (to, b) in reverse(bindings)
		_bind!(g, to, b.value, b.line)
	end
	return g
end

rewrite(c::Rewrite, signal::Signal) = signal

function rewrite(c::Rewrite, signal::NamedSignal)
	push!(c.required, signal)
	return signal
end


abstract type OpFunc end
struct Func{T} <: OpFunc; end
func_of(::Func{T}) where T = T::Symbol

# Ops are pure functions of their arguments. Two operations with the same op and same arguments are equal.
struct Op{T<:OpFunc} <: Signal
	func::OpFunc
	args::Tuple{Vararg{Signal}}
end

Op(mathop::Symbol, args...) = (MathOp = Func{mathop}; Op{MathOp}(MathOp(), signal.(args)))

func_of(op::Op) = func_of(op.func)

function rewrite(c::Rewrite, op::Op)
	if func_of(op) == :select
		@assert length(op.args) == 3
		arg1 = rewrite(c, op.args[1])
		if arg1 isa Constant  # Simplify constant selects
			sel = arg1.value
			@assert 0 <= sel <= 1
			sel == 1 && return rewrite(c, op.args[2])
			return rewrite(c, op.args[3])
		end
	end
	args = rewrite.((c,), op.args)
	return Op{typeof(op.func)}(op.func, args)
end


# Mux controlled by a microcode control signal
struct ControlMux <: OpFunc
	control::Symbol
	cases::Tuple  # need as many case values as there are arguments to the mux
end

function mux(control::Symbol, pairs)
	cases = Tuple([p[1] for p in pairs])
	args  = Tuple([signal(p[2]) for p in pairs])
	mux = ControlMux(control, cases)
	return Op{ControlMux}(mux, args)
end

# Rewrite control muxes into static bindings based on their control signal
function rewrite(c::Rewrite, mux_op::Op{ControlMux})
	mux = mux_op.func::ControlMux

	#!haskey(c.mcode, mux.control) && return signal(0)  # TODO: Should we allow this?

	control = c.mcode[mux.control]

	index = 0
	for (i, key) in enumerate(mux.cases)
		if control == key
			index = i
			break
		end
	end
	index <= 0 && error("Case ", control, " not found")

	return rewrite(c, mux_op.args[index])
end


struct ControlSource <: OpFunc
	control::Symbol
end

source(control::Symbol) = Op{ControlSource}(ControlSource(control), ())

rewrite(c::Rewrite, op::Op{ControlSource}) = signal(c.mcode[op.func.control])



struct StateVector
	states::Vector{NamedSignal}
	state_set::Set{NamedSignal}
	state_inds::Dict{NamedSignal, Int}
	state_dict::Dict{Symbol, NamedSignal}

	StateVector(states::Vector{NamedSignal}) = new(states, Set(states), Dict([state => i for (i, state) in enumerate(states)]), Dict([sym_name_of(state) => state for state in states]))
end

new_state(states::StateVector) = zeros(Int, length(states.states))
get_state(states::StateVector, state::Vector, signal::NamedSignal) = state[states.state_inds[signal]]
get_state(states::StateVector, state::Vector, signal::Symbol) = get_state(states, state, states.state_dict[signal])
set_state!(states::StateVector, state::Vector, signal::NamedSignal, value) = (state[states.state_inds[signal]] = value)
set_state!(states::StateVector, state::Vector, signal::Symbol, value) = set_state!(states, state, states.state_dict[signal], value)


# AST parsing
# ===========
mutable struct ParseContext
	g::Graph
	symbols::Dict{Symbol, NamedSignal}
	curr_line::LineNumberNode
	states::Vector{NamedSignal}
	signal_dict::SignalDict

	ParseContext(signal_dict::SignalDict = SignalDict()) = new(Graph(), Dict{Symbol, NamedSignal}(), LineNumberNode(-1, :no_file), NamedSignal[], signal_dict)
end

function bind!(c::ParseContext, name::Symbol, value::NamedSignal)
	haskey(c.symbols, name) && error("Name ", name, " already defined")
	c.symbols[name] = value
	return value
end

function graph_from_AST(top_ex::Expr, signal_dict::SignalDict = SignalDict())
	c = ParseContext(signal_dict)
	@assert top_ex.head == :block
	for ex in top_ex.args
		graph_from_AST!(c, ex)
	end

	return c
end

graph_from_AST!(c::ParseContext, ex::LineNumberNode) = (c.curr_line = ex)

const def_register_sym =  Symbol("@reg")
const def_input_sym =  Symbol("@input")

function graph_from_AST!(c::ParseContext, ex::Expr)
	head, args, nargs = ex.head, ex.args, length(ex.args)

	if head == :macrocall
		c.curr_line = args[2]::LineNumberNode
		if args[1] == def_register_sym
			for name in args[3:end]
				name::Symbol
				signal = bind!(c, name, register!(c.signal_dict, name))
				push!(c.states, signal)
			end
		elseif args[1] == def_input_sym
			for name in args[3:end]
				name::Symbol
				signal = bind!(c, name, input!(c.signal_dict, name))
				push!(c.states, signal)
			end
		else
			error("Don't know how to interpret ", ex)
		end
	elseif head == :(=) && nargs == 2
		dest_name = args[1]
		if dest_name isa Symbol
			dest = bind!(c, dest_name, wire!(c.signal_dict, dest_name))
		elseif isexpr(dest_name, :call, 2) && dest_name.args[1] == :next
			reg_name = dest_name.args[2]::Symbol
			reg = signal_from_AST(c, reg_name)::Register
			dest = next(reg)
		else
			error("Don't know how to interpret destination ", dest_name)
		end
		src = signal_from_AST(c, args[2])
		bind!(c.g, dest, src, c.curr_line)
	else
		error("Don't know how to interpret ", ex)
	end
end

signal_from_AST(c::ParseContext, x::Integer) = signal(x)

function signal_from_AST(c::ParseContext, name::Symbol)
	haskey(c.symbols, name) || error("Symbol ", name, " not defined, ", c.curr_line)
	return c.symbols[name]
end

function signal_from_AST(c::ParseContext, q::QuoteNode)
	sym = q.value::Symbol
	return source(sym)
end

function signal_from_AST(c::ParseContext, ex::Expr)
	head, args, nargs = ex.head, ex.args, length(ex.args)

	if head == :call
		fname = args[1]::Symbol

		if fname == :mux
			@assert nargs == 3
			control = (args[2]::QuoteNode).value::Symbol
			pairs = args[3]::Vector{<:Pair}
			return mux(c, control, pairs)
		else
			fargs = Signal[]
			for farg in args[2:end]
				push!(fargs, signal_from_AST(c, farg))
			end
			return Op(fname, fargs...)
		end
	elseif isexpr(ex, :block)
		# Unwrap a begin block if it contains just one argument that is not a line number node
		ex2 = nothing
		found = false
		for arg in ex.args
			arg isa LineNumberNode && continue
			if ex2 === nothing
				ex2 = arg
				found = true
			else
				error("Don't know how to interpret ", ex)
			end
			found || error("Don't know how to interpret ", ex)
			return signal_from_AST(c, ex2)
		end
	elseif isexpr(ex, :&&, 2); return Op(:&&, signal_from_AST.((c,), args)...) # Represent && and || as function calls in the graph -- everything is pure anyway
	elseif isexpr(ex, :||, 2); return Op(:||, signal_from_AST.((c,), args)...)
	elseif isexpr(ex, :if, 3); return Op(:select, signal_from_AST.((c,), args)...) # ternary operator ? :
	else
		error("Don't know how to interpret ", ex)
	end
end

function mux(c::ParseContext, control::Symbol, pairs)
	cases = Tuple([p[1] for p in pairs])
	args  = Tuple([signal_from_AST(c, p[2]) for p in pairs])
	mux = ControlMux(control, cases)
	return Op{ControlMux}(mux, args)
end


function cat_expr_blocks(blocks::Expr...)
	code = []
	for block in blocks
		@assert isexpr(block, :block)
		append!(code, block.args)
	end
	Expr(:block, code...)
end


# Export
# ======

abstract type Export end

# Julia AST export
# ----------------

struct ASTExport <: Export
	add_show::Bool

	ASTExport(add_show::Bool = false) = new(add_show)
end

const state_vector_sym = gensym("state")

function export!(c::ASTExport, states::StateVector, graphs::Vector{Graph}, func_name = "e_func")
	func_name = Symbol(func_name)
	code = []
	for (i, state) in enumerate(states.states)
		name = sym_name_of(state)
		push!(code, :($name = ($state_vector_sym)[$i]))
	end
	for (i, g) in enumerate(graphs)
		c.add_show && push!(code, :(println($(string("\n#", i-1)))))
		push!(code, export!(c, g))
	end
	for (i, state) in enumerate(states.states)
		name = sym_name_of(state)
		push!(code, :(($state_vector_sym)[$i] = $name))
	end

	#return Expr(:block, code...)
	return :(function $func_name($state_vector_sym::Vector{Int})
		$(code...)
		return $nothing
	end)
end

function export!(c::ASTExport, g::Graph)
	code = []
	# Emit computations
	for dest in g.order
		name = sym_name_of(dest, true)
		b = g.bindings[dest]
		push!(code, b.line)
		value = export!(c, b.value)
		ex = :($name = $value)
		#if c.add_show; push!(code, :(@show($ex)))
		if c.add_show; push!(code, :(@show_hex($ex)))
		else           push!(code, ex)
		end
	end
	# Emit `reg = next_reg` for each register
	for dest in g.order
		dest isa Register || continue
		name = sym_name_of(dest)
		next_name = sym_name_of(dest, true)
		push!(code, :($name = $next_name))
	end

	return Expr(:block, code...)
end

function export!(c::ASTExport, op::Op{<:Func})
	args = [export!(c, arg) for arg in op.args]
	nargs = length(args)
	func = func_of(op)
	if     func == :&&; return Expr(:&&, [:(Bool($arg)) for arg in args]...)
	elseif func == :||; return Expr(:||, [:(Bool($arg)) for arg in args]...)
	elseif func == :! && nargs == 1; return Expr(:call, func, :(Bool($(args[1]))))
	else                return Expr(:call, func, args...)
	end
end

export!(c::ASTExport, signal::NamedSignal) = sym_name_of(signal)
export!(c::ASTExport, signal::Constant) = signal.value


# C++/Python export
# -----------------
struct TextExport{L} <: Export
	io::IOBuffer
	TextExport{L}() where L = new{L}(IOBuffer())
end

lang_of(c::TextExport{L}) where L = L
take_string!(c::TextExport) = String(take!(c.io))

const CppExport = TextExport{:cpp}
const PythonExport = TextExport{:python}

get_line_comment_marker(::CppExport) = "//"
get_line_comment_marker(::PythonExport) = "#"

const cpp_unary_ops = Set([:+, :-, :~])
const cpp_binary_ops = Set([:+, :-, :*, :(<<), :(>>), :(==), :(!=), :>, :<, :(>=), :(<=), :&, :|, :xor, :&&, :||])
const python_op_replacements = Dict([:! => :not, :&& => :and, :|| => :or])

function export!(c::CppExport, states::StateVector, struct_name = "State")
	println(c.io, "struct $struct_name {")
	for signal in states.states
		println(c.io, "\tint ", sym_name_of(signal), ";")
	end
	println(c.io, "};")
end

function export!(c::PythonExport, states::StateVector, struct_name = "State")
	println(c.io, "class $struct_name:")
	println(c.io, "\tdef __init__(self):")
	for signal in states.states
		println(c.io, "\t\tself.", sym_name_of(signal), " = 0")
	end
end

function export!(c::TextExport, states::StateVector, graphs::Vector{Graph}, struct_name::String, func_name::String = "e_func")
	lang = lang_of(c)

	if lang == :cpp; println(c.io, "void $func_name($struct_name &_states) {")
	elseif lang == :python; println(c.io, "def $func_name(_states):")
	else error("Unsupported language: ", lang)
	end

	for (i, state) in enumerate(states.states)
		name = sym_name_of(state)
		print(c.io, "\t")
		lang_of(c) == :cpp && print(c.io, "int ")
		println(c.io, "$name = _states.$name;")
	end
	println(c.io)
	if lang_of(c) == :cpp
		# Declare variables for the wires
		declared = Set{NamedSignal}()
		for g in graphs
			for signal in g.order
				signal isa Wire || signal isa Register || continue
				signal in declared && continue
				name = sym_name_of(signal, true)
				println(c.io, "\tint $name;")
				push!(declared, signal)
			end
		end
		println(c.io)
	end
	for (i, g) in enumerate(graphs)
		println(c.io, "\t", get_line_comment_marker(c), " ", i-1)
		export!(c, g)
		println(c.io)
	end
	for (i, state) in enumerate(states.states)
		name = sym_name_of(state)
		println(c.io, "\t_states.$name = $name;")
	end

	if lang == :cpp; println(c.io, "}")
	elseif lang == :python
	else error("Unsupported language: ", lang)
	end
end

function export!(c::TextExport, g::Graph)
	# Emit computations
	for dest in g.order
		name = sym_name_of(dest, true)
		print(c.io, "\t", name, " = ");
		export!(c, g.bindings[dest].value)
		println(c.io, ";")
	end
	# Emit `reg = next_reg` for each register
	for dest in g.order
		dest isa Register || continue
		name = sym_name_of(dest)
		next_name = sym_name_of(dest, true)
		println(c.io, "\t", name, " = ", next_name, ";")
	end
	return c
end

function export!(c::TextExport, op::Op{<:Func})
	func = func_of(op)
	args = op.args
	nargs = length(args)

	force_op = false
	if lang_of(c) == :python
		if haskey(python_op_replacements, func)
			func = python_op_replacements[func]
			force_op = true
		end
	end

	if nargs == 1 && (force_op || func in cpp_unary_ops)
		print(c.io, "(", func)
		func == :not && print(c.io, " ")
		export!(c, args[1])
		print(c.io, ")")
	elseif nargs == 2 && (force_op || func in cpp_binary_ops)
		func == :xor && (func = :^)
		print(c.io, "(")
		export!(c, args[1])
		print(c.io, " ", func, " ")
		export!(c, args[2])
		print(c.io, ")")
	elseif nargs >= 3 && (force_op || func in cpp_binary_ops)
		# Convert e g Julia -(x,y,z) to (x-y)-z
		export!(c, Op(func, Op(func, args[1], args[2]), args[3:end]...))
	elseif nargs == 3 && func == :select
		print(c.io, "(")
		if lang_of(c) == :cpp
			export!(c, args[1])
			print(c.io, " ? ")
			export!(c, args[2])
			print(c.io, " : ")
			export!(c, args[3])
		elseif lang_of(c) == :python
			export!(c, args[2])
			print(c.io, " if ")
			export!(c, args[1])
			print(c.io, " else ")
			export!(c, args[3])
		else
			error("select unimplemented for lang = ", lang_of(c))
		end
		print(c.io, ")")
	else
		#error("Don't know how to export func=$func, nargs=$nargs")
		print(c.io, func, "(")
		for (i, arg) in enumerate(args)
			export!(c, arg)
			i != nargs && print(c.io, ", ")
		end
		print(c.io, ")")
	end
end

export!(c::TextExport, signal::NamedSignal) = print(c.io, sym_name_of(signal))
export!(c::TextExport, signal::Constant) = print(c.io, signal.value)

#=
# Operator / function overloading for Signal
# ==========================================

# TODO: Make sure that these operations work the same in all export cases
for op in [:+, :-, :*, :(<<), :(>>), :(==), :(!=), :>, :<, :(>=), :(<=), :&, :|, :xor]
	@eval begin
		Base.$op(x::Signal, y::Signal) = Op($(QuoteNode(op)), x, y)
		Base.$op(x::Signal, y::Integer) = Op($(QuoteNode(op)), x, y)
		Base.$op(x::Integer, y::Signal) = Op($(QuoteNode(op)), x, y)
	end
end

# workaround since we have overloaded x == y
isequal(x::Signal, y::Signal) = (x === y) 
isequal(x::Signal, y) = false
isequal(x, y::Signal) = false

for op in [:-, :~]
	@eval begin
		Base.$op(x::Signal) = Op($(QuoteNode(op)), x)
	end
end
=#

postpone(func::Symbol, args...) = Op(func, args...)

Base.bitreverse(x::Int, n::Int) = Int(bitreverse(UInt32(x&(2^32-1))) >> (32 - n))


function select(cond::Union{Int, Bool}, x, y)
	cond&~1 == 0 || error("select: cond = ", cond)
	return cond != 0 ? x : y
end
select(cond::Signal, x, y) = Op(:select, cond, x, y)
select(cond::Symbol, x, y) = mux(cond, [1 => signal(x), 0 => signal(y)])
