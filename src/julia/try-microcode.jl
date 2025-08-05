module TryMicrocode
using Plots

include("signals.jl")
include("microcode.jl")

signal_dict = SignalDict()


detune_sign = 1

code = Dict[]
# Detune
alu_op!(code, REG_ACC, REG_PHASE, SRC_DETUNE_COUNTER; src2_sign = detune_sign, lshift = LSHIFT_DETUNE) 						# (phase, detune_counter)
# Triangle
alu_op!(code, REG_ACC, SRC_0,     REG_ACC; neg_src2_sel = NS2_TRIANGLE, lshift = LSHIFT_1, notneg = true, part_we = true) 	# (0, acc); either order
# Triangle offset. Separate step for now. TODO: combine with triangle
alu_op!(code, REG_ACC, SRC_TRI_OFFSET, REG_ACC; clamp_result = true) 														# (tri_offset, acc); either order
# Slope
alu_op!(code, REG_ACC, SRC_0,     REG_ACC; clamp_result = true, lshift = LSHIFT_SLOPE) 										# (0, acc)

## Fine slope
##alu_op!(code, NO_DEST, REG_ACC,  SRC_SLOPE_OFFSET; neg_src2_sel = NS2_INV_SIGN_ACC) # compare
##alu_op!(code, REG_ACC, REG_ACC,  SRC_SLOPE_OFFSET; neg_src2_sel = NS2_SIGN_ACC, clamp_result = true) # x + offset
##alu_op!(code, REG_ACC, REG_ACC,  REG_ACC; clamp_result = true) # 2x

# Slope + Fine slope
#alu_op!(code, NO_DEST, SRC_SLOPE_OFFSET, REG_ACC; lshift = LSHIFT_SLOPE, neg_src1_sel = NS2_INV_SIGN_ACC) # compare 		# (slope_offset, acc)
#alu_op!(code, NO_DEST, SRC_SLOPE_OFFSET, REG_ACC; lshift = LSHIFT_SLOPE, neg_src1_sel = NS2_SIGN_ACC) # (x<<n) + offset	# (slope_offset, acc)
#alu_op!(code, NO_DEST, REG_ACC,          REG_ACC; lshift = LSHIFT_SLOPE_PLUS1) # (x<<(n+1)) 								# (0, acc)

# Volume clamp
#alu_op!(code, REG_DEST, SRC_AMP, REG_ACC; neg_src1_sel = ..., neg_src2_sel = ..., vol_clamp = true, ...) # compare 		# (amp, acc); either order



cg = graph_from_AST(alu_model_source, signal_dict)
graphs = rewrite_graphs(cg, code::Vector{<:Dict})

states = StateVector(cg.states)


#add_show = true
add_show = false

ast = export!(ASTExport(add_show), states, graphs, :alu_func!)
@show ast
eval(ast)


state = new_state(states)
alu_bits = 12
max_result = (1 << (alu_bits -1)) - 1
set_state!(states, state, :max_result, max_result)
#set_state!(states, state, :alu_bits, alu_bits)

set_state!(states, state, :detune_counter, 1 << (alu_bits - 2))
set_state!(states, state, :detune_exp, 0)
set_state!(states, state, :tri_offset, (-1 << (alu_bits - 1)) + (1 << (alu_bits - 3)))

set_state!(states, state, :slope_exp0, 1)
set_state!(states, state, :slope_exp1, 2)

accs = Int[]
parts = Int[]
for i = 0:2^alu_bits-1
	set_state!(states, state, :reg_phase, i)
	alu_func!(state)
	push!(accs, get_state(states, state, :reg_acc))
	push!(parts, get_state(states, state, :reg_part))
end


display(plot(accs)); display(plot!(parts .<< (alu_bits-1)))

end
