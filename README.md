# Desktop Pet

An animated desktop companion for Windows, with optional local AI chat through Ollama.

<p align="center"><img src="docs/images/desktop-fox.png" width="260" alt="The Desktop Pet fox"></p>

The pet watches your cursor, follows when you hold and move away, and rests when left alone. Click it to open a compact chat popup, or expand the popup into a full conversation window.

Created by **Abir Dutta** ([ADworld05](https://github.com/ADworld05)). Original project code is MIT licensed. The fox model is by **pxltiger**, with separate attribution and license notices.

**Status:** Windows x64 release candidate **1.0.0-rc.8**. Source and [release downloads](https://github.com/ADworld05/Desktop-Pet/releases/tag/v1.0.0-rc.8) are public. Binaries are unsigned; native glass effects depend on Windows and graphics support.

## Get started

Download the installer or portable ZIP from [the rc.8 release](https://github.com/ADworld05/Desktop-Pet/releases/tag/v1.0.0-rc.8).

- **Installer:** exit any running pet through its tray menu, open `DesktopPet_Setup.exe`, choose **Install / Update**, then **Open installed pet**.
- **Portable:** extract the entire `DesktopPet_Portable.zip` and run `DesktopPet.exe` inside the extracted folder. Keep its supplied files together.
- **From source:** follow [BUILDING.md](BUILDING.md).

The pet stays out of the taskbar by default. Use its system-tray icon, including the hidden-icons panel, for Show, Hide, Restore input and Exit. Chat and Settings remain normal desktop windows. Windows controls where the tray icon appears.

## Everyday controls

| Action | Result |
|---|---|
| Move the cursor near the pet | Eye and head tracking |
| Click its body | Open compact chat; click again to dismiss |
| Double-click | Jump and sit |
| Hold for about a second, then move away | Lead the pet toward the cursor |
| Release after following | Finish the current trip and settle |
| Right-click | Open the pet menu |

Settings contains gesture, movement, sound, permission and threshold controls. The [usage guide](docs/USAGE.md) explains follow timing, rest/sleep, glass settings, data import/export and troubleshooting.

![Compact chat](docs/images/compact-chat.png)

## Local AI setup

The pet works without AI. Chat needs a separately installed [Ollama runtime](https://ollama.com/download) and at least one compatible local model. Install Ollama, start it, then open **Chat → Local AI → Refresh / Retry**.

You can install a model by tag in Model Manager, or use a terminal:

```powershell
ollama pull qwen3:1.7b
ollama list
```

Refresh the list in Desktop Pet, select the model and send a question. Downloads need internet access; supported local inference uses your loopback Ollama service without a cloud API key or automatic cloud fallback.

| Category | Suggested model |
|---|---|
| FAST, default | `qwen3:1.7b` |
| BALANCED | `qwen3:4b` |
| SLOW, manual selection | `qwen3:8b` |
| ALTERNATIVE | `gemma3:4b` |

One compatible model is enough. Installed models are detected dynamically; the app does not bundle or silently move their weights. RAM use and response time depend on the model, quantization and context. The default context is 4K tokens, with one generation at a time.

## Chats, memory and privacy

Past chats are saved locally. Memory stores notes you explicitly add or ask the pet to remember; you can inspect, edit, export and import them. Closing the pet starts a fresh conversation next time while retaining saved history and notes.

- General data: `%APPDATA%\DesktopFox`.
- Machine-specific model settings and permissions: `%LOCALAPPDATA%\DesktopFox\Config`.
- Model weights: Ollama’s configured model directory.

These files are **not encrypted**. Uninstall preserves saved data and model weights. The old `DesktopFox` data and internal filenames remain for compatibility; the visible product name is Desktop Pet.

Windows actions use explicit folder/application permissions and a fixed reviewed action set. The model cannot grant itself access or execute arbitrary shell commands. See the [usage guide](docs/USAGE.md) for those controls and [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## Requirements and development

Windows x64 with graphics drivers supporting OpenGL 3.3; tested on Windows 11. Other hardware, display scales and glass composition can behave differently. Packaged use needs no Godot, Blender or Python. AI model memory requirements are separate from pet-only use.

Source builds use Godot 4.7.2 Standard, matching Windows export templates, Python and x86_64 MinGW-w64. [BUILDING.md](BUILDING.md) covers builds, regression tests, the manual CI workflow and signing. [CONTRIBUTING.md](CONTRIBUTING.md) covers changes and bug reports.

## License and credits

Original code and documentation: [MIT](LICENSE), copyright **2026 Abir Dutta**. The supplied **Fox** model and original animations are by **pxltiger**, under CC BY 4.0 identified in the supplied asset metadata. Keep the [asset attribution](Notices/Fox-Attribution.md) and [third-party notices](THIRD_PARTY_NOTICES.md). Ollama and model weights are installed and licensed separately. [AUTHORS.md](AUTHORS.md) records project credits and AI coding assistance.
