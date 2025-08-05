
const CF_PWL_PHASE = 1
const NO_DETUNE = 7

mutable struct ChannelState
	PHASE_BITS::Int
	MANTISSA_BITS::Int

	period::Int
	flags::Int
	detune_exp::Int
	tri_offset::Int
	slope_exp::Vector{Int}
	slope_add::Vector{Int}
	amp::Int

	phase::Int
	oct_counter::Int
	acc::Int

	ChannelState(PHASE_BITS::Int, MANTISSA_BITS::Int, period::Int, flags::Int) = new(PHASE_BITS, MANTISSA_BITS, period, flags, NO_DETUNE, 0, [0, 0], [0, 0], (1 << (PHASE_BITS-1))-1,  0, 0, 0)
end

phase_mask_of(c::ChannelState) = ((1 << (c.PHASE_BITS - 1)) - 1)
full_phase_mask_of(c::ChannelState) = ((1 << c.PHASE_BITS) - 1)
split_period(c::ChannelState) = (c.period >> c.MANTISSA_BITS, c.period & ((1 << c.MANTISSA_BITS) - 1))

signed_clamp(c::ChannelState, x::Int) = clamp(x, -1 << (c.PHASE_BITS - 1), (1 << (c.PHASE_BITS - 1)) - 1)


function update_phase!(c::ChannelState)
	oct, mantissa = split_period(c)

	shift_count = 3 - oct
	skip = false
	if shift_count < 0
		oct_enables = (c.oct_counter + 1) & ~c.oct_counter
		skip = (((oct_enables >> (-shift_count - 1)) & 1) == 0)
		shift_count = 0
	end

	if !skip
		delayed = (((c.phase >> shift_count) & 1) != 0)

		if delayed
			small_step = true
		else
			mantissa_ext = (mantissa << (c.PHASE_BITS - 1 - c.MANTISSA_BITS))
			if c.flags & CF_PWL_PHASE == 0
				rev_phase = bitreverse(UInt16(c.phase >> 1)) >> (16 - (c.PHASE_BITS - 1))
				rev_phase_shifted = (rev_phase << shift_count) & phase_mask_of(c)

				small_step = rev_phase_shifted < mantissa_ext
			else
				cmp_phase = c.phase >> 1
				cmp_phase &= -1 << shift_count # for correct period quantization; the lowest shift_count bits in phase are not used
				small_step = cmp_phase < mantissa_ext
			end
		end

		c.phase = (c.phase + ((small_step ? 1 : 2) << shift_count)) & full_phase_mask_of(c)
	end
	c.oct_counter += 1
end

function calc_waveform!(c::ChannelState, detune_down::Bool=false)
	acc = c.phase

	# Detune
	if c.detune_exp != NO_DETUNE
		delta_phase = c.oct_counter >> (6 + c.detune_exp)
		acc += detune_down ? -delta_phase : delta_phase
		acc &= full_phase_mask_of(c)
	end

	# Triangle
	acc = acc << 1
	second_half = acc >= (1 << c.PHASE_BITS)
	if second_half
		acc = xor(acc, full_phase_mask_of(c))
	end
	acc &= full_phase_mask_of(c)

	# Offset
	acc = min(acc + c.tri_offset, full_phase_mask_of(c))

	# Convert to signed
	acc -= (1 << (c.PHASE_BITS - 1))

	# Slope
	slope_exp = c.slope_exp[begin + second_half]
	acc <<= slope_exp
	acc = signed_clamp(c, acc)

	# Fine slope
	slope_add = c.slope_add[begin + second_half]
	if acc >= 0; acc = min(2*acc, acc + slope_add)
	else         acc = max(2*acc, acc - slope_add)
	end
	acc = signed_clamp(c, acc)

	# Volume clamp
	acc = clamp(acc, -c.amp, c.amp)

	c.acc = acc
	return acc
end
