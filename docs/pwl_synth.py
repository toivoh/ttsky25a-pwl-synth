
PERIPHERAL_NUM = 33
BASE_ADDRESS = 0x800_0000 + PERIPHERAL_NUM*64

REG_PERIOD = 0
REG_PHASE = 1
REG_AMP = 2
REG_SLOPE_R = 4
REG_SLOPE_F = 6
REG_PWM_OFFSET = 8
REG_MODE = 10
REG_SWEEP_PA = 12
REG_SWEEP_WS = 14

WAVEFORM_LINEAR_OSC = 0
WAVEFORM_NOISE = 1
WAVEFORM_PWL_OSC = 2
WAVEFORM_ORION = 3

OSC_SYNC_OFF = 0
OSC_SYNC_4_BIT = 1
OSC_SYNC_HARD = 2
OSC_SYNC_SOFT = 3

CFG_STEREO_EN = 1
CFG_STEREO_POS_EN = 2

# Chromatic scale starting on B
note_mantissas = [1001, 887, 780, 679, 583, 493, 408, 327, 252, 180, 112, 49]

note_names = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11};

# Store current channel values so that we can restore or modify them
curr_on = [False]*4
curr_slopes_r = [0]*4
curr_slopes_f = [0]*4
curr_pwm_offsets = [0]*4
curr_modes = [0]*4
curr_sweep_pa = [0]*4
curr_sweep_ws = [0]*4
curr_cfg = 0

def raw_reg_write(address, data):
	machine.mem16[BASE_ADDRESS + (address&63)] = data

def reg_write(channel, reg, data):
	address = channel*16 + reg
	machine.mem16[BASE_ADDRESS + (address&63)] = data

def set_cfg(cfg):
	curr_cfg = cfg
	raw_reg_write(0x23, cfg)

def sweeps_off(channel):
	reg_write(channel, REG_SWEEP_PA, 0)
	reg_write(channel, REG_SWEEP_WS, 0)

def note_off(channel):
	reg_write(channel, REG_SWEEP_PA, 0) # make sure that amp doesn't start to sweep upward after we set it to zero
	reg_write(channel, REG_AMP, 0)
	curr_on[channel] = False

def all_notes_off():
	for channel in range(4): note_off(channel)

def play_raw_note(channel, f_period, amp=63):
	reg_write(channel, REG_PERIOD, f_period)
	reg_write(channel, REG_AMP, amp)
	curr_on[channel] = True

def get_f_period(note, octave = 4):
	note += 12*octave
	note += 1 # since note_mantissas starts on B
	note, octave = note % 12, note // 12

	if octave < 0: octave = 0
	elif octave > 7: octave = 7

	mantissa = note_mantissas[note]
	if octave >= 6: mantissa &= -1 << (octave - 5) # round to make sure that we hit an integer period

	return mantissa | ((7-octave)<<10)

def write_curr_waveform(channel):
	reg_write(channel, REG_SLOPE_R, curr_slopes_r[channel])
	reg_write(channel, REG_SLOPE_F, curr_slopes_f[channel])
	reg_write(channel, REG_PWM_OFFSET, curr_pwm_offsets[channel])
	reg_write(channel, REG_MODE, curr_modes[channel])

# note can be an integer (semitones from C0) or (name, octave), where name is a key in note_names
# relative_detune is specified in semitones: increase by 12 to double the detuning (or set to None to turn off detuning)
def play_note(channel, note, amp=63, relative_detune=0):
	if isinstance(note, tuple):
		note_name, octave = note
		note = note_names[note_name] + octave*12

	# Set detuning based on note frequency
	if relative_detune == None:
		detune_f = 0
	else:
		detune_f =(note + relative_detune) // 6
		detune_f = max(0, min(15, detune_f))

	# Update detune_exp and possibly detune_fifth
	mode = curr_modes[channel]
	mode = (mode & ~7) | (detune_f >> 1)
	if (curr_cfg & CFG_STEREO_POS_EN) != 0 or (mode & 7 << 4) == 0: # set detune_fifth when not using freq_multipliers (including when stereo position mode is on)
		mode = (mode & ~2048) | ((detune_f&1) << 11)
	curr_modes[channel] = mode

	note_off(channel)
	reg_write(channel, REG_SWEEP_WS, 0)
	write_curr_waveform(channel)
	play_raw_note(channel, get_f_period(note), amp)
	reg_write(channel, REG_SWEEP_PA, curr_sweep_pa[channel])
	reg_write(channel, REG_SWEEP_WS, curr_sweep_ws[channel])

def set_waveform(channel, slope_r=0, slope_f=0, pwm_offset=0, detune_exp=0, waveform=0, freq_multipliers=0, common_sat=False, osc_sync=0, detune_fifth=False):
	mode = (detune_exp&7) | ((waveform&1)<<3) | ((freq_multipliers&7)<<4) | ((common_sat&1)<<7) | ((waveform&2)<<7) | ((osc_sync&3)<<9) | ((detune_fifth&1)<<11)

	curr_slopes_r[channel] = slope_r
	curr_slopes_f[channel] = slope_f
	curr_pwm_offsets[channel] = pwm_offset
	curr_modes[channel] = mode

	if curr_on[channel]:  # otherwise, the waveform will be applied when starting the next note
		write_curr_waveform(channel)

def set_period_amp_sweep(channel, period_down=False, period_rate=0, amp_target=0, amp_rate=0):
	if period_rate == 2: period_rate = 1 # represent as maximum rate
	if 0 < amp_rate <= 4: amp_rate = 1 # clamp to maximum rate, repesent amp_rate=4 as maximum rate

	period_sweep = (period_rate&15) | ((period_down&1)<<4)
	amp_sweep = (amp_rate&15) | ((amp_target&7) << 4)
	curr_sweep_pa[channel] = amp_sweep | (period_sweep << 8)
	if curr_on[channel]:
		reg_write(channel, REG_SWEEP_PA, curr_sweep_pa[channel])

def set_pwm_slope_sweep(channel, pwm_down=False, pwm_rate=0, slope_down=False, slope_dir=3, slope_rate=0):
	if 0 < pwm_rate <= 4: pwm_rate = 1 # clamp to maximum rate, repesent pwm_rate=4 as maximum rate
	if 0 < slope_rate <= 4: slope_rate = 1 # clamp to maximum rate, repesent slope_rate=4 as maximum rate

	pwm_sweep = (pwm_rate&15) | ((pwm_down&1)<<4)
	slope_sweep = (slope_rate&15) | ((slope_down&1) << 4) | ((slope_dir&3) << 5)
	curr_sweep_ws[channel] = slope_sweep | (pwm_sweep << 8)
	if curr_on[channel]:
		reg_write(channel, REG_SWEEP_WS, curr_sweep_ws[channel])
