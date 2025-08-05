
function export_microcode(io::IO, order::Vector, mcode::Dict)
	print(io, "begin")
	num_exported = 0
	for name in order
		if haskey(mcode, name)
			value = mcode[name]
			value = Int(value)
			print(io, "\t", name, " = ", value, ";" )
			num_exported += 1
		end
	end
	num_exported == length(mcode) || error("Names missing from the order vector: ", collect(setdiff(keys(mcode), order)))
	print(io, "\tend")
end

function export_microcode(io::IO, order::Vector, mcodes::Vector{<:Dict})
	for (i1, mcode) in enumerate(mcodes)
		i = i1-1
		print(io, i, ":\t")
		export_microcode(io, order, mcode)
		println(io)
	end
end

@enum RegSrc begin
	REG_ACC = 0; REG_PHASE
	SRC_0; SRC_DETUNE_COUNTER; SRC_TRI_OFFSET
	NO_DEST
end
#const NO_DEST = ?

is_dest(r::RegSrc) = (r != NO_DEST)

@enum LShiftSrc begin
	LSHIFT_0; LSHIFT_1
	LSHIFT_DETUNE; LSHIFT_SLOPE
end

@enum NegSrc2Sel begin
	NS2_CTRL = 0
	NS2_TRIANGLE
end

const lshift_cases = [LSHIFT_0 => 0, LSHIFT_1 => 1, LSHIFT_DETUNE => :(-detune_exp), LSHIFT_SLOPE => :(reg_part ? slope_exp1 : slope_exp0)]
const neg_src2_cases = [NS2_CTRL => :(:neg_src2), NS2_TRIANGLE => :(reg_acc > max_result)]

function alu_op!(code::Vector, dest::RegSrc, src1::RegSrc, src2::RegSrc;
		src2_sign::Int = 1, lshift::LShiftSrc = LSHIFT_0, clamp_result = false, neg_src2_sel::NegSrc2Sel = NS2_CTRL, notneg = false, part_we = false
	)
	@assert is_dest(dest)
	@assert src2_sign == 1 || src2_sign == -1
	push!(code, Dict([
		:src1_sel => src1, :src2_sel => src2, :neg_src2 => (src2_sign == -1), :src2_lshift_sel => lshift, :clamp_result => clamp_result,
		:neg_src2_sel => neg_src2_sel, :notneg => notneg,
		:dest_sel => dest, :part_we => part_we
	]))
end


#const microcode_signal_order = []


# ALU model
# ---------

const dest_cases = [REG_ACC => :reg_acc, REG_PHASE => :reg_phase]
const src_cases = vcat(dest_cases, [SRC_0 => 0, SRC_DETUNE_COUNTER => :detune_counter, SRC_TRI_OFFSET => :tri_offset])
const dest_mappings = Dict(dest_cases)

const alu_model_source = quote
	@reg reg_acc reg_phase reg_part
	@input detune_counter detune_exp tri_offset slope_exp0 slope_exp1
	@input max_result

	src1 = mux(:src1_sel, $src_cases)
	src2_0 = mux(:src2_sel, $src_cases)

	src2_lshift = mux(:src2_lshift_sel, $lshift_cases)
	src2_shifted = src2_lshift >= 0 ? src2_0 << src2_lshift : src2_0 >> -src2_lshift
	neg_src2 = mux(:neg_src2_sel, $neg_src2_cases)
	src2 = neg_src2 ? (:notneg ? ~src2_shifted : -src2_shifted) : src2_shifted

	result_0 = src1 + src2
	clamped_result = min(max_result, max(-max_result - 1, result_0))
	truncated_result = result_0 & (2*max_result + 1)
	result = :clamp_result ? clamped_result : truncated_result
end


# rewrite_graphs
# ==============
function rewrite_graphs(cg::ParseContext, code::Vector{<:Dict}; use_dest_sel = true)
	g = cg.g
	if use_dest_sel;  result = cg.symbols[:result];  end

	graphs = Graph[]
	for (i, mcode) in enumerate(code)
		#mcode = copy(mcode)

		required = Set{NamedSignal}()
		use_dest_sel && is_dest(mcode[:dest_sel]) && push!(required, result)

		r = Rewrite(mcode, required)
		gg = rewrite(r, g)
		if use_dest_sel && is_dest(mcode[:dest_sel])
			bind!(gg, next(cg.symbols[dest_mappings[mcode[:dest_sel]]]), result)
		end

		if (mcode[:part_we])
			bind!(gg, next(cg.symbols[:reg_part]), cg.symbols[:neg_src2])
		end

		# Illustrate the rewrite result if desired
		c = ASTExport(); println(i, ":"); show(export!(c, gg)); println()

		push!(graphs, gg)
	end
	return graphs
end
