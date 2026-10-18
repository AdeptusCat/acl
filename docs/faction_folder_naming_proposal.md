# Faction folder naming convention

Status: implemented on 6 October 2026 after authorization to execute the proposal. Five content directories were renamed, with 40 primary files and 13 import companions moved. See the [manifest](faction_folder_refactor_manifest.json) for exact paths, hashes, preserved UIDs, and compatibility redirects.

## Convention

Use full English country names in lowercase `snake_case` as the folder identifier for country-specific content. Use the same identifier in every resource and asset category.

| Content identity | Folder identifier |
| --- | --- |
| Germany | `germany` |
| United States | `united_states` |

This replaces the current mix of a nationality adjective (`german`), a country name (`germany`), and abbreviations (`ger`, `us`) with one rule. Future country folders follow the same rule, for example `united_kingdom`. Display labels can contain spaces and capitalization.

Keep the established category-first layout:

```text
resources/
  soldiers/
    germany/
    united_states/
  squads/
    germany/
    united_states/
assets/
  status/
    germany/
    united_states/
```

Retain shared definitions outside country folders where they already belong. Files inside a country folder can use role names such as `rifle_squad.tres`; they do not need to repeat the country. Any separate basename cleanup should have its own manifest.

## Implemented directory mapping

Paths below are relative to the project root.

| Previous content folder | Canonical content folder | Primary files | Import companions |
| --- | --- | --- | --- |
| `resources/soldiers/germany/` | Retain | 11 | 0 |
| `resources/soldiers/us/` | `resources/soldiers/united_states/` | 11 | 0 |
| `resources/squads/german/` | `resources/squads/germany/` | 8 | 0 |
| `resources/squads/us/` | `resources/squads/united_states/` | 8 | 0 |
| `assets/status/ger/` | `assets/status/germany/` | 7 | 7 |
| `assets/status/us/` | `assets/status/united_states/` | 6 | 6 |

The five directory moves preserve image bytes, resource values, and original UIDs. Import source paths and generated cache paths now match the canonical folders. The existing German soldier folder already matched the convention. Image basenames such as `idle_ger.png` and `idle_us.png`, including those outside country folders, remain unchanged.

The old resource directories remain only for 27 small `.tres.remap` files that redirect legacy loads to the canonical definitions. A match generated before the moves contained faction resource paths without UIDs, so these redirects are required for backward compatibility. Retain them while supporting saves or external references containing the old paths. Current project references use the canonical folders.

Godot's default export omits these manual redirects, and including them alone does not resolve the additional redirect created by binary resource conversion. The project-owned `addons/faction_resource_compatibility/` export plugin therefore packages the current canonical definitions at the legacy paths. It uses the manifest's compatibility mapping, adds no gameplay behavior, and preserves the existing export preset settings. Keep the enabled plugin alongside the redirects while old paths are supported.

## Existing identifiers

`Globals.Team` uses `AXIS` and `ALLIES`; these identify game sides. Country folders identify the authored content. Renaming directories does not require changing those enum values or save fields.

`RankGrades.TITLES` uses the existing keys `DE`, `US`, `UK`, and `SU`. Preserve that API during a folder migration. A future runtime faction-identity design can explicitly map country identifiers to existing rank keys, without inferring a country from directory names at runtime.

Keep `resources/weapons/` and `scenes/game/units/unit.tscn` at their current paths: saves already retain those paths as strings. The five compatibility scripts from the organization refactor also remain in place.

## Migration and verification procedure

1. Create a separate manifest for the five directory moves, including every resource, image, and import companion. Preserve resource and imported-asset UIDs.
2. Update `.tres`, `.tscn`, and import source references to the new paths. Check for generated paths and external references instead of assuming all references use UIDs.
3. Verify saves created before the folder changes. If an old save retains a moved resource path without a usable UID, provide an explicit compatibility mapping or redirect. Do not rewrite the existing legacy fixtures to make tests pass.
4. Run a fresh import in an isolated copy, verify both faction catalogs and soldier definitions, and inspect both factions' battlefield textures and status icons.
5. Run roster, weapon-save, legacy-save compatibility, objective-visibility, and broader systems regressions. Audit the actual workspace after any editor import because stale caches previously caused unintended resource rewrites.

## Results

| Check | Result |
| --- | --- |
| Unchanged baseline, including startup variants and fresh-process persistence verification | 17/17 regression runs passed |
| Final suite, including the new faction-save compatibility regression | 18/18 regression runs passed |
| Parser and convention checks under the existing phased-controller exclusion | 150 scripts, zero failures or violations |
| Project-owned export plugin | Both editor scripts compiled and passed separate convention checks |
| Legacy resource redirects and UID resolution | All 27 moved resource definitions resolve at both old and canonical paths with the original UIDs |
| Imported faction textures and battlefield view bindings | All 13 textures load, retain their original UIDs, and remain bound in the battlefield view |
| Fresh isolated import and workspace index refresh | Passed; workspace import introduced no unintended file changes |
| Default Map and Orchard Road integration checks | Zero assertion failures before and after the migration |
| Web-preset data-package export and isolated package runtime | All 27 legacy definitions and 13 textures load with their original UID mappings; faction and script-path save compatibility regressions pass |

The new `tests/faction_save_compatibility_regression.tscn` loads the unchanged pre-move fixture `tests/fixtures/legacy_faction_match.tres`. It checks raw legacy paths directly, canonical team catalogs, both saved faction rosters, a direct legacy soldier reference, original weapons without fallback, and saving/loading the match again. Direct path checks also run from the exported package, where the fixture itself may be converted to binary.

Each map integration check ran 600 process frames at fixed FPS 60 and exercised startup, unit details, command controls, overlays, countdown/results, and LOS bake/reload. Default Map produced no script errors. Orchard Road reproduced the same four existing defense-order `follow_cube_path` calls on `Nil` seen in the baseline. Missing debug-match data and shutdown warnings also remain baseline diagnostics. These existing issues are outside the faction-folder migration.

No interactive visual inspection, browser run, or executable build was performed. The exported data package was tested with the headless runtime from an empty directory, without source-project fallback. Image bytes and headless texture bindings were verified. Gameplay scripts, team and rank identifiers, weapon paths, loadout values, the saved unit-scene path, and the existing five script compatibility wrappers are preserved. The project registers the new export plugin; existing third-party addons and export presets remain unchanged.
