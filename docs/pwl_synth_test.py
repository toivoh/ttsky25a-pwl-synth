import pwl_synth
import time

def raw_reg_write(address, data):
	print("raw_reg_write(", address, ", ", data, ")", sep="")

def reg_write(channel, reg, data):
	print("reg_write(", channel, ", ", reg, ", ", data, ")", sep="")

pwl_synth.raw_reg_write = raw_reg_write
pwl_synth.reg_write = reg_write

from pwl_synth import *

def sleep(t):
	print("sleep(", t, ")", sep="")

def test1():
	notes = [("C", 4), ("G", 4), ("B", 4), ("C", 5)]
	channel = 0
	relative_detune = 0  # Try to increase decrease, or set to None to turn off detuning

	# Fade out each note by sweeping down amp. Set amp_rate=0 to keep sustained.
	set_period_amp_sweep(channel, amp_target=0, amp_rate=12)  # amp_rate = 12 should ramp down in around 0.5 s at 64 MHz clock frequency

	for note in notes:
		play_note(channel, note, relative_detune=relative_detune)

		sleep(0.5)
	sleep(0.5)
	note_off(channel)

def test2():
	notes = [("D", 3), ("G", 3), ("C", 4), ("Eb", 4)]
	relative_detune = 0  # Try to increase decrease, or set to None to turn off detuning
	for (channel, note) in enumerate(notes):
		# Fade in each note by sweeping up amp. Takes effect when the next note is played.
		set_period_amp_sweep(channel, amp_target=63, amp_rate=12)  # amp_rate = 12 should ramp down in around 0.5 s at 64 MHz clock frequency

		play_note(channel, note, amp=0, relative_detune=relative_detune)

		sleep(0.5)
	sleep(0.5)
	all_notes_off()

def test3():
	channel = 0

	# Triangle wave.
	# Timbre initially becomes darker (more sine-like) when lowering amplitude from amp_s = 1.
	set_waveform(channel, slope_r=0, slope_f=0, pwm_offset=0)

	# 4 bit triangle wave
	set_waveform(channel, slope_r=0, slope_f=0, pwm_offset=0, osc_sync=OSC_SYNC_4_BIT)

	# Square wave
	slope = 12*16  # Reduce to make it smoother (eventually turning into a triangle wave)
	set_waveform(channel, slope_r=slope, slope_f=slope, pwm_offset=0)

	# Sawtooth-like wave
	slope = 12*16  # Reduce to make it smoother (eventually turning into a triangle wave)
	set_waveform(channel, slope_r=0, slope_f=slope, pwm_offset=0)

	# 25% duty pulse wave. Reduce both slope_s values equally to make it smoother.
	# Amplitude starts to drop when slope < 1*16.
	slope = 12*16  # Reduce to make it smoother
	set_waveform(channel, slope_r=slope, slope_f=slope, pwm_offset=128)

	# 12.5% duty pulse wave. Reduce both slope_s values equally to make it smoother.
	# Amplitude starts to drop when slope < 2*16.
	slope = 12*16  # Reduce to make it smoother
	set_waveform(channel, slope_r=slope, slope_f=slope, pwm_offset=192)

	# Sine wave approximation. Varying the amplitude and slope a bit
	# (while keeping both slopes the same) gives other approximattions.
	set_waveform(channel, slope_r=8, slope_f=8, pwm_offset=0)

	# Clamped triangle wave. Same spectrum as a triangle wave (but 6 dB louder) at full amplitude,
	# but timbre starts to become brighter as soon as lowering amplitude from amp_s = 1.
	set_waveform(channel, slope_r=16, slope_f=16, pwm_offset=0)

	# Noise. Don't use on channels 0 and 3 at the same time, note that channels 1 and 2 have noise with a short period (11 bit LFSR)
	set_waveform(channel, slope_r=0, slope_f=0, pwm_offset=0, waveform=WAVEFORM_NOISE)

	# Sawtooth-like wave with common saturation (works only on channel 0) and (3x, 2x) frequency multiplier (power chord).
	# Play one octave lower than it is intended to sound, since the frequency multipliers raise the frequency.
	slope = 12*16  # Reduce to make it smoother
	set_waveform(channel, slope_r=0, slope_f=slope, pwm_offset=0, freq_multipliers=3, common_sat=True)
	# Try with set_pwm_slope_sweep(channel, slope_down=True, slope_rate=12)

	set_pwm_slope_sweep(channel, slope_down=True, slope_rate=10)  # slope_rate = 10 should be enough to sweep from full slope to zero in about 0.5 s

	set_waveform(channel, slope_r=16, slope_f=16)
	set_period_amp_sweep(channel, period_down=False, period_rate=1, amp_target=0, amp_rate=8)
	play_note(channel, ("C", 4), amp=63, relative_detune=None)

	sleep(1)

	set_period_amp_sweep(channel, period_down=False, period_rate=1, amp_target=0, amp_rate=10)
	set_waveform(channel, slope_r=0, slope_f=0, pwm_offset=0, waveform=WAVEFORM_NOISE)
	play_note(channel, ("Bb", 7), amp=63, relative_detune=None)  # Bb7 is the highest note in the scale right now

if True:
	channel = 0
	slope = 12*16  # Reduce to make it smoother
	set_waveform(channel, slope_r=slope, slope_f=slope, pwm_offset=128)

test1()
test2()
test3()
