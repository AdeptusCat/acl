# Faction resource export compatibility

This project-owned editor plugin preserves old faction resource paths in exported packages. Development loads use the `.tres.remap` files retained at those old paths.

Godot's normal export omits manual `.remap` files. Merely including them also fails when their targets have been converted to binary and require another remap. At export time, this plugin reads `docs/faction_folder_refactor_manifest.json` and packages each canonical resource's current contents at its legacy path. Internal references continue to use the current canonical paths.

Keep the plugin enabled while the project's old faction resource paths remain supported. Update the manifest's `compatibility_resources` mapping if a canonical resource moves again. This plugin does not run during gameplay and does not change existing export preset settings.

Validation includes a Web-preset data-package export, loading every legacy alias from that package in an empty directory, checking canonical resource/texture UID resolution, and running the faction and script-path save compatibility regressions from the package.
