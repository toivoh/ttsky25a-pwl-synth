module TryWaveform
using Test
using Plots

include("channel-model.jl")


PHASE_BITS = 12
MANTISSA_BITS = 10

oct = 3
mantissa = 0
period = (((1 << MANTISSA_BITS) + mantissa) << oct) >> 2

flags = 0
#flags = CF_PWL_PHASE

state = ChannelState(PHASE_BITS, MANTISSA_BITS, (oct << MANTISSA_BITS) | mantissa, flags)

#state.slope_exp = [8, 8]
#state.tri_offset = 1 << (PHASE_BITS - 2) # full range is 0 to 2^(PHASE_BITS - 1) - 1

state.slope_exp = [1, 3]
state.slope_add = [1 << (PHASE_BITS - 3), 0] # full range is 0 to 2^(PHASE_BITS - 2) - 1
state.tri_offset = 1 << (PHASE_BITS - 2) # full range is 0 to 2^(PHASE_BITS - 1) - 1

state.amp = round(Int, 0.75*2^(PHASE_BITS - 1)) # full range is 0 to 2^(PHASE_BITS - 1) - 1


phase = Int[]
y = Int[]
for i = 0:period-1
	push!(phase, state.phase)
	push!(y, calc_waveform!(state))
	update_phase!(state)
end

display(plot(y))

end
