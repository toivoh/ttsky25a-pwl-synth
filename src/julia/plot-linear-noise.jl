using Plots
using Random

n = 32

x = 0:n-1
#y = rand(Bool, n)
#y = Bool[0, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1]
y = Bool[0, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0]

display(plot(x, y*2, aspect_ratio = 1, axis=([], false), ticks = false, legend = nothing))
