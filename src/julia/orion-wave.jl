using Plots

mask = 0b11001011111

function orion_wave(x::Integer, mask::Integer, offset::Integer=0, pwm_offset::Integer=255)
	## Input: sawtooth wave, 12 bits (0 - 4095)
	#y = phase
	y = x & 4095

	# Don't transform the sawtooth to a triangle wave, but offset in different directions depending on if we are in the first or second half of the cycle
	if y < 2048; y += (pwm_offset - 256) << 2
	else         y -= (pwm_offset - 256) << 2
	end
	y = y & 4095

	## Shuffle the bits
	#y = {y[11], [9], y[8], y[11], y[10], y[6], [8], y[7], 0, y[4], 0}
	x = y
	y = 0
	y |= ((x >>  4).&1) <<  1
	y |= ((x >>  7).&1) <<  3
	y |= ((x >>  8).&1) <<  4
	y |= ((x >> 6).&1)  <<  5
	y |= ((x >> 10).&1) <<  6
	y |= ((x >> 11).&1) <<  7
	y |= ((x >> 8).&1)  <<  8
	y |= ((x >>  9).&1) <<  9
	y |= ((x >> 11).&1) << 10

	## Mask the result
	#mask = {slope_f[7:0], {3{slope_f[7:0]}}}
	y &= mask

	## Add offset, multiply by 3 and wrap around
	#offset = slope_r[5:0] << 5
	offset = (offset & 63) << 5
	y = ((y + offset) * 3) & 2047

	# Output: 11 bits signed
	if (y >= 1024); y -= 2048; end

	return y
end

#=
x = 0:4095
y = orion_wave.(x, mask)
display(plot(x, y, axis=([], false), ticks = false, legend = nothing))
=#

for (i, offset) in enumerate(0:4:15)
	x = 0:4095
	y = orion_wave.(x, mask, offset)
	@show maximum(y)
	pl = (i == 1) ? plot : plot!
	display(pl(x .+ (i-1)*(4096+512), y, axis=([], false), ticks = false, legend = nothing, color = 1, aspect_ratio = 1))
end


#savefig("../../docs/orion-wave-uncropped.png")
