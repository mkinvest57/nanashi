#!/usr/bin/env python3
"""Inspect release artifacts and generate Nanashi's public installation manifests."""

import argparse
import datetime as dt
import hashlib
import json
import plistlib
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import quote, urlsplit


IOS_ID = "com.rayanmakhlouf.noopdev.noop"
WIDGET_ID = IOS_ID + ".widgets"
APP_GROUP = "group.com.rayanmakhlouf.noopdev.noop.staging"
ANDROID_ID = "com.rayanmakhlouf.nanashi"
SOURCE_ID = "com.rayanmakhlouf.nanashi.source"
REQUIRED_ENTITLEMENTS = {
    "com.apple.developer.healthkit",
    "com.apple.developer.healthkit.background-delivery",
    "com.apple.security.application-groups",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(*args):
    result = subprocess.run(args, check=False, capture_output=True)
    if result.returncode:
        raise ValueError(f"{args[0]} failed: {result.stderr.decode(errors='replace').strip()}")
    return result


def https_url(value):
    parsed = urlsplit(value)
    require(parsed.scheme == "https" and parsed.hostname and not parsed.username
            and not parsed.password and not parsed.fragment and not parsed.query,
            f"Expected a public HTTPS URL without credentials/query/fragment: {value}")
    require(parsed.hostname not in {"localhost", "127.0.0.1", "::1"}, "Local URLs cannot be published")
    return value.rstrip("/")


def file_record(path):
    path = Path(path)
    require(path.is_file() and path.stat().st_size > 0, f"Missing or empty artifact: {path}")
    return {"filename": path.name, "size": path.stat().st_size, "sha256": sha256(path)}


def ipa_info(path):
    """Read exact bundle metadata; never extract a path before checking its archive name."""
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "IPA contains duplicate archive entries")
        for name in names:
            parts = PurePosixPath(name).parts
            require(not name.startswith("/") and ".." not in parts and "\\" not in name,
                    "Unsafe IPA archive path")
            require(not (archive.getinfo(name).external_attr >> 16 & 0o170000) == 0o120000,
                    "IPA symlinks are not supported by this distribution checker")
        apps = [name for name in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        require(len(apps) == 1, "IPA must contain exactly one iPhone app")
        app_root = str(PurePosixPath(apps[0]).parent)
        widgets = [name for name in names if re.fullmatch(
            re.escape(app_root) + r"/PlugIns/[^/]+\.appex/Info\.plist", name)]
        require(len(widgets) == 1, "Nanashi's widget must be retained as its own extension")
        require(not any("/Watch/" in name for name in names), "Remove the Watch bundle from the sideload IPA")
        require(not any(name.endswith("embedded.mobileprovision") for name in names),
                "Do not distribute a personally provisioned IPA")
        app = plistlib.loads(archive.read(apps[0]))
        widget = plistlib.loads(archive.read(widgets[0]))
        require(app.get("CFBundleIdentifier") == IOS_ID, "iOS bundle identity changed; existing data would not follow")
        require(widget.get("CFBundleIdentifier") == WIDGET_ID, "Widget bundle identity changed")
        require(app.get("AppGroupIdentifier") == widget.get("AppGroupIdentifier") == APP_GROUP,
                "App and widget must use the existing shared App Group")
        require(app.get("CFBundleDisplayName") == "Nanashi", "The iOS app must be branded Nanashi")
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            require(str(app.get(key, "")) and app.get(key) == widget.get(key), f"App/widget mismatch: {key}")
        require(re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", app.get("MinimumOSVersion", "")),
                "Missing or invalid iOS deployment minimum")
        require(app_root + "/" + app.get("CFBundleExecutable", "") in names, "Main executable missing")
        privacy = {}
        for info in (app, widget):
            for key, value in info.items():
                if key.startswith("NS") and key.endswith("UsageDescription"):
                    require(isinstance(value, str) and value.strip(), f"Empty privacy description: {key}")
                    privacy.setdefault(key, value)
        return {"version": str(app["CFBundleShortVersionString"]), "build": str(app["CFBundleVersion"]),
                "bundleIdentifier": IOS_ID, "minOSVersion": app["MinimumOSVersion"],
                "appGroup": APP_GROUP, "widgetBundleIdentifier": WIDGET_ID,
                "privacy": privacy, "appPath": app_root,
                "widgetPath": str(PurePosixPath(widgets[0]).parent)}


def inspect_ios(path):
    info = ipa_info(path)
    entitlements = set()
    with tempfile.TemporaryDirectory(prefix="nanashi-ipa-") as directory:
        with zipfile.ZipFile(path) as archive:
            archive.extractall(directory)
        app = Path(directory) / info["appPath"]
        run("codesign", "--verify", "--deep", "--strict", str(app))
        for key in ("appPath", "widgetPath"):
            bundle = str(Path(directory) / info[key])
            identity = run("codesign", "-dvv", bundle).stderr.decode(errors="replace")
            require("Signature=adhoc" in identity, "Distribution must use a replaceable ad-hoc capability template")
            result = run("codesign", "-d", "--entitlements", ":-", bundle)
            capabilities = plistlib.loads(result.stdout)
            require(capabilities.get("com.apple.security.application-groups") == [APP_GROUP],
                    "Signed App Group is missing or differs from the installed identity")
            require(not capabilities.get("get-task-allow"), "Debug entitlement in distribution IPA")
            require(not any(k in capabilities for k in ("application-identifier", "com.apple.developer.team-identifier")),
                    "Personal Apple identity must not be embedded in the distribution template")
            if key == "appPath":
                require(capabilities.get("com.apple.developer.healthkit") is True
                        and capabilities.get("com.apple.developer.healthkit.background-delivery") is True,
                        "HealthKit capabilities missing from app")
            entitlements.update(capabilities)
    return {"schemaVersion": 1, "platform": "ios", **file_record(path),
            **{k: v for k, v in info.items() if k not in {"appPath", "widgetPath", "privacy"}},
            "appPermissions": {"entitlements": sorted(entitlements), "privacy": info["privacy"]},
            "verification": "codesign-ad-hoc-deep-strict"}


def parse_android_badging(text):
    package = re.search(r"^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'", text, re.M)
    sdk = re.search(r"^sdkVersion:'([0-9]+)'", text, re.M)
    require(package and sdk, "aapt2 did not report package, version, and minimum SDK")
    app_id, build, version = package.groups()
    require(app_id == ANDROID_ID, "Android package must use Nanashi's permanent release identity")
    require("application-label:'Nanashi'" in text, "The Android release must be branded Nanashi")
    require(not re.search(r"^application-debuggable", text, re.M), "Debuggable APK cannot be published")
    return {"applicationId": app_id, "build": build, "version": version, "minSDK": int(sdk.group(1))}


def inspect_android(path, aapt2, apksigner):
    info = parse_android_badging(run(aapt2, "dump", "badging", str(path)).stdout.decode())
    signatures = run(apksigner, "verify", "--verbose", "--print-certs", str(path)).stdout.decode()
    require("android debug" not in signatures.lower(), "A shared/debug signing certificate cannot ship")
    certs = re.findall(r"^Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-fA-F]{64})$", signatures, re.M)
    require(len(certs) == 1, "Expected one verified Android release signer")
    return {"schemaVersion": 1, "platform": "android", **file_record(path), **info,
            "signingCertificateSHA256": certs[0].lower(), "verification": "apksigner-verified"}


def load_verified(path, metadata_path, platform):
    data = json.loads(Path(metadata_path).read_text())
    require(data.get("schemaVersion") == 1 and data.get("platform") == platform, "Wrong artifact metadata schema")
    for key, value in file_record(path).items():
        require(data.get(key) == value, f"Artifact changed after inspection: {platform} {key}")
    require(data.get("verification") == {"ios": "codesign-ad-hoc-deep-strict", "android": "apksigner-verified"}[platform],
            "Artifact signature verification is missing")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", data.get("version", "")), "Version must be stable SemVer x.y.z")
    require(re.fullmatch(r"[1-9][0-9]*", str(data.get("build", ""))), "Build must be a positive integer")
    if platform == "ios":
        actual = ipa_info(path)
        for key in ("version", "build", "bundleIdentifier", "minOSVersion", "appGroup", "widgetBundleIdentifier"):
            require(data.get(key) == actual[key], f"IPA metadata mismatch: {key}")
        permissions = data.get("appPermissions", {})
        require(REQUIRED_ENTITLEMENTS <= set(permissions.get("entitlements", [])), "Missing HealthKit/widget entitlements")
        require(permissions.get("privacy") == actual["privacy"], "IPA privacy permissions differ from manifest")
    else:
        require(data.get("applicationId") == ANDROID_ID, "Unexpected Android package")
        require(re.fullmatch(r"[0-9a-f]{64}", data.get("signingCertificateSHA256", "")), "Missing signing certificate")
        require(isinstance(data.get("minSDK"), int) and data["minSDK"] >= 26, "Invalid Android minimum SDK")
    return data


def generate(args):
    repository = https_url(args.repository)
    require(re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository), "Expected a GitHub repository URL")
    base = https_url(args.base_url)
    require(re.fullmatch(r"[A-Za-z0-9_.-]+", args.tag), "Unsafe release tag")
    require(re.fullmatch(r"[0-9a-f]{40}", args.source_sha), "A full source commit SHA is required")
    platforms = {}
    for platform in ("ios", "android"):
        artifact = getattr(args, "ipa" if platform == "ios" else "apk")
        metadata = getattr(args, platform + "_metadata")
        require(bool(artifact) == bool(metadata), f"{platform} requires both artifact and inspection metadata")
        if artifact:
            platforms[platform] = load_verified(artifact, metadata, platform)
    require(platforms, "At least one verified binary is required; do not publish placeholder download links")
    require(len({value["version"] for value in platforms.values()}) == 1, "iOS/Android marketing versions differ")
    first = next(iter(platforms.values()))
    require(args.tag in {f"v{first['version']}", f"nanashi-v{first['version']}-b{first['build']}"},
            "Release tag does not identify the inspected version")
    if args.previous_catalog:
        previous = json.loads(Path(args.previous_catalog).read_text())
        require(previous.get("repository") == repository, "Previous catalog belongs to another repository")
        previous_release = previous.get("latest")
        if previous_release is not None:
            require(isinstance(previous_release, dict), "Invalid previous release catalog")
            previous_version = previous_release.get("version")
            require(isinstance(previous_version, str)
                    and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", previous_version),
                    "Previous release must have a stable SemVer version")
            require(tuple(map(int, first["version"].split(".")))
                    > tuple(map(int, previous_version.split("."))),
                    "A new public release must increment the marketing version")
        for platform, data in platforms.items():
            old = (previous.get("latest") or {}).get(platform)
            if old:
                require(int(data["build"]) > int(old["build"]), "A new release must increment the platform build number")
                if platform == "android":
                    require(data["signingCertificateSHA256"] == old["signingCertificateSHA256"],
                            "Android signing key changed; existing users would be unable to update")
    published = args.published_at or dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    require(dt.datetime.fromisoformat(published.replace("Z", "+00:00")).tzinfo is not None, "Release date must include a timezone")
    release_url = f"{repository}/releases/tag/{args.tag}"
    latest = {"version": first["version"], "releaseURL": release_url, "publishedAt": published,
              "sourceCommit": args.source_sha}
    source_url = base + "/altstore-source.json"
    public_keys = {"ios": ("version", "build", "bundleIdentifier", "minOSVersion", "size", "sha256"),
                   "android": ("version", "build", "applicationId", "minSDK", "size", "sha256", "signingCertificateSHA256")}
    for platform, data in platforms.items():
        latest[platform] = {key: data[key] for key in public_keys[platform]}
        latest[platform]["downloadURL"] = f"{repository}/releases/download/{args.tag}/{quote(data['filename'], safe='')}"
    catalog = {"schemaVersion": 1, "updatedAt": published, "repository": repository, "latest": latest,
               "sideStore": {"sourceURL": source_url,
                             "addSourceURL": "sidestore://source?url=" + quote(source_url, safe="")} if "ios" in platforms else None}
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    if "ios" in platforms:
        data = platforms["ios"]
        description = ("Nanashi is a personal, noncommercial adaptation of NOOP by @ryanbr / NoopApp. "
                       "Bluetooth collection and health history remain on the device. "
                       "Source and license: " + repository + ". Not affiliated with WHOOP. "
                       "Required Notice: Copyright 2026 NoopApp. PolyForm Noncommercial 1.0.0.")
        version = {"version": data["version"], "buildVersion": data["build"], "date": published,
                   "localizedDescription": args.notes or "See the release notes for changes and verification.",
                   "downloadURL": latest["ios"]["downloadURL"], "size": data["size"], "minOSVersion": data["minOSVersion"]}
        previous_versions = []
        if args.previous_source:
            previous = json.loads(Path(args.previous_source).read_text())
            require(previous.get("identifier") == SOURCE_ID, "Previous feed belongs to a different source")
            require(len(previous.get("apps", [])) == 1 and previous["apps"][0].get("bundleIdentifier") == IOS_ID,
                    "Previous feed has a different app identity")
            previous_versions = [entry for entry in previous["apps"][0].get("versions", [])
                                 if (entry.get("version"), entry.get("buildVersion")) != (data["version"], data["build"])]
            for entry in previous_versions:
                require(str(entry.get("downloadURL", "")).startswith(repository + "/releases/download/"),
                        "Previous source contains a release outside this repository")
            old_permissions = previous["apps"][0].get("appPermissions", {})
            data["appPermissions"]["entitlements"] = sorted(set(data["appPermissions"]["entitlements"])
                                                           | set(old_permissions.get("entitlements", [])))
            for key, value in old_permissions.get("privacy", {}).items():
                data["appPermissions"]["privacy"].setdefault(key, value)
        source = {"name": "Nanashi", "identifier": SOURCE_ID, "sourceURL": source_url,
                  "website": base, "iconURL": base + "/icon.png", "description": description,
                  "apps": [{"name": "Nanashi", "bundleIdentifier": IOS_ID, "developerName": "Nanashi contributors",
                            "localizedDescription": description, "iconURL": base + "/icon.png",
                            "versions": [version] + previous_versions,
                            "appPermissions": data["appPermissions"]}], "news": []}
        write_json(output / "altstore-source.json", source)
    else:
        # Prevent a stale iOS feed being accidentally bundled into an Android-only release.
        require(not (output / "altstore-source.json").exists(), "Use a clean output directory for an Android-only release")
    write_json(output / "releases.json", catalog)
    (output / "SHA256SUMS.txt").write_text("".join(f"{data['sha256']}  {data['filename']}\n" for data in platforms.values()))
    return catalog


def write_json(path, value):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
    temporary.replace(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    ios = commands.add_parser("inspect-ios")
    ios.add_argument("--ipa", required=True)
    ios.add_argument("--output", required=True)
    android = commands.add_parser("inspect-android")
    android.add_argument("--apk", required=True)
    android.add_argument("--aapt2", default="aapt2")
    android.add_argument("--apksigner", default="apksigner")
    android.add_argument("--output", required=True)
    manifest = commands.add_parser("generate")
    for flag in ("ipa", "apk", "ios-metadata", "android-metadata", "published-at", "notes", "previous-source", "previous-catalog"):
        manifest.add_argument("--" + flag)
    for flag in ("base-url", "repository", "tag", "source-sha", "output-dir"):
        manifest.add_argument("--" + flag, required=True)
    args = parser.parse_args()
    try:
        if args.command == "inspect-ios":
            write_json(args.output, inspect_ios(args.ipa))
        elif args.command == "inspect-android":
            write_json(args.output, inspect_android(args.apk, args.aapt2, args.apksigner))
        else:
            generate(args)
    except (ValueError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Release validation failed: {error}\n")


if __name__ == "__main__":
    main()
