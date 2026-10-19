# Building Desktop Pet on Windows

Packaged users do not need development tools. The local builder uses existing tools and never downloads software, templates or AI models.

## Prerequisites

- Windows x64 and Python 3.10 or newer on PATH.
- Godot **4.7.2 Standard** and its matching Windows x64 export templates. The C# edition is not required.
- **x86_64 MinGW-w64 GCC**, Windows headers/libraries and `windres` from the same toolchain.
- The included runtime assets and notices. Blender is not needed for this runtime build.

## Build

From the repository root:

```powershell
python scripts/check_source.py
python scripts/build_windows.py --godot godot --cc gcc --templates "<matching template folder>" --installer
```

Replace the template placeholder with the existing directory containing `windows_release_x86_64.exe`. Pass full executable paths for `--godot` and `--cc` when they are not on PATH. `windres.exe` is found beside GCC, or selected with `--windres`. Omit `--installer` for only the portable package. A self-contained Godot installation can also find its own templates without `--templates`.

The builder checks Godot/compiler versions, builds four DLLs and two helpers, imports/exports the application, includes notices and creates inventories/hashes. For setup it copies installer sources into an isolated build project, embeds the verified payload, compiles shortcuts/resources/bootstrap, and verifies the embedded bundle using extraction-only `/verify`. It does **not** install, launch the pet, register an uninstaller or modify shared Ollama settings.

```text
dist/1.0.0-rc.7/
├── DesktopPet/                  # Run DesktopPet.exe here
├── DesktopPet_Portable.zip
└── DesktopPet_Setup.exe         # With --installer
.build/
├── logs/                        # Compiler/import/export diagnostics
├── Installer/                   # Generated payload and finite setup bundle
└── build_result.json            # Hashes and validation scope
```

Build profiles stay inside `.build`; normal use retains ordinary Windows user-data locations. Outputs are unsigned **review candidates**, not automatically published releases. Tool versions, timestamps and resources can affect binary hashes; the build is source-portable, not claimed bit-for-bit reproducible.

For editor development, build native bridges first, then import `Source/Godot/project.godot`. Main scene: `scenes/DesktopFox.tscn`. Optional historical proof fixtures and Blender authoring inputs are not distributed; see `Source/Blender/README.md`.

## Product naming and compatibility

Visible product labels and new archives use **Desktop Pet**. Internal `DesktopFox.exe`, `DesktopFox.pck`, native `fox_*` bridges, schemas, shortcut ownership filenames and `%APPDATA%/DesktopFox` / `%LOCALAPPDATA%/DesktopFox` remain compatible with existing installs. Do not rename these separately: title allowlists, launchers, setup ownership checks and data paths must agree. Existing custom pet names are preserved. The supplied animal remains a fox; the original asset's credited title is unchanged.

## CI draft

`.github/workflows/windows-review.yml` is a **manual-only draft**. It requires a dedicated trusted Windows x64 self-hosted runner labelled `desktop-pet-build` with the above tools and Python installed. Supply the runner's actual tool/template paths when dispatching. It does not download tools, use signing secrets, create releases or run on untrusted pull requests. Action versions are pinned to verified commits. Do not attach a personal runner to arbitrary public contributions.

The workflow has **not** been run on GitHub. Local compilation/export, ZIP integrity and setup `/verify` are checked separately from interactive installation/update/uninstall and Windows UI appearance. A GitHub-hosted runner configuration remains future work.

On the development machine, Godot sometimes exits with Windows access-violation code `0xC0000005` after creating a fresh installer import cache. The builder retains that log and retries an import **once**, only for that exit code and without a script error. A repeated crash or script error fails the build. This is a recorded tooling limitation, not a certified engine fix.

## Signing and distribution

Keep generated binaries, private data, model weights and keys out of source commits. For public signing, choose a trusted certificate/service and complete its identity checks separately. Sign payload components before computing dependent hashes, assemble setup, sign outer setup last, regenerate distribution hashes and repeat lifecycle checks. Never replace published bytes under an old hash/version. No certificate has been purchased or signing performed.

Native integration is Windows-specific; there is no supported Linux/macOS runtime build.
