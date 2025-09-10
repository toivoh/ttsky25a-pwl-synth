using Plots

x = -1:0.001:1

for (i, slope_frac) in enumerate(0:0.25:1)
	pl = i == 1 ? plot : plot!

	y = clamp.(2x, x .- slope_frac./2, x .+ slope_frac/2)
	y = clamp.(y, -1, 1)

	display(pl(x .+ i*2, y, color = 1, aspect_ratio = 1, axis=([], false), ticks = false, legend = nothing))
end

#savefig("../../docs/slope-uncropped.png")
