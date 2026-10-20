"""Build an unsigned Windows candidate with existing tools and fresh staging."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.0.0-rc.8"
RUNTIME = (
    "DesktopPet.exe", "DesktopFox.exe", "DesktopFox.pck",
    "DesktopFoxStartup.exe", "fox_window.dll", "fox_chat_window.dll",
    "fox_glass.dll", "fox_path_boundary.dll",
)
GUIDES = ("README.md", "BUILDING.md", "AUTHORS.md", "CONTRIBUTING.md", "LICENSE",
          "THIRD_PARTY_NOTICES.md", "SECURITY.md", "docs/USAGE.md")
NOTICES = ("Fox-Attribution.md", "GCC-GPL-3.txt", "GCC-Runtime-Exception-3.1.txt",
           "Godot-License.txt", "Godot-Third-Party.txt", "MinGW-w64-License.txt",
           "Native-Bridge.txt", "Sounds-CC0.txt")
IMAGES = ("desktop-fox.png", "compact-chat.png", "full-chat.png", "settings.png",
          "model-manager.png", "lying.png", "sleeping.png")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def distribution_names():
    return set(RUNTIME) | set(GUIDES) | {"Notices/" + n for n in NOTICES} | {
        "docs/images/" + n for n in IMAGES
    }


def check_distribution(folder, expected):
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file()}
    if actual != expected:
        raise RuntimeError(f"Unexpected distribution files: {sorted(actual ^ expected)}")


def prepare_release(root, version):
    destination = root / "dist" / version
    if destination.exists():
        raise FileExistsError(f"Release already exists: {destination}. Keep it; use a new version for changes.")
    staging = root / ".build" / "staging"
    staging.mkdir(parents=True, exist_ok=True)
    return Path(tempfile.mkdtemp(prefix="candidate-", dir=staging)), destination


def publish_local(staging, destination, root):
    # Rename only the fresh build-owned tree within this checkout. Never clean
    # or reuse an existing release folder, and never recursively delete files.
    if not staging.resolve().is_relative_to((root / ".build" / "staging").resolve()):
        raise ValueError("Staging path is outside the build directory")
    if not destination.resolve().is_relative_to((root / "dist").resolve()):
        raise ValueError("Release path is outside dist")
    if destination.exists():
        raise FileExistsError(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    os.rename(staging, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--cc", default="gcc", help="x86_64 MinGW-w64 GCC")
    parser.add_argument("--templates", help="Matching Windows export-template directory")
    parser.add_argument("--installer", action="store_true")
    parser.add_argument("--windres", help="Resource compiler; defaults to GCC's directory")
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("This builder requires Windows.")
    godot = Path(shutil.which(args.godot) or args.godot).resolve()
    cc = Path(shutil.which(args.cc) or args.cc).resolve()
    if not godot.is_file() or not cc.is_file():
        parser.error("Select existing Godot and MinGW-w64 executables.")
    version = subprocess.check_output([str(godot), "--version"], text=True).strip()
    machine = subprocess.check_output([str(cc), "-dumpmachine"], text=True).strip()
    if not version.startswith("4.7.2.") or not machine.startswith("x86_64-"):
        parser.error("Requires Godot 4.7.2 and x86_64 MinGW-w64 GCC.")
    stage, destination = prepare_release(ROOT, VERSION)
    out = stage / "DesktopPet"
    out.mkdir()
    temp = ROOT / ".build"
    logs = temp / "logs"
    logs.mkdir(exist_ok=True)
    env = os.environ.copy()
    for key, leaf in [("APPDATA", "Roaming"), ("LOCALAPPDATA", "Local")]:
        folder = temp / "Profile" / leaf
        folder.mkdir(parents=True, exist_ok=True)
        env[key] = str(folder)
    if args.templates:
        templates = Path(args.templates).resolve()
        if not (templates / "windows_release_x86_64.exe").is_file():
            parser.error("Template directory must contain windows_release_x86_64.exe.")
        target = Path(env["APPDATA"]) / "Godot/export_templates/4.7.2.stable"
        target.mkdir(parents=True, exist_ok=True)
        for name in ["windows_release_x86_64.exe", "version.txt"]:
            if (templates / name).is_file() and (templates / name).resolve() != (target / name).resolve():
                shutil.copy2(templates / name, target / name)

    def run(label, command):
        for attempt in range(2):
            path = logs / f"{label}.attempt{attempt + 1}.log"
            with path.open("w", encoding="utf-8") as log:
                result = subprocess.run([str(x) for x in command], cwd=ROOT, env=env,
                                        stdout=log, stderr=subprocess.STDOUT, timeout=180)
            text = path.read_text(encoding="utf-8", errors="replace")
            shutil.copy2(path, logs / (label + ".log"))
            retry = (attempt == 0 and label in {"godot_import", "setup_import"}
                     and result.returncode in {3221225477, -1073741819}
                     and "SCRIPT ERROR" not in text)
            if retry:
                print(f"{label}: import access violation; retrying once. First log retained.", flush=True)
                continue
            if result.returncode or "SCRIPT ERROR" in text:
                raise RuntimeError(f"{label} failed ({result.returncode}); see {path}")
            break
        print(label + " passed", flush=True)

    src = ROOT / "Source/Native"
    native = ROOT / "Source/Godot/native"
    common = [cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
              "-Wno-cast-function-type", "-shared", "-static-libgcc"]
    targets = [("fox_window", ["user32", "advapi32", "wtsapi32"]),
               ("fox_chat_window", []), ("fox_glass", ["user32", "gdi32"]),
               ("fox_path_boundary", ["advapi32", "user32", "shlwapi", "wintrust", "crypt32"])]
    for name, libs in targets:
        run(name, [*common, src / (name + ".c"), "-o", native / (name + ".dll"),
                   *["-l" + x for x in libs]])
        shutil.copy2(native / (name + ".dll"), out / (name + ".dll"))
    for name, source, flags, libs in [
        ("DesktopPet", "fox_release_launcher", ["-mwindows"], []),
        ("DesktopFoxStartup", "fox_release_startup", [], ["ole32", "shell32", "uuid"]),
    ]:
        run(name, [cc, "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror", "-municode",
                   "-static-libgcc", *flags, src / (source + ".c"), "-o", out / (name + ".exe"),
                   *["-l" + x for x in libs]])
    helpers = temp / "Helpers"
    helpers.mkdir(exist_ok=True)
    shutil.copy2(out / "DesktopFoxStartup.exe", helpers / "DesktopFoxStartup.exe")
    project = ROOT / "Source/Godot"
    run("godot_import", [godot, "--headless", "--path", project, "--editor", "--import"])
    run("godot_export", [godot, "--headless", "--path", project, "--export-release",
                         "Windows Portable Release", out / "DesktopFox.exe"])
    expected = distribution_names()
    for name in sorted(expected - set(RUNTIME)):
        target = out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    check_distribution(out, expected)
    inventory = {name: {"bytes": (out / name).stat().st_size, "sha256": digest(out / name)}
                 for name in sorted(expected)}
    (out / "release.json").write_text(json.dumps({
        "version": VERSION, "product": "Desktop Pet", "build": "source-build",
        "godot": version, "compiler_target": machine, "unsigned": True, "files": inventory,
    }, indent=2) + "\n", encoding="utf-8")
    expected.add("release.json")
    (out / "SHA256SUMS.txt").write_text("".join(
        digest(out / name) + "  " + name + "\n" for name in sorted(expected)), encoding="utf-8")
    expected.add("SHA256SUMS.txt")
    check_distribution(out, expected)
    archive = stage / "DesktopPet_Portable.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zipped:
        for name in sorted(expected):
            zipped.write(out / name, "DesktopPet/" + name)
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() is not None or set(zipped.namelist()) != {"DesktopPet/" + n for n in expected}:
            raise RuntimeError("Portable archive verification failed")
    result = {"version": VERSION, "portable_zip": str(destination / archive.name),
              "sha256": digest(archive), "bytes": archive.stat().st_size,
              "runtime_files": len(RUNTIME), "installer_built": False}
    if args.installer:
        from build_installer import build_installer
        windres = Path(args.windres).resolve() if args.windres else cc.with_name("windres.exe")
        result.update(build_installer(ROOT, out, VERSION, godot, cc, windres, env, run))
        result["setup"] = str(destination / "DesktopPet_Setup.exe")
    publish_local(stage, destination, ROOT)
    (temp / "build_result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("Build complete: " + str(destination / "DesktopPet/DesktopPet.exe"))


if __name__ == "__main__":
    main()
