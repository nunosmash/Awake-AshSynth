# awake-ashsynth

![awake-ashsynth on norns](https://raw.githubusercontent.com/nunosmash/Awake-AshSynth/main/awake-ashsynth.png)

**Demo:** [Demo](https://youtu.be/Gphk6wk1QOY)

A norns script that pairs the **Awake sequencer** with the **AshSynth engine**.  
It follows the same sequencing structure as `awake-passersby`, but uses the **Ash** engine instead of Passersby.

---

## Overview

Awake uses **two overlapping sequencers**:

| Layer | Role |
|-------|------|
| **Top (one)** | Melody. Sound only triggers when this layer has a note |
| **Bottom (two)** | Pitch offset. **Added** to the top layer to set the final pitch |

```
final pitch = scale[ one[step] + two[step] ]
```

A bottom value of `0` is not a rest — it means **offset 0**. If the top layer has a note, sound still plays even when the bottom is `0`.

---

## Requirements

- norns
- **ashsynth** must also be installed (`ashsynth/lib/Engine_Ash.sc`)
- The SuperCollider engine file should live in **ashsynth only**. A separate `Engine_Ash.sc` inside `awake-ashsynth` will cause duplicate engine errors
- Grid (optional): monome grid or **toga** integration
- `lib/ash_engine.lua` and `lib/beatclock-crow.lua` are included in this script

### Installation

```
norns/dust/code/awake-ashsynth/   ← this script
norns/dust/code/ashsynth/         ← Ash engine (required)
norns/dust/data/awake-ashsynth/   ← presets & pmap
```

---

## Engine / Sound

- **Engine**: `engine.name = "Ash"` — same as ashsynth
- **Parameters**: `lib/ash_engine.lua` — same Ash parameter set as ashsynth
- **MIDI CC map**: `data/awake-ashsynth/awake-ashsynth.pmap` — same as ashsynth pmap (ch 5)
- **Differences from ashsynth**
  - No awake halfsecond (softcut) delay loop — direct engine output
  - `noteOff` → `noteOn` each step to retrigger ADSR (sequencer behavior)
  - **TIE** support for legato / glide between steps
  - SOUND mode shortcuts: cutoff, reso, drive, reverb, delay, fdbk

---

## Controls

**E1** cycles modes: `STEP` → `LOOP` → `SOUND` → `OPTION`  
**K1** hold = **alt**

### STEP

| Input | Action |
|-------|--------|
| E2 | Move edit position |
| E3 | Change note value (current channel: one / two) |
| K2 | Switch one ↔ two channel |
| K2 + alt | Clear entire pattern (including TIE) |
| K3 | Morph (current channel) |
| K3 + alt | Random (resets TIE) |
| E2 + alt | Probability |

### LOOP

| Input | Action |
|-------|--------|
| E2 | Top loop length |
| E3 | Bottom loop length |
| K2 | Reset playhead |
| K2 + alt | Reset clock |
| K3 | Random jump |

### SOUND

| Input | Action |
|-------|--------|
| K2 / K3 | Select parameter pair |
| E2 / E3 | Adjust selected Ash parameters |

Shortcuts: **cutoff**, **reso**, **drive**, **reverb**, **delay**, **fdbk**

### OPTION

| Input | Action |
|-------|--------|
| E2 | BPM |
| E3 | Root note |
| E2 + alt | Step length |
| E3 + alt | Scale |

---

## Grid (toga / monome)

### Note editing

- **Top 8 rows** (or upper half of a 16-row grid): `one` pattern
- **Bottom 8 rows** (or lower half of a 16-row grid): `two` pattern
- Press a step (column) to toggle a note. Press again to delete

On an 8-row grid, use K2 to switch between one / two.

### TIE (legato)

**K1 + press step (column)** → toggle TIE on that step (only if a note exists)

| Display | Meaning |
|---------|---------|
| **Grid** | That step's **column** fills dimly; the **note cell stays off** |
| **norns screen** | A dim **vertical line** at that step; the note bar stays dark |
| **During playback** | Current step is highlighted brightly |

A tied step **legs into the next step** (`noteOff` is skipped).

- **Top TIE**: melody continues into the next step
- **Bottom TIE**: offset change continues into the next step (legato works even if bottom goes to `0`)
- Sound only plays when the **top layer has a note**

Deleting a note / alt+K2 clear / random also clears TIE.

---

## Glide

Uses the Ash engine glide, synced with the sequencer. Adjust via params, SOUND mode, or MIDI CC.

| Glide Mode | Behavior |
|------------|----------|
| **All** | Glide on every step |
| **Legato** | Glide only on TIE-connected steps |

Without TIE, each step sends `noteOff` → `noteOn`, so every note is the same length.  
For **legato glide**, use TIE + **Glide Mode: Legato** + raise the glide amount.

### Example

```
Top (one):    ● ● ● ●   (same note, no TIE)
Bottom (two): 2 → 5     (TIE ON at step 2)

→ pitch glides from one+2 to one+5
```

---

## MIDI

### Output

params **output**: audio / midi / audio+midi / crow, etc.

### CC (built-in)

| CC | Parameter |
|----|-----------|
| 1 | lp_env_amount |
| 7 | drive |
| 71 | lp_resonance |
| 74 | lp_cutoff |

Additional CC mapping via `cc_num_1`–`cc_num_4` and `cc_assign_1`–`cc_assign_4`.

### pmap (ch 5)

| CC | Parameter |
|----|-----------|
| 30 | lp_cutoff |
| 31 | filter_attack |
| 32 | lp_resonance |
| 33 | filter_sustain |
| 34 | drive |
| 35 | filter_decay |
| 36 | lfo_master |
| 37 | filter_release |
| 38 | fm_amount |
| 39 | glide |
| 40 | lp_env_amount |

File: `data/awake-ashsynth/awake-ashsynth.pmap`

---

## Presets

Load with MIDI **Program Change (PC 0–15)**.

```
data/awake-ashsynth/awake-ashsynth-01.pset
data/awake-ashsynth/awake-ashsynth-02.pset
...
```

Presets include:

- one / two pattern data (`one_data_*`, `two_data_*`)
- TIE state (`one_tie_*`, `two_tie_*`)
- Loop lengths, BPM, scale, Ash engine parameters

Older presets saved without TIE load with all ties off.

---

## vs. awake-passersby

| | awake-passersby | awake-ashsynth |
|--|-----------------|----------------|
| Engine | Passersby | **Ash** (ashsynth) |
| Delay | halfsecond softcut | Engine delay only |
| SOUND shortcuts | filter, resonance, lfo rate, lfo depth, delay, delay fb | cutoff, reso, drive, reverb, delay, fdbk |
| TIE / legato | No | **Yes** |
| Sequencer / UI / grid | Same | Same |

---

## File structure

```
awake-ashsynth/
├── awake-ashsynth.lua      # main script
├── README.md
└── lib/
    ├── ash_engine.lua      # Ash params & engine bridge
    └── beatclock-crow.lua  # clock

data/awake-ashsynth/
├── awake-ashsynth.pmap
└── awake-ashsynth-XX.pset
```

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.  
See [LICENSE](LICENSE) for the full text.

### Third-party components

| Component | License | Notes |
|-----------|---------|-------|
| [awake](https://github.com/tehn/awake) | GPL-3.0 (norns ecosystem) | Sequencer structure & UI |
| [awake-passersby](https://github.com/nattog/awake-passersby) | GPL-3.0 | Direct basis for this script |
| [passersby](https://github.com/markwheeler/passersby) | GPL-3.0 | awake-passersby engine reference |
| [ashsynth](https://github.com/nunosmash/ashsynth) | Apache 2.0 | `lib/ash_engine.lua`; requires `Engine_Ash.sc` from ashsynth |

`lib/ash_engine.lua` is derived from ashsynth (Apache 2.0) and is included in this GPL-3.0 distribution per Apache–GPL compatibility.

---

## Credits

- Awake sequencer: [@tehn](https://github.com/tehn)
- Based on [awake-passersby](https://github.com/nattog/awake-passersby) / [awake](https://github.com/tehn/awake)
- Ash engine: [ashsynth](https://github.com/nunosmash/ashsynth)
