module TryGraphModel
using Plots

include("signals.jl")

@enum Stage begin
	STATE_CMP_REV_PHASE = 0
	STATE_UPDATE_PHASE
	STATE_DETUNE
	STATE_TRI
	#STATE_COMBINED_SLOPE_CMP
	#STATE_COMBINED_SLOPE_ADD
	STATE_COARSE_SLOPE
	STATE_FINE_SLOPE
#	STATE_AMP_CMP
	STATE_AMP
	STATE_OUT_ACC
	NUM_STATES
end

const PHASE_BITS = 12
const FULL_PHASE_MASK = (1 << PHASE_BITS) - 1
const HALF_PHASE_MASK = (1 << (PHASE_BITS - 1)) - 1

const DETUNE_EXP_BITS = 3
const DETUNE_EXP_OFF = (1 << DETUNE_EXP_BITS) - 1

const OUT_RSHIFT = 3

const stage_model_sources = Dict([
	STATE_DETUNE => quote
		@reg acc
		@reg phase oct_counter detune_exp
		delta_phase_0 = oct_counter >> (6 + detune_exp)
		delta_phase = (detune_exp == $DETUNE_EXP_OFF) ? 0 : delta_phase_0 # TODO: detune_down changes sign
		next(acc) = (phase + delta_phase) & FULL_PHASE_MASK # acc unsigned
	end
	STATE_TRI => quote
		@reg acc part
		@reg tri_offset
		curr_part = (acc > HALF_PHASE_MASK)
		next(part) = curr_part
		tri_acc = curr_part ? (~acc) & $HALF_PHASE_MASK : acc
		next(acc) = clamp(acc + tri_offset, $(-(HALF_PHASE_MASK+1)), $HALF_PHASE_MASK)
	end
	STATE_COARSE_SLOPE => quote
		@reg acc
		@reg slope_exp
		acc0 = acc << slope_exp
		next(acc) = clamp(acc0 + tri_offset, $(-(HALF_PHASE_MASK+1)), $HALF_PHASE_MASK)
	end
	STATE_FINE_SLOPE => quote
		@reg acc
		@reg slope_add
		acc0 = acc >= 0 ? min(2*acc, acc + slope_add) : max(2*acc, acc - slope_add)
		acc0 = acc << slope_exp
		next(acc) = clamp(acc0 + tri_offset, $(-(HALF_PHASE_MASK+1)), $HALF_PHASE_MASK)
	end
	STATE_AMP => quote
		@reg acc
		@reg amp
		next(acc) = clamp(acc, -amp, amp)
	end
	STATE_OUT_ACC => quote
		@reg acc out_acc
		@input first_term
		next(out_acc) = (first_term ? 0 : out_acc) + (acc >> OUT_RSHIFT) # not supposed to go out of bounds
	end
])

signal_dict = SignalDict()




end
