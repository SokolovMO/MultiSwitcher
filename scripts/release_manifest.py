"""Create an immutable candidate identity and verify artifact-bound acceptance."""
import argparse
import hashlib
import json
import re
from pathlib import Path

REQUIRED = {"signature", "notarization", "gatekeeper", "functional", "interface", "update_a_to_b", "data_preservation"}


def digest(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def create(app, version, build, commit, channel, minimum_os, artifact, updater_key=None):
    if app not in {"MultiShift", "MultiSwitcher"} or channel not in {"stable", "beta"}:
        raise ValueError("unsupported application or channel")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("version must have three numeric components")
    if not re.fullmatch(r"[1-9]\d*", build) or not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("invalid build or full commit SHA")
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", minimum_os):
        raise ValueError("invalid minimum macOS")
    manifest = dict(schema=1, app=app, version=version, build=build, commit=commit,
                    channel=channel, architecture="arm64", minimum_macos=minimum_os,
                    artifact=Path(artifact).name, sha256=digest(artifact))
    if updater_key is not None:
        import base64
        if len(base64.b64decode(updater_key, validate=True)) != 32:
            raise ValueError("invalid updater public key")
        manifest["updater_public_key"] = updater_key
    manifest["candidate_id"] = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()
    return manifest


def verify(manifest, artifact, acceptance):
    identity = dict(manifest)
    candidate_id = identity.pop("candidate_id")
    expected = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    if expected != candidate_id or digest(artifact) != manifest["sha256"]:
        raise ValueError("candidate or artifact changed; acceptance invalidated")
    if acceptance.get("candidate_id") != candidate_id:
        raise ValueError("acceptance belongs to another candidate")
    checks = acceptance.get("checks", {})
    if any(checks.get(check) != "passed" for check in REQUIRED):
        raise ValueError("required acceptance checks are incomplete")
    if not acceptance.get("reviewer") or not acceptance.get("reviewed_at"):
        raise ValueError("reviewer and review timestamp are required")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    make = sub.add_parser("create")
    for key in ("app", "version", "build", "commit", "channel", "minimum-os", "artifact"):
        make.add_argument("--" + key, required=True)
    make.add_argument("--updater-key")
    check = sub.add_parser("verify")
    for key in ("manifest", "artifact", "acceptance"):
        check.add_argument("--" + key, required=True)
    args = vars(parser.parse_args())
    command = args.pop("command")
    if command == "create":
        print(json.dumps(create(**args), indent=2))
    else:
        verify(json.loads(Path(args["manifest"]).read_text()), args["artifact"],
               json.loads(Path(args["acceptance"]).read_text()))
        print("acceptance verified")

if __name__ == "__main__":
    main()
