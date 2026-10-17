# Display and HUD validation

The design resolution and minimum supported window are 1280 × 720. The project
uses `canvas_items`, `expand`, fractional scaling, and high-DPI support.
`DisplaySettings` owns the window mode, remembered windowed size, UI size, and
`user://display.cfg`. UI scaling applies to the battle HUD's CanvasLayer; camera
zoom remains independent. Secondary sections fold when the available HUD space
falls below 1100 units wide or 620 units tall. They can still be expanded.
The interface-size slider supports 50–150% in 1% increments and shows the current
percentage. Mouse drags preview the percentage and apply it on release, keeping
the slider stationary during the drag. Keyboard and wheel changes apply directly.

Run the automated matrix:

```sh
godot --headless --path . res://tests/display_layout_regression.tscn
```

The matrix covers all combinations of 50%, 75%, 83%, 100%, 125%, and 150% interface
size with:

| Shape | Output sizes |
| --- | --- |
| 16:9 | 1280×720, 1366×768, 1920×1080, 2560×1440, 3840×2160 |
| 16:10 | 1920×1200, 2560×1600 |
| Ultrawide | 2560×1080, 3440×1440 |

Checks cover panel bounds and separation, central battlefield space, scrollable
objectives, tooltips at all four corners, target hints, command wheel sectors,
stacked-unit picking, exact roster selection, settings input, and saved
preferences. Slider checks exercise mouse dragging, keyboard adjustment, saved
intermediate percentages, and range validation. Headless runs do not load or
overwrite player display preferences.

For rendered checks, use an isolated preferences directory:

```sh
XDG_DATA_HOME=/tmp/acl-display-qa godot --path . \
  res://tests/display_layout_regression.tscn -- --capture
```

Rendered runs save screenshots to `/tmp/acl-display-*.png` and additionally check
native fullscreen, window-size restoration, manual resizing, and the UI-size
slider. Sizes capped by the desktop are reported as skipped; the headless
matrix still checks those exact output sizes.

Inspect rendered text and transient panels at each supported size. Also verify
the actual game's detailed battlefield art and native high-DPI output on target
hardware. The automated fixture uses a small battlefield and does not simulate
monitor DPI changes.

Validation on 2026-10-17: 54 headless combinations passed 3,417 checks; 30 native
combinations plus native window controls passed 1,913 checks. The local desktop
capped 2560×1440, 3840×2160, 2560×1600, and 3440×1440 to 2560×1382. The HUD
regression passed 106 checks, and all 293 scripts passed parsing and convention
checks. The existing full-match fixture still reports resource leaks during
shutdown.
