using Plots
using FFTW

n_harmonics = 10

function waveform(x, slope_frac, amp)
	y = 2*rem(x, 1, RoundNearest)
	y = abs(y)*2-1

	y1 = 2*y
	y2 = y + copysign(0.5*slope_frac, y)

	y = abs(y1) < abs(y2) ? y1 : y2

	y = clamp(y, -amp, amp)
end

function spectrum(y::Vector)
	f = fft(y)
	#n = (length(f)>>1)+1
	n = n_harmonics
	return abs.(f[2:n])/abs(f[2])
end
spectrum(args...) = spectrum(waveform.(args...))

n = 1024

x = (0:n-1)/n

#slope_middle, slope_spread = 0.5, 0.5
#amp_middle, amp_spread = 1, 0
slope_middle, slope_spread = 0.5, 0.01
amp_middle, amp_spread = 1, 0.01

for (i, (slope_frac, amp)) in enumerate([
		(slope_middle, amp_middle),
		(slope_middle-slope_spread, amp_middle),
		(slope_middle+slope_spread, amp_middle),
		(slope_middle, amp_middle-amp_spread),
		(slope_middle, amp_middle+amp_spread),
	])
	y = waveform.(x, slope_frac, amp)
	pl = i == 1 ? plot : plot!

	#display(pl(x, y))
	h = 1:2:n_harmonics
	display(pl(h, spectrum(y)[1:2:end].*h.^2))
	#display(pl(20log10.(spectrum(y)[1:2:end])))
end
