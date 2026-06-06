-- awake-ashsynth: time changes + Ash engine
-- based on awake-passersby / awake @tehn
--
-- top loop plays notes
-- transposed by bottom loop
--
-- (grid optional)
--
-- E1 changes modes:
-- STEP/LOOP/SOUND/OPTION
--
-- K1 held is alt *
--
-- STEP
-- E2/E3 move/change
-- K2 toggle *clear
-- K3 morph *rand
-- K1 + grid: toggle TIE (legato into next step; dim step column + dark note = tied)
--
-- LOOP
-- E2/E3 loop length
-- K2 reset position
-- K3 jump position
--
-- SOUND
-- K2/K3 selects
-- E2/E3 changes
--
-- OPTION
-- *toggle
-- E2/E3 changes

engine.name = "Ash"
local Ash = include "lib/ash_engine"

local MusicUtil = require "musicutil"

local options = {}
options.OUTPUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF", "crow ii JF + cv"}
options.STEP_LENGTH_NAMES = {"1 bar", "1/2", "1/3", "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32", "1/48", "1/64"}
options.STEP_LENGTH_DIVIDERS = {1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64}

local grid = util.file_exists(_path.code.."toga") and include "toga/lib/togagrid" or grid
local arc = util.file_exists(_path.code.."toga") and include "toga/lib/togaarc" or arc

local g = grid.connect()

local alt = false

local mode = 1
local mode_names = {"STEP","LOOP","SOUND","OPTION"}

local one = {
  pos = 0,
  length = 8,
  start = 1,
  data = {1,0,3,5,6,7,8,7,0,0,0,0,0,0,0,0},
  tie = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
}

local two = {
  pos = 0,
  length = 7,
  start = 1,
  data = {5,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
  tie = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
}

function add_pattern_params() 
  params:add_separator()
  
  params:add{type = "number", id = "one_length", name = "<one> length]", min=1, max=16, 
    default = one.length,
    action=function(x) one.length = x end }

  params:add{type = "number", id = "one_start", name = "<one> start]", min=1, max=16, 
    default=one.start,
    action=function(x) one.start = x end }
  
  for i=1,16 do
    params:add{type = "number", id= ("one_data_"..i), name = ("<one> data "..i), min=0, max=8, 
      default = one.data[i],
      action=function(x)one.data[i] = x end }
    params:add{type = "number", id= ("one_tie_"..i), name = ("<one> tie "..i), min=0, max=1,
      default = one.tie[i],
      action=function(x) one.tie[i] = x end }
  end
  
  params:add_separator()
  
  params:add{type = "number", id = "two_length", name = "<two> length]",  min=1, max=16, 
    default = two.length,
    action=function(x)two.length = x end}
  
  params:add{type = "number", id = "two_start", name = "<two> start]",  min=1, max=16, 
    default = two.start,
    action=function(x)two.start = x end }
  
  for i=1,16 do
    params:add{type = "number", id= "two_data_"..i, name = "<two> data "..i,  min=0, max=8, 
      default = two.data[i],
      action=function(x) two.data[i] = x end }
    params:add{type = "number", id= "two_tie_"..i, name = "<two> tie "..i, min=0, max=1,
      default = two.tie[i],
      action=function(x) two.tie[i] = x end }
  end
  
  params:add_separator()
end

local set_loop_data = function(which, step, val)
  params:set(which.."_data_"..step, val)
end

local function set_loop_tie(which, step, val)
  params:set(which.."_tie_"..step, val)
end

local function toggle_loop_tie(which, step)
  set_loop_tie(which, step, 1 - params:get(which.."_tie_"..step))
end

local function loop_prev_pos(loop, pos)
  local p = pos - 1
  if p < 1 then p = loop.length end
  return p
end

local function loop_has_tie(which, step)
  return params:get(which.."_tie_"..step) == 1
end

-- Awake: pitch = one + two; upper gates sound. Lower "0" is still a valid offset step.
local function step_is_legato_any()
  if one.data[one.pos] <= 0 then return false end
  local prev_one = loop_prev_pos(one, one.pos)
  if one.data[prev_one] <= 0 then return false end

  if loop_has_tie("one", prev_one) then return true end

  local prev_two = loop_prev_pos(two, two.pos)
  if two.data[prev_two] > 0 and loop_has_tie("two", prev_two) then return true end

  return false
end

local function grid_pitch_row(data)
  return 9 - data
end



local midi_out_device
local midi_out_channel

local scale_names = {}
local notes = {}
local active_notes = {}

local edit_ch = 1
local edit_pos = 1

snd_sel = 1
local snd_names = {"cutoff", "reso", "drive", "reverb", "delay", "fdbk"}
local snd_params = {"lp_cutoff", "lp_resonance", "drive", "reverb_mix", "delay_mix", "delay_feedback"}
local NUM_SND_PARAMS = #snd_params

-- ashsynth grid default (0.85); MIDI uses vel/127
local NOTE_VEL = 0.85

-- MIDI CC map (same as ashsynth)
local builtin_cc = {
  [1] = "lp_env_amount", [7] = "drive", [71] = "lp_resonance", [74] = "lp_cutoff",
}

local assign_cc_options = {
  "none",
  "osc1_level", "osc2_level", "osc1_pitch", "osc2_pitch", "osc1_octave", "osc2_octave",
  "noise_level", "fm_amount", "glide", "lp_cutoff", "lp_resonance", "lp_env_amount",
  "filter_attack", "filter_decay", "amp_attack", "amp_decay",
  "lfo_rate", "lfo_master", "lfo_osc_amount", "lfo_filter_amount", "lfo_amp_amount",
  "lfo_filter_env_attack_amount", "lfo_filter_env_decay_amount", "lfo_filter_env_sustain_amount", "lfo_filter_env_release_amount",
  "lfo_pw_amount", "lfo_detune1_amount", "lfo_detune2_amount", "lfo_noise_amount", "lfo_fm_amount", "lfo_glide_amount",
  "lfo_delay_amount", "lfo_reverb_amount", "lfo_drive_amount",
  "lfo2_rate", "lfo2_master", "lfo2_osc_amount", "lfo2_filter_amount", "lfo2_amp_amount",
  "lfo2_filter_env_attack_amount", "lfo2_filter_env_decay_amount", "lfo2_filter_env_sustain_amount", "lfo2_filter_env_release_amount",
  "lfo2_pw_amount", "lfo2_detune1_amount", "lfo2_detune2_amount", "lfo2_noise_amount", "lfo2_fm_amount", "lfo2_glide_amount",
  "lfo2_delay_amount", "lfo2_reverb_amount", "lfo2_drive_amount",
  "delay_mix", "delay_feedback", "reverb_mix", "drive",
}

local function cc_to_param(cc)
  if builtin_cc[cc] then return builtin_cc[cc] end
  for i = 1, 4 do
    if params:get("cc_num_" .. i) == cc then
      local n = assign_cc_options[params:get("cc_assign_" .. i)]
      if n ~= "none" then return n end
    end
  end
end

local function set_cc_value(param_id, val)
  local idx = params.lookup and params.lookup[param_id]
  if idx then
    local p = params:lookup_param(idx)
    if p and p.t == 3 and p.options then
      params:set(param_id, util.clamp(util.round(val * #p.options - 0.001) + 1, 1, #p.options))
      return
    end
  end
  local ok, a, b = pcall(function() return params:get_range(param_id) end)
  if ok and a and b then params:set(param_id, util.linlin(0, 1, a, b, val)) end
end

local BeatClock = include 'lib/beatclock-crow'
local clk = BeatClock.new()
local clk_midi = midi.connect()
local delay_sync_clock_id = nil

local PRESET_DIR = "awake-ashsynth"
local PRESET_PREFIX = "awake-ashsynth-"

local function clk_midi_event(data)
  clk:process_midi(data)

  local msg = midi.to_msg(data)
  if msg.type == "cc" then
    local ch = params:get("midi_channel")
    if ch == 1 or (ch > 1 and msg.ch == ch - 1) then
      local pid = cc_to_param(msg.cc)
      if pid then set_cc_value(pid, msg.val / 127) end
    end
    return
  end

  local status = data[1]

  if status >= 0xC0 and status <= 0xCF then
    local program_number = data[2]
    local midi_channel = (status - 0xC0) + 1
    local file_num = program_number + 1

    if file_num >= 1 and file_num <= 16 then
      local preset_filename = PRESET_PREFIX .. string.format("%02d", file_num) .. ".pset"
      local preset_path = _path.data .. PRESET_DIR .. "/" .. preset_filename

      print("Checking for preset file: "..preset_path)

      if util.file_exists(preset_path) then
        print("MIDI PC "..program_number.." (Channel "..midi_channel..") received. Loading preset: "..preset_filename)
        params:read(preset_path)
        params:bang()
        Ash.push_engine_state()
        build_scale()
        apply_delay_from_bpm()
        if redraw then redraw() end
      else
        print("MIDI PC "..program_number.." (Channel "..midi_channel..") received. Preset file not found: "..preset_filename)
        print("Expected path: ".._path.data .. PRESET_DIR .."/")
      end
    end
  end
end

clk_midi.event = clk_midi_event

local SCREEN_FRAMERATE = 15
local screen_refresh_metro
local notes_off_metro = metro.init()

function build_scale()
  notes = MusicUtil.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), 16)
  local num_to_add = 16 - #notes
  for i = 1, num_to_add do
    table.insert(notes, notes[16 - num_to_add])
  end
end

local function release_notes(legato)
  if not legato then
    if params:get("output") == 1 or params:get("output") == 3 then
      if engine and engine.noteOff then engine.noteOff(1) end
    end
    if (params:get("output") == 2 or params:get("output") == 3) then
      for _, a in pairs(active_notes) do
        midi_out_device:note_off(a, nil, midi_out_channel)
      end
    end
    active_notes = {}
  end
end

local function all_notes_off()
  release_notes(false)
end

local function apply_glide_for_step(legato)
  if not engine or not engine.glideOn then return end
  if params:get("glide") <= 0 then
    engine.glideOn(0)
    return
  end
  local on = 0
  if params:get("glide_mode") == 1 then
    on = 1
  elseif params:get("glide_mode") == 2 and legato then
    on = 1
  end
  engine.glideOn(on)
end

local function engine_note_on(freq, legato)
  apply_glide_for_step(legato)
  engine.noteOn(1, freq, NOTE_VEL)
end

local function apply_delay_from_bpm()
  if not engine or not engine.delayTime then return end
  if params:get("delay_sync") ~= 2 then return end
  local beats = Ash.delay_division_beats(params:get("delay_division"))
  local beat_sec = 60 / math.max(20, clk.bpm)
  engine.delayTime(util.clamp(beat_sec * beats, 0.01, 2))
end

local function morph(loop, which)
  for i=1,loop.length do
    if loop.data[i] > 0 then
      set_loop_data(which, i, util.clamp(loop.data[i]+math.floor(math.random()*3)-1,1,8))
    end
  end
end

local function random()
  for i=1,one.length do
    set_loop_data("one", i, math.floor(math.random()*9))
    set_loop_tie("one", i, 0)
  end
  for i=1,two.length do
    set_loop_data("two", i, math.floor(math.random()*9))
    set_loop_tie("two", i, 0)
  end
end

local function step()
  one.pos = one.pos + 1
  if one.pos > one.length then one.pos = 1 end
  two.pos = two.pos + 1
  if two.pos > two.length then two.pos = 1 end

  local legato = step_is_legato_any()
  release_notes(legato)

  if one.data[one.pos] > 0 then
    local note_num = notes[one.data[one.pos]+two.data[two.pos]]
    local freq = MusicUtil.note_num_to_freq(note_num)
    if math.random(100) <= params:get("probability") then
      if params:get("output") == 1 or params:get("output") == 3 then
        engine_note_on(freq, legato)
      elseif params:get("output") == 4 then
        crow.output[1].volts = (note_num-60)/12
        crow.output[2]()
      elseif params:get("output") == 5 then
        crow.ii.jf.play_note((note_num-60)/12,5)
      elseif params:get("output") == 6 then
        crow.output[1].volts = (note_num-60)/12
        crow.output[2]()
        crow.ii.jf.play_note((note_num-60)/12,5)
      end
      
      if (params:get("output") == 2 or params:get("output") == 3) then
        midi_out_device:note_on(note_num, 96, midi_out_channel)
        table.insert(active_notes, note_num)

        if params:get("note_length") < 4 and not legato then
          notes_off_metro:start((60 / clk.bpm / clk.steps_per_beat / 4) * params:get("note_length"), 1)
        end
      end
    end
  else
    release_notes(false)
  end

  if params:get("crow_clock_out") == 2 then crow.output[4]() end

  if g then
    gridredraw()
  end
  redraw()

end

local function stop()
  all_notes_off()
  if engine and engine.noteOffAll then engine.noteOffAll() end
end

local function crow_init()
  
  local crow_tap = 0
  local crow_deltatap = 1

  crow.input[1].mode("change", 1, 0.05, "rising")
  crow.input[1].change = function(s)
    if params:get("crow_clock_input") ~= 2 then
      morph(one, "one")
      morph(two, "two")
    else
      step()
      local crow_tap1 = util.time()
      crow_deltatap = crow_tap1 - crow_tap
      crow_tap = crow_tap1
      local crow_tap_tempo = (60/crow_deltatap)/4
      params:set("bpm",math.floor(crow_tap_tempo+0.5))
    end
  end
  crow.input[2].mode("change", 1, 0.05, "rising")
  crow.input[2].change = function()
    if params:get("crow_clock_input") ~= 3 then
      random()
    else
      step()
    end
  end
  
  if params:get("output") == 4 then
    crow.output[2].action = "{to(5,0),to(0,0.25)}"
  end
  
end

norns.crow.add = function()
  norns.crow.init()
  crow_init()
end

function load_preset(num)
  local preset_path = _path.data .. PRESET_DIR .. "/" .. PRESET_PREFIX .. string.format("%02d", num) .. ".pset"
  if util.file_exists(preset_path) then
    params:read(preset_path)
    params:bang()
    Ash.push_engine_state()
    build_scale()
    apply_delay_from_bpm()
    print("불러온 프리셋: "..PRESET_PREFIX..string.format("%02d", num))
  else
    print("프리셋 없음: " .. preset_path)
  end
end

local function update_delay_actions()
  params:set_action("delay_time", function(v)
    if params:get("delay_sync") == 1 then engine.delayTime(v) end
  end)
  params:set_action("delay_division", function()
    if params:get("delay_sync") == 1 then Ash.apply_delay_time() else apply_delay_from_bpm() end
  end)
  params:set_action("delay_sync", function()
    if params:get("delay_sync") == 1 then Ash.apply_delay_time() else apply_delay_from_bpm() end
  end)
end

function init()
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  
  midi_out_device = midi.connect(1)
  
  clk.on_step = step
  clk.on_stop = stop
  clk.on_select_internal = function()
    clk:start()
    params:set("crow_clock_input",1)
  end
  clk.on_select_midi = function()
    one.pos = 0
    two.pos = 0
    params:set("crow_clock_input",1)
  end
  clk.on_select_crow = function()
    params:set("crow_clock_input",2)
  end
  clk:add_clock_params()
  params:set("bpm", 91)
  params:set_action("bpm", function(v)
    clk:bpm_change(v)
    apply_delay_from_bpm()
  end)
  
  params:add{type = "trigger", id = "clear_crow", name = "reset/clear crow [K3]", action = function()
    norns.crow.init()
  end}
  
  notes_off_metro.event = all_notes_off
  
  params:add{type = "option", id = "output", name = "output",
    options = options.OUTPUT,
    action = function(value)
      all_notes_off()
      if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      elseif value == 5 or value == 6 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      end
    end}
  params:add{type = "trigger", id = "reset_jf_ii", name = "reset JF [K3]", action = function()
    crow.ii.jf.mode(0)
    end}
  params:add{type = "number", id = "midi_out_device", name = "midi out device",
    min = 1, max = 4, default = 1,
    action = function(value) midi_out_device = midi.connect(value) end}
  params:add{type = "number", id = "midi_out_channel", name = "midi out channel",
    min = 1, max = 16, default = 1,
    action = function(value)
      all_notes_off()
      midi_out_channel = value
    end}
  params:add{type = "number", id = "midi_device", name = "midi in device",
    min = 1, max = 4, default = 1,
    action = function(value)
      clk_midi.event = nil
      clk_midi = midi.connect(value)
      clk_midi.event = clk_midi_event
    end}
  local midi_channels = {"All"}
  for i = 1, 16 do table.insert(midi_channels, i) end
  params:add{type = "option", id = "midi_channel", name = "midi in channel",
    options = midi_channels, default = 1}
  params:add_separator("midi cc assign")
  for i = 1, 4 do
    params:add{type = "number", id = "cc_num_" .. i, name = "CC #" .. i, min = 0, max = 127, default = 10 + i}
    params:add{type = "option", id = "cc_assign_" .. i, name = "CC " .. i .. " dest",
      options = assign_cc_options, default = 1}
  end
  params:add_separator()
  
  params:add{type = "option", id = "step_length", name = "step length", options = options.STEP_LENGTH_NAMES, default = 8,
    action = function(value)
      clk.ticks_per_step = 96 / options.STEP_LENGTH_DIVIDERS[value]
      clk.steps_per_beat = options.STEP_LENGTH_DIVIDERS[value] / 4
      clk:bpm_change(clk.bpm)
      apply_delay_from_bpm()
    end}
  params:add{type = "option", id = "note_length", name = "note length",
    options = {"25%", "50%", "75%", "100%"},
    default = 4}
  
  params:add{type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5,
    action = function() build_scale() end}
  params:add{type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() build_scale() end}
  params:add{type = "number", id = "probability", name = "probability",
    min = 0, max = 100, default = 100,}
  params:add_separator()

  Ash.add_params()
  update_delay_actions()

  crow_init()

  clk:start()

  -- ashsynth: engine direct out only (no awake halfsecond softcut loop)
  audio.level_eng_cut(0)
  audio.level_adc_cut(0)
  audio.level_adc(0)
  softcut.enable(1, 0)

  add_pattern_params()
  params:default()
  build_scale()

  screen_refresh_metro = metro.init()
  screen_refresh_metro.time = 1 / SCREEN_FRAMERATE
  screen_refresh_metro.event = function() redraw() end
  screen_refresh_metro:start()

  clock.run(function()
    for _ = 1, 50 do
      if engine and engine.osc1Wave then break end
      clock.sleep(0.1)
    end
    Ash.push_engine_state()
    apply_delay_from_bpm()
  end)

  delay_sync_clock_id = clock.run(function()
    while true do
      clock.sleep(60 / math.max(20, clk.bpm) / 4)
      apply_delay_from_bpm()
    end
  end)

  redraw()
end



function g.key(x, y, z)
  local grid_h = g.rows
  if z > 0 then
    if alt then
      if (grid_h == 8 and edit_ch == 1) or (grid_h == 16 and y <= 8) then
        if one.data[x] > 0 then toggle_loop_tie("one", x) end
      end
      if (grid_h == 8 and edit_ch == 2) or (grid_h == 16 and y > 8) then
        if two.data[x] > 0 then toggle_loop_tie("two", x) end
      end
    elseif (grid_h == 8 and edit_ch == 1) or (grid_h == 16 and y <= 8) then
      if one.data[x] == 9-y then
        set_loop_data("one", x, 0)
        set_loop_tie("one", x, 0)
      else
        set_loop_data("one", x, 9-y)
      end
    elseif (grid_h == 8 and edit_ch == 2) or (grid_h == 16 and y > 8) then
      if grid_h == 16 then y = y - 8 end
      if two.data[x] == 9-y then
        set_loop_data("two", x, 0)
        set_loop_tie("two", x, 0)
      else
        set_loop_data("two", x, 9-y)
      end
    end
    gridredraw()
    redraw()
  end
end

local function grid_draw_channel(loop, y_offset)
  for x = 1, 16 do
    if loop.data[x] > 0 and loop.tie[x] == 1 then
      local y = grid_pitch_row(loop.data[x]) + y_offset
      for row = 1, 8 do
        local grid_y = row + y_offset
        g:led(x, grid_y, grid_y == y and 0 or 2)
      end
    end
  end
  for x = 1, 16 do
    if loop.data[x] > 0 and loop.tie[x] ~= 1 then
      g:led(x, grid_pitch_row(loop.data[x]) + y_offset, 5)
    end
  end
  if loop.pos > 0 and loop.data[loop.pos] > 0 then
    g:led(loop.pos, grid_pitch_row(loop.data[loop.pos]) + y_offset, 15)
  else
    g:led(loop.pos, 1 + y_offset, 3)
  end
end

function gridredraw()
  local grid_h = g.rows
  g:all(0)
  if edit_ch == 1 or grid_h == 16 then
    grid_draw_channel(one, 0)
  end
  if edit_ch == 2 or grid_h == 16 then
    grid_draw_channel(two, grid_h == 16 and 8 or 0)
  end
  g:refresh()
end

function enc(n, delta)
  if n==1 then
    mode = util.clamp(mode+delta,1,4)
  elseif mode == 1 then --step
    if n==2 then
      if alt then
        params:delta("probability", delta)
      else
        local p = (edit_ch == 1) and one.length or two.length
        edit_pos = util.clamp(edit_pos+delta,1,p)
      end
    elseif n==3 then
      if edit_ch == 1 then
        params:delta("one_data_"..edit_pos, delta)
      else
        params:delta("two_data_"..edit_pos, delta)
      end
    end
  elseif mode == 2 then --loop
    if n==2 then
      params:delta("one_length", delta)
    elseif n==3 then
      params:delta("two_length", delta)
    end
  elseif mode == 3 then --sound
    if n==2 then
      params:delta(snd_params[snd_sel], delta)
    elseif n==3 then
      params:delta(snd_params[snd_sel+1], delta)
    end
  elseif mode == 4 then --option
    if n==2 then
      if alt==false then
        params:delta("bpm", delta)
      else
        params:delta("step_length",delta)
      end
    elseif n==3 then
      if alt==false then
        params:delta("root_note", delta)
      else
        params:delta("scale_mode", delta)
      end
    end
  end
  redraw()
end

function key(n,z)
  if n==1 then
    alt = z==1

  elseif mode == 1 then --step
    if n==2 and z==1 then
      if not alt==true then
        if edit_ch == 1 then
          edit_ch = 2
          if edit_pos > two.length then edit_pos = two.length end
        else
          edit_ch = 1
          if edit_pos > one.length then edit_pos = one.length end
        end
      else
        for i=1,one.length do
          params:set("one_data_"..i, 0)
          params:set("one_tie_"..i, 0)
        end
        for i=1,two.length do
          params:set("two_data_"..i, 0)
          params:set("two_tie_"..i, 0)
        end

      end
    elseif n==3 and z==1 then
      if not alt==true then
        if edit_ch == 1 then morph(one, "one") else morph(two, "two") end
      else
        random()
        gridredraw()
      end
    end
  elseif mode == 2 then --loop
    if n==2 and z==1 then
      one.pos = 0
      two.pos = 0
      if alt==true then clk:reset() end
    elseif n==3 and z==1 then
      one.pos = math.floor(math.random()*one.length)
      two.pos = math.floor(math.random()*two.length)
    end
  elseif mode == 3 then --sound
    if n==2 and z==1 then
      snd_sel = util.clamp(snd_sel - 2,1,NUM_SND_PARAMS-1)
    elseif n==3 and z==1 then
      snd_sel = util.clamp(snd_sel + 2,1,NUM_SND_PARAMS-1)
    end
  elseif mode == 4 then --option
    if n==2 then
    elseif n==3 then
    end
  end

  redraw()
end

function redraw()
  screen.clear()
  screen.line_width(1)
  screen.aa(0)
  if mode==1 then
    screen.move(26 + edit_pos*6, edit_ch==1 and 33 or 63)
    screen.line_rel(4,0)
    screen.level(15)
    if alt then
      screen.move(0, 22)
      screen.level(1)
      screen.text("tie")
      screen.move(0, 30)
      screen.level(1)
      screen.text("prob")
      screen.move(0, 45)
      screen.level(15)
      screen.text(params:get("probability"))
    end
    screen.stroke()
  end
  screen.move(32,30)
  screen.line_rel(one.length*6-2,0)
  screen.move(32,60)
  screen.line_rel(two.length*6-2,0)
  screen.level(mode==2 and 6 or 1)
  screen.stroke()

  local function screen_draw_track(loop, baseline_y, length, ch)
    local top_y = baseline_y - 24
    for i=1,length do
      if loop.data[i] > 0 and loop.tie[i] == 1 then
        local col_x = 28 + i*6
        local note_y = baseline_y - loop.data[i]*3
        screen.line_width(2)
        screen.level(i == loop.pos and 6 or 2)
        if note_y - 2 >= top_y then
          screen.move(col_x, top_y)
          screen.line_rel(0, note_y - top_y - 2)
          screen.stroke()
        end
        if note_y + 2 <= baseline_y then
          screen.move(col_x, note_y + 2)
          screen.line_rel(0, baseline_y - note_y - 2)
          screen.stroke()
        end
        screen.line_width(1)
      end
    end
    for i=1,length do
      if loop.data[i] > 0 and (loop.tie[i] ~= 1 or i == loop.pos) then
        local y = baseline_y - loop.data[i]*3
        screen.move(26 + i*6, y)
        screen.line_rel(4,0)
        if loop.tie[i] == 1 then
          screen.level(15)
        else
          screen.level(i == loop.pos and 15 or ((edit_ch == ch and loop.data[i] > 0) and 4 or (mode==2 and 6 or 1)))
        end
        screen.stroke()
      end
    end
  end

  screen_draw_track(one, 30, one.length, 1)
  screen_draw_track(two, 60, two.length, 2)

  screen.level(4)
  screen.move(0,10)
  screen.text(mode_names[mode])

  if mode==3 then
    screen.level(1)
    screen.move(0,30)
    screen.text(snd_names[snd_sel])
    screen.level(15)
    screen.move(0,40)
    screen.text(params:string(snd_params[snd_sel]))
    screen.level(1)
    screen.move(0,50)
    screen.text(snd_names[snd_sel+1])
    screen.level(15)
    screen.move(0,60)
    screen.text(params:string(snd_params[snd_sel+1]))
  elseif mode==4 then
    screen.level(1)
    screen.move(0,30)
    screen.text(alt==false and "bpm" or "div")
    screen.level(15)
    screen.move(0,40)
    screen.text(alt==false and params:get("bpm") or params:string("step_length")) 
    screen.level(1)
    screen.move(0,50)
    screen.text(alt==false and "root" or "scale")
    screen.level(15)
    screen.move(0,60)
    screen.text(alt==false and params:string("root_note") or params:string("scale_mode"))
  end

  screen.update()
  screen.ping()
end

function cleanup()
  clk:stop()
  if delay_sync_clock_id then
    clock.cancel(delay_sync_clock_id)
    delay_sync_clock_id = nil
  end
  if screen_refresh_metro then
    screen_refresh_metro:stop()
    screen_refresh_metro = nil
  end
  if engine and engine.noteKillAll then engine.noteKillAll() end
end
