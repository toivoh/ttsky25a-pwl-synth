module PwlOscillator
using Plots
using Test

const BITS = 12


function wf(mantissa::Int, n::Int)
	y = Int[]
	phase = 0
	for i = 1:n
		phase_mod = phase & ((2^(BITS-1) - 1) & ~1)
		phase_mod |= (phase >> (BITS-1)) & 1

		small_step = (phase_mod < mantissa)
		phase += 2 - small_step
		phase &= (2^BITS - 1)

		push!(y, phase)
	end
	return y
end

#mantissa = 0x5555 & (2^(BITS-1)-1)
mantissa = 0xaaaa & (2^(BITS-1)-1)

period = 2^(BITS-1) + mantissa

y = wf(mantissa, 2*period)
display(plot(y))
@test y[end] == 0



display(plot(y, color = 3))

n = length(y)
period = n >> 1
x = 0:n
y = round.((x .% period) * (256 / period))*16

display(plot!(x .- n*1.1, y, color = 1, aspect_ratio = 1, axis=([], false), ticks = false, legend = nothing))
#savefig("../../docs/pwl-phase-uncropped.png")

end

