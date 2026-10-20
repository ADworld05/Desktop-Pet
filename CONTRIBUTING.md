# Contributing

Start with README.md and BUILDING.md. Keep ordinary pet behavior and permissions predictable; make focused changes with evidence for the behavior they affect.

- Run `python scripts/check_source.py` before preparing a commit.
- Build with the supported Windows toolchain, then run `python scripts/run_tests.py --godot <your-godot-executable>`. See BUILDING.md for interactive Windows checks.
- Report application/Windows/Ollama/model versions and reproduction steps for issues.
- Redact personal paths, chat history and memory from screenshots/logs. Never upload credentials, signing keys or model weights.
- Keep third-party attribution and notices. Original code contributions should be compatible with the project MIT license; do not relicense bundled assets.
- Do not change defaults, permissions or model storage silently. Existing user data must survive updates/uninstall unless the user explicitly requests its removal.

Helpful areas include compatibility reports, accessibility, CI and measured performance improvements. Opening a pull request does not require uploading personal data.
