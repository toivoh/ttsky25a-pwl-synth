module SynthTest
using Test
using Plots

include("channel-model.jl")


PHASE_BITS = 12
MANTISSA_BITS = 10

oct = 0
mantissa = 0b0101010100
period = (((1 << MANTISSA_BITS) + mantissa) << oct) >> 2

flags = 0
#flags = CF_PWL_PHASE

state = ChannelState(PHASE_BITS, MANTISSA_BITS, (oct << MANTISSA_BITS) | mantissa, flags)

phase = Int[]
for i = 0:period-1
#for i = 0:2
#	@show i
	push!(phase, state.phase)
	update_phase!(state)
end

display(plot(phase))
@test state.phase == 0

end
