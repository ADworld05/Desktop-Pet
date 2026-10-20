"""Run packaging tests and source/export regressions with fresh isolated profiles."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from build_windows import ROOT, VERSION, RUNTIME


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--app-dir", type=Path, default=ROOT / "dist" / VERSION / "DesktopPet")
    parser.add_argument("--taskbar", action="store_true", help="Also open isolated native test windows")
    args = parser.parse_args()
    godot = Path(shutil.which(args.godot) or args.godot).resolve()
    app = args.app_dir.resolve()
    if not godot.is_file() or not all((app / n).is_file() for n in RUNTIME):
        parser.error("Select Godot and build the complete application first.")
    build = ROOT / ".build"
    build.mkdir(exist_ok=True)
    evidence = Path(tempfile.mkdtemp(prefix="DesktopPetTests-", dir=build))
    runner = evidence / "Runner"
    runner.mkdir()
    runner_godot = godot
    if godot.name.endswith("_console.exe"):
        runner_godot = godot.with_name(godot.name.replace("_console.exe", ".exe"))
        if not runner_godot.is_file():
            parser.error("The Godot console wrapper needs its matching editor executable beside it.")
    shutil.copy2(runner_godot, runner / "TestRunner.exe")
    for dll in app.glob("*.dll"):
        shutil.copy2(dll, runner / dll.name)
    results = {}
    with (evidence / "packaging.log").open("w", encoding="utf-8") as log:
        unit = subprocess.run([os.sys.executable, "-m", "unittest", "discover", "-s", "tests",
                               "-p", "test_*.py", "-v"], cwd=ROOT, stdout=log,
                              stderr=subprocess.STDOUT, timeout=60)
    if unit.returncode:
        raise RuntimeError(f"Packaging tests failed; see {evidence}")
    cases = [("source", "regression.gd", False), ("packed", "regression.gd", False)]
    if args.taskbar:
        cases.append(("taskbar", "taskbar.gd", True))
    for label, script, graphical in cases:
        env = os.environ.copy()
        for key, leaf in [("APPDATA", "Roaming"), ("LOCALAPPDATA", "Local")]:
            folder = evidence / label / leaf
            folder.mkdir(parents=True)
            env[key] = str(folder)
        command = [str(godot if label == "source" else runner / "TestRunner.exe")]
        if not graphical:
            command.append("--headless")
        command += ["--path", str(ROOT / "Source/Godot")]
        if label != "source":
            command += ["--main-pack", str(app / "DesktopFox.pck")]
        command += ["--script", str(ROOT / "tests" / script)]
        if graphical:
            command += ["--", "--t13-validation"]
        log_path = evidence / (label + ".log")
        with log_path.open("w", encoding="utf-8") as log:
            result = subprocess.run(command, env=env, cwd=ROOT, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=90)
        text = log_path.read_text(encoding="utf-8", errors="replace")
        if result.returncode or "SCRIPT ERROR" in text:
            raise RuntimeError(f"{label} failed; see {log_path}")
        filename = "taskbar_checks.json" if graphical else "checks.json"
        rows = json.loads((evidence / label / "Roaming" / filename).read_text(encoding="utf-8"))
        if len(rows) != (14 if graphical else 54) or not all(row["pass"] for row in rows):
            raise RuntimeError(f"{label} failed; inspect {filename}")
        results[label] = len(rows)
        print(f"{label}: {len(rows)} checks passed", flush=True)
    (evidence / "summary.json").write_text(json.dumps({
        "packaging_tests": "passed", "checks": results,
        "profile_scope": "fresh test-owned directories only",
    }, indent=2) + "\n", encoding="utf-8")
    print("Tests passed; evidence: " + str(evidence))


if __name__ == "__main__":
    main()
