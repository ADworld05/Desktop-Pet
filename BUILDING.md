# Building Desktop Fox

Packaged users do not need these development tools. Use installer/portable assets from GitHub Releases when available.

## Toolchain

- Godot 4.7.2 Standard and matching Windows x64 export templates.
- A Windows C/MinGW toolchain for native DLLs, launchers and setup helpers; resource compiler for manifests/version resources.
- Python for existing packaging utilities.
- Blender 4.5.9 LTS only when editing/rebaking 3D assets. Existing runtime assets are under Source/Godot/runtime_assets.

## Current workflow and gaps

1. Review native build scripts under Source/Native and replace toolchain locations with your own installed compiler. Do not run paths copied from another computer.
2. Build the native bridges into Source/Godot/native and produce the launcher/startup helpers. Preserve their adjacent .gdextension descriptors.
3. With those dependencies available, import Source/Godot/project.godot in the matching Godot editor. The application entry scene is scenes/DesktopFox.tscn.
4. Review export_presets.cfg output paths; export the Windows Portable Release preset with required raw runtime assets. Keep engine/PCK/native DLLs/helpers together and expose DesktopPet.exe as the launcher.
5. Curate application assets/notices, generate checksums and installer payload.json/payload.zip, then export Installer/Source with matching native helpers. The self-extracting installer requires its checked bundle and version resources.
6. Verify the actual ZIP and standalone installer, plus isolated install/update/uninstall and user-data preservation. Signed builds require signatures before dependent payload hashes are generated and outer setup signing last.

This workflow has been used for the packaged build, but the prepared public source does not yet provide a portable end-to-end build command or a complete CI pipeline. Native scripts/export paths still need cleanup; original packaging utilities depend on additional build inputs and are not currently shipped as a ready fresh-clone recipe. No unverified command is offered as turnkey setup.

Contributions improving reproducible builds and CI are welcome. Preserve attribution and avoid publishing personal runtime data, model weights, caches, credentials or signing keys.
