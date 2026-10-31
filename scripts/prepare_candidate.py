"""Create an immutable candidate tag from reviewed main and dispatch its builder."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess


def api(path, data=None, method="GET"):
    args = ["gh", "api", path, "--method", method]
    if data is not None:
        args += ["--input", "-"]
    result = subprocess.run(args, input=json.dumps(data) if data is not None else None,
                            capture_output=True, text=True, check=True)
    return json.loads(result.stdout) if result.stdout.strip() else None


def metadata(app):
    if app == "MultiSwitcher":
        info = plistlib.loads(Path("macos/Info.plist").read_bytes())
        return info["CFBundleShortVersionString"], info["CFBundleVersion"]
    version = re.search(r'__version__\s*=\s*"([0-9.]+)"', Path("dragshift/__init__.py").read_text()).group(1)
    return version, Path("macos/build-number.txt").read_text().strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, choices=["MultiShift", "MultiSwitcher"])
    parser.add_argument("--commit", required=True)
    parser.add_argument("--channel", required=True, choices=["beta", "stable"])
    args = parser.parse_args()
    repo = "SokolovMO/" + args.app
    if os.environ.get("GITHUB_REPOSITORY") != repo:
        raise ValueError("unexpected source repository")
    if not re.fullmatch(r"[a-f0-9]{40}", args.commit):
        raise ValueError("full commit SHA required")
    subprocess.run(["git", "fetch", "origin", "main"], check=True)
    subprocess.run(["git", "merge-base", "--is-ancestor", args.commit, "origin/main"], check=True)
    workflow = "macos.yml" if args.app == "MultiShift" else "multi-switcher-ci.yml"
    runs = api(f"repos/{repo}/actions/workflows/{workflow}/runs?head_sha={args.commit}&event=push&per_page=100")["workflow_runs"]
    runs = [r for r in runs if r["head_branch"] == "main"]
    if not runs or runs[0]["conclusion"] != "success":
        raise ValueError("latest push CI for this commit must pass")
    subprocess.run(["git", "checkout", "--detach", args.commit], check=True)
    version, build = metadata(args.app)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("numeric version and positive integer build required")
    tag = f"{'beta-v' if args.channel == 'beta' else 'v'}{version}-build{build}"
    refs = api(f"repos/{repo}/git/matching-refs/tags/{tag}")
    exact = [ref for ref in refs if ref["ref"] == "refs/tags/" + tag]
    if exact:
        if exact[0]["object"]["type"] != "commit" or exact[0]["object"]["sha"] != args.commit:
            raise ValueError("tag is already bound to another commit")
    else:
        api(f"repos/{repo}/git/refs", {"ref": "refs/tags/" + tag, "sha": args.commit}, "POST")
    existing = api(f"repos/{repo}/releases?per_page=100")
    if any(r["tag_name"] == tag for r in existing):
        print("candidate already exists")
        return
    builder = "macos.yml" if args.app == "MultiShift" else "multi-switcher-release.yml"
    runs = api(f"repos/{repo}/actions/workflows/{builder}/runs?head_sha={args.commit}&event=workflow_dispatch&per_page=100")["workflow_runs"]
    if any(r["head_branch"] == tag and r["status"] != "completed" for r in runs):
        print("candidate build already running")
        return
    api(f"repos/{repo}/actions/workflows/{builder}/dispatches", {"ref": tag}, "POST")
    print("candidate queued:", tag)

if __name__ == "__main__":
    main()
