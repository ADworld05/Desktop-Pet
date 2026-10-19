# Building Desktop Fox on Windows

Packaged users do not need development tools. This source package can build the portable application using existing local tools. It never downloads a compiler, editor, templates or AI model automatically.

## Prerequisites

- Windows x64 and Python 3.10 or newer.
- Godot **4.7.2 Standard**, with its matching Windows x64 export templates installed. The C# edition is not required.
- A working **x86_64 MinGW-w64 GCC** toolchain with Windows headers/libraries. A 32-bit GCC installation is rejected.
- The included `Source/Godot/runtime_assets` and `Notices` directories.

Blender is not needed for the runtime build. Historical Blender authoring scripts tied to external fixtures are not part of this runtime-source package; see `Source/Blender/README.md`.

## Check and build

From the repository root, with Godot and MinGW-w64 available on PATH:

```powershell
python scripts/check_source.py
python scripts/build_windows.py --godot godot --cc gcc
```

If your Godot executable has a different name or tools are not on PATH, pass their actual executable paths with `--godot` and `--cc`. The builder checks versions and compiler target before building. Install matching export templates through Godot first; an unavailable template is reported in the export log.

The builder compiles four Windows DLLs and launcher/startup helpers, imports the project, exports the **Windows Portable Release** preset, includes notices, writes hashes and produces:

```text
dist/
├── DesktopFox/                 # Run DesktopPet.exe here
└── DesktopFox_Portable.zip
.build/
├── logs/                       # Compiler/import/export diagnostics
└── build_result.json           # Output archive identity
```

All generated app/build files stay inside this checkout. Build-time AppData variables are process-local and point into `.build`; normal packaged use keeps its ordinary Windows user-data locations. The build does not launch the pet, install it, change shared Ollama settings or modify an existing installation.

For editor development, compile native bridges first, then import `Source/Godot/project.godot`. Main scene: `scenes/DesktopFox.tscn`. Do not invoke historical debug/proof command-line switches: their optional test fixtures are not distributed in this package.

## Installer and signing

Installer sources and current native setup/helper sources are included. The portable build command does **not** produce a standalone installer. Installer packaging must generate `payload.json` and `payload.zip` from the hashed application, export `Installer/Source`, generate the finite bundle header, compile setup resources/bootstrap, and assemble its embedded components. A portable end-to-end installer build script/CI remains to be added and validated.

Unsigned source builds are labelled review builds. For signing, sign payload components before dependent hashes are computed, assemble the installer, sign the outer setup last and retest extraction/lifecycle. Do not change previously published bytes while advertising old hashes.

## Validation scope

This source package's portable pipeline was compiled/exported with the pinned Godot version and a 64-bit MinGW-w64 toolchain. Its source and actual exported resource pack passed checks for required assets/39 animation entries, model policy, data paths and Memory callbacks. This does not certify all graphics drivers, hardware or installer lifecycle for a newly rebuilt package. Exercise the resulting application on your own Windows environment before publishing a release.

Native integration is Windows-specific. There is no supported Linux/macOS runtime build or automated public CI pipeline yet.
