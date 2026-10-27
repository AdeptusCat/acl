# Weapon audio levels

All 20 authored weapon definitions use calibrated playback gains for their
existing audio assets. Firing and explosive impacts target **−20 LUFS maximum
momentary loudness**; automatic burst tails target **−24 LUFS**. A tail is four
decibels below the firing body so it does not jump out when firing stops.

## Findings and changes

The previous firing levels spanned 24.6 dB: approximately −2.9 LUFS for MG34
loops versus −27.5 LUFS for fallback rifles. Rifle shots ignored `volume_db`
and always played at −6 dB. Rifle-grenade launches and impacts received a fixed
+6 dB boost. Some decoded peaks consequently exceeded 0 dBFS, even before mixing
multiple weapons. Loop tails used fixed zero gain regardless of their source
level, giving a particularly quiet M3 tail compared with other automatic weapons.

`volume_db` now controls the absolute gain of both muzzle one-shots and automatic
loops. Independent `decay_volume_db`, `hit_volume_db`,
`riflegrenade_shot_volume_db` and `riflegrenade_hit_volume_db` settings calibrate
the other audio events. The shared rifle sound is calibrated in the default
WeaponSpec, as well as its authored users.

Automatic loop players were also offset by the unit position while already
parented to that unit. They now use zero local offset, placing the sound at the
firing unit and making distance attenuation comparable with muzzle one-shots.

## Firing calibration

Every firing entry below now measures −20.0 LUFS at the meter's 0.1 LU resolution,
before spatial attenuation, random pitch variation and bus/master settings.
These are loudness measurements of the audible event, not rounds-per-minute
averages or a promise that different timbres sound identical.

| Weapon | Previous firing level, LUFS | New playback gain, dB |
| --- | ---: | ---: |
| Kar98k, including grenade-capable rifle fire | −13.5 | −12.5 |
| M1 Garand | −17.4 | −8.6 |
| M1 Carbine | −17.1 | −8.9 |
| Enfield / Springfield, including grenade-capable rifle fire | −27.5 | +1.5 |
| MG34, both mounts | −2.9 | −13.1 |
| M1919A4 | −5.9 | −17.1 |
| BAR | −8.0 | −15.0 |
| MP40 | −8.3 | −11.7 |
| M3 Grease Gun | −4.5 | −15.5 |
| Bazooka / Panzerschreck | −14.4 | −11.6 |
| All four mortars | −11.0 | −15.0 |
| Rifle-grenade launch | −7.1 | −6.9 |

Both rifle-grenade weapons use −10.6 dB for their explosive impacts, as do the
mortars and offboard 105 mm HE using the same explosion asset. Bazooka and
Panzerschreck impacts use −14.0 dB for their separate asset. These all measure
−20.0 LUFS after calibration.

Tail gains are −14.2 dB for MG34, −13.7 dB for BAR and M1919A4, −7.1 dB for MP40,
and +3.4 dB for M3. Each measures −24.0 LUFS. The highest individual true peak
after calibration is −4.2 dBTP, in the M3 tail. Simultaneous weapons still add
in the mix; this is per-event calibration, not a master limiter.

## Reproduce the measurements

Run with FFmpeg installed:

```bash
python3 tools/audio/analyze_weapon_levels.py --output /tmp/weapon-levels.csv --check
```

The analyzer reads the authored weapon definitions, their current gains and
fallback sounds from the WeaponAudio scene. It measures all referenced audio
using FFmpeg's EBU R128 scanner with true-peak detection. Mono files are measured
as dual mono. Imported loops repeat for four seconds; one-shots play once with
silence padding so even very short samples receive a complete 400 ms window.
The loudest 400 ms window prevents quiet tails and silence from making a loud
gunshot appear artificially quiet. Original recordings are retained.

The tool decodes each asset again with its actual playback gain and writes a
report. `--check` requires each event within 1 LU of its role's target and true
peaks no higher than −3 dBTP. The checked-in
[measurement report](weapon_audio_levels.csv) contains all 36 events, including
shared assets and fallback rifles.

The weapon audio regression scene checks gain routing for every authored weapon,
including normal versus grenade fire, explosive impacts, independent tails and
correct loop position. It also retains the existing burst lifecycle checks.
