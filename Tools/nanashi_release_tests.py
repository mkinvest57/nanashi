"""Distribution regressions: identity, permissions, signing and artifact integrity."""

import argparse
import copy
import json
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from Tools import nanashi_release as release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.ipa = self.root / "Nanashi-ios-v12.1.0-b446.ipa"
        self.apk = self.root / "Nanashi-android-v12.1.0-b446.apk"
        self.apk.write_bytes(b"APK fixture inspected by the native-tool stub")
        self.app = {"CFBundleIdentifier": release.IOS_ID, "AppGroupIdentifier": release.APP_GROUP,
                    "CFBundleDisplayName": "Nanashi", "CFBundleExecutable": "Nanashi",
                    "CFBundleShortVersionString": "12.1.0", "CFBundleVersion": "446",
                    "MinimumOSVersion": "17.0", "NSHealthShareUsageDescription": "Reads permitted health data."}
        self.widget = {**self.app, "CFBundleIdentifier": release.WIDGET_ID}
        self.entitlements = {"com.apple.security.application-groups": [release.APP_GROUP],
                             "com.apple.developer.healthkit": True,
                             "com.apple.developer.healthkit.background-delivery": True,
                             "com.apple.developer.healthkit.access": []}
        self.make_ipa()
        self.ios_metadata = self.root / "ios.metadata.json"
        self.android_metadata = self.root / "android.metadata.json"
        with patch.object(release, "run", self.native_tool):
            self.ios = release.inspect_ios(self.ipa)
            self.android = release.inspect_android(self.apk, "aapt2", "apksigner")
        release.write_json(self.ios_metadata, self.ios)
        release.write_json(self.android_metadata, self.android)
        self.args = argparse.Namespace(
            ipa=self.ipa, apk=self.apk, ios_metadata=self.ios_metadata, android_metadata=self.android_metadata,
            base_url="https://nanashi.example", repository="https://github.com/mkinvest57/nanashi",
            tag="nanashi-v12.1.0-b446", source_sha="a" * 40, output_dir=self.root / "public",
            published_at="2026-11-12T12:00:00Z", notes=None, previous_source=None, previous_catalog=None)

    def make_ipa(self, extra=None, include_widget=True):
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/Nanashi.app/Info.plist", plistlib.dumps(self.app))
            archive.writestr("Payload/Nanashi.app/Nanashi", b"Mach-O fixture")
            if include_widget:
                archive.writestr("Payload/Nanashi.app/PlugIns/NanashiWidgets.appex/Info.plist", plistlib.dumps(self.widget))
            for name, data in (extra or {}).items():
                archive.writestr(name, data)

    def native_tool(self, *args):
        if args[0] == "aapt2":
            value = ("package: name='com.rayanmakhlouf.nanashi' versionCode='446' versionName='12.1.0'\n"
                     "sdkVersion:'26'\napplication-label:'Nanashi'\n")
            return SimpleNamespace(stdout=value.encode(), stderr=b"")
        if args[0] == "apksigner":
            value = "Signer #1 certificate SHA-256 digest: " + "b" * 64 + "\nSigner #1 certificate DN: CN=Nanashi\n"
            return SimpleNamespace(stdout=value.encode(), stderr=b"")
        if "-dvv" in args:
            return SimpleNamespace(stdout=b"", stderr=b"Signature=adhoc\n")
        if "--entitlements" in args:
            return SimpleNamespace(stdout=plistlib.dumps(self.entitlements), stderr=b"")
        return SimpleNamespace(stdout=b"", stderr=b"")

    def test_manifest_uses_actual_binaries_and_capabilities(self):
        catalog = release.generate(self.args)
        self.assertEqual(catalog["latest"]["ios"]["sha256"], release.sha256(self.ipa))
        self.assertEqual(catalog["latest"]["ios"]["size"], self.ipa.stat().st_size)
        self.assertEqual(catalog["latest"]["android"]["signingCertificateSHA256"], "b" * 64)
        feed = json.loads((self.args.output_dir / "altstore-source.json").read_text())
        app = feed["apps"][0]
        self.assertEqual(app["bundleIdentifier"], release.IOS_ID)
        self.assertEqual(app["versions"][0]["buildVersion"], "446")
        self.assertEqual(app["appPermissions"]["privacy"], self.ios["appPermissions"]["privacy"])
        self.assertNotIn("marketplaceID", app)
        self.assertEqual(catalog["sideStore"]["addSourceURL"],
                         "sidestore://source?url=https%3A%2F%2Fnanashi.example%2Faltstore-source.json")

    def test_changed_artifact_cannot_reuse_verified_metadata(self):
        self.apk.write_bytes(self.apk.read_bytes() + b"tampering")
        with self.assertRaisesRegex(ValueError, "Artifact changed after inspection"):
            release.generate(self.args)

    def test_signed_ipa_metadata_is_rechecked_against_plist(self):
        self.ios["version"] = "12.2.0"
        release.write_json(self.ios_metadata, self.ios)
        with self.assertRaisesRegex(ValueError, "IPA metadata mismatch"):
            release.generate(self.args)

    def test_rejects_personally_provisioned_ipa(self):
        self.make_ipa({"Payload/Nanashi.app/embedded.mobileprovision": b"profile"})
        with self.assertRaisesRegex(ValueError, "personally provisioned"):
            release.ipa_info(self.ipa)

    def test_rejects_path_traversal_before_extraction(self):
        self.make_ipa({"../../credentials": b"data"})
        with self.assertRaisesRegex(ValueError, "Unsafe IPA"):
            release.ipa_info(self.ipa)

    def test_cannot_accidentally_ship_another_bundle_identity(self):
        self.app["CFBundleIdentifier"] = "com.noopapp.noop"
        self.make_ipa()
        with self.assertRaisesRegex(ValueError, "identity changed"):
            release.ipa_info(self.ipa)

    def test_missing_widget_rejected(self):
        self.make_ipa(include_widget=False)
        with self.assertRaisesRegex(ValueError, "widget must be retained"):
            release.ipa_info(self.ipa)

    def test_mismatched_widget_group_rejected(self):
        self.widget["AppGroupIdentifier"] = release.APP_GROUP + ".changed"
        self.make_ipa()
        with self.assertRaisesRegex(ValueError, "shared App Group"):
            release.ipa_info(self.ipa)

    def test_extension_version_mismatch_rejected(self):
        self.widget["CFBundleVersion"] = "445"
        self.make_ipa()
        with self.assertRaisesRegex(ValueError, "App/widget mismatch"):
            release.ipa_info(self.ipa)

    def test_healthkit_must_survive_signing(self):
        del self.entitlements["com.apple.developer.healthkit"]
        with patch.object(release, "run", self.native_tool):
            with self.assertRaisesRegex(ValueError, "HealthKit capabilities missing"):
                release.inspect_ios(self.ipa)

    def test_personal_signing_identity_rejected(self):
        self.entitlements["application-identifier"] = "PERSONAL." + release.IOS_ID
        with patch.object(release, "run", self.native_tool):
            with self.assertRaisesRegex(ValueError, "Personal Apple identity"):
                release.inspect_ios(self.ipa)

    def test_android_debug_cert_rejected(self):
        def debug_tool(*args):
            output = self.native_tool(*args)
            if args[0] == "apksigner":
                output.stdout += b"Signer #1 certificate DN: CN=Android Debug\n"
            return output
        with patch.object(release, "run", debug_tool):
            with self.assertRaisesRegex(ValueError, "debug signing certificate"):
                release.inspect_android(self.apk, "aapt2", "apksigner")

    def test_android_staging_identity_rejected(self):
        text = self.native_tool("aapt2").stdout.decode().replace("com.rayanmakhlouf.nanashi", "com.noop.whoop.staging")
        with self.assertRaisesRegex(ValueError, "permanent release identity"):
            release.parse_android_badging(text)

    def test_android_debuggable_rejected(self):
        with self.assertRaisesRegex(ValueError, "Debuggable"):
            release.parse_android_badging(self.native_tool("aapt2").stdout.decode() + "application-debuggable\n")

    def test_no_placeholder_downloads(self):
        self.args.ipa = self.args.apk = self.args.ios_metadata = self.args.android_metadata = None
        with self.assertRaisesRegex(ValueError, "At least one verified binary"):
            release.generate(self.args)

    def test_unsafe_public_urls_rejected(self):
        for url in ("http://nanashi.example", "https://token@nanashi.example", "https://localhost", "https://nanashi.example?token=x"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                release.https_url(url)

    def test_distinct_versions_rejected(self):
        self.android["version"] = "13.0.0"
        release.write_json(self.android_metadata, self.android)
        with self.assertRaisesRegex(ValueError, "marketing versions differ"):
            release.generate(self.args)

    def test_platform_build_counters_are_independent(self):
        self.android["build"] = "559"
        release.write_json(self.android_metadata, self.android)
        self.args.tag = "v12.1.0"
        catalog = release.generate(self.args)
        self.assertEqual(catalog["latest"]["ios"]["build"], "446")
        self.assertEqual(catalog["latest"]["android"]["build"], "559")

    def test_signing_key_rotation_cannot_break_updates(self):
        catalog = release.generate(self.args)
        catalog["latest"]["version"] = "12.0.0"
        catalog["latest"]["android"]["build"] = "445"
        catalog["latest"]["ios"]["build"] = "445"
        catalog["latest"]["android"]["signingCertificateSHA256"] = "c" * 64
        previous = self.root / "previous.json"
        release.write_json(previous, catalog)
        self.args.previous_catalog = previous
        with self.assertRaisesRegex(ValueError, "signing key changed"):
            release.generate(self.args)

    def test_previous_release_minimum_os_remains_available(self):
        release.generate(self.args)
        feed_path = self.args.output_dir / "altstore-source.json"
        feed = json.loads(feed_path.read_text())
        previous = copy.deepcopy(feed["apps"][0]["versions"][0])
        previous.update(version="12.0.0", buildVersion="445", minOSVersion="16.0")
        feed["apps"][0]["versions"] = [previous]
        release.write_json(feed_path, feed)
        self.args.previous_source = feed_path
        release.generate(self.args)
        versions = json.loads(feed_path.read_text())["apps"][0]["versions"]
        self.assertEqual([v["buildVersion"] for v in versions], ["446", "445"])
        self.assertEqual(versions[1]["minOSVersion"], "16.0")

    def test_new_build_counter_required_for_updates(self):
        catalog = release.generate(self.args)
        catalog["latest"]["version"] = "12.0.0"
        release.write_json(self.args.output_dir / "releases.json", catalog)
        self.args.previous_catalog = self.args.output_dir / "releases.json"
        with self.assertRaisesRegex(ValueError, "increment"):
            release.generate(self.args)

    def test_higher_build_does_not_allow_same_or_older_marketing_version(self):
        catalog = release.generate(self.args)
        for platform in ("ios", "android"):
            catalog["latest"][platform]["build"] = "445"
        previous = self.root / "previous.json"
        self.args.previous_catalog = previous
        for previous_version in ("12.1.0", "12.1.1", "13.0.0"):
            with self.subTest(previous_version=previous_version):
                catalog["latest"]["version"] = previous_version
                release.write_json(previous, catalog)
                with self.assertRaisesRegex(ValueError, "increment the marketing version"):
                    release.generate(self.args)

    def test_marketing_versions_compare_numeric_components(self):
        catalog = release.generate(self.args)
        catalog["latest"]["version"] = "2.99.999"
        for platform in ("ios", "android"):
            catalog["latest"][platform]["build"] = "445"
        previous = self.root / "previous.json"
        release.write_json(previous, catalog)
        self.args.previous_catalog = previous
        updated = release.generate(self.args)
        self.assertEqual(updated["latest"]["version"], "12.1.0")

    def test_malformed_previous_version_is_not_silently_replaced(self):
        catalog = release.generate(self.args)
        catalog["latest"]["version"] = "unknown"
        previous = self.root / "previous.json"
        release.write_json(previous, catalog)
        self.args.previous_catalog = previous
        with self.assertRaisesRegex(ValueError, "stable SemVer"):
            release.generate(self.args)

    def test_initial_empty_catalog_allows_first_public_release(self):
        previous = self.root / "previous.json"
        release.write_json(previous, {"repository": self.args.repository, "latest": None})
        self.args.previous_catalog = previous
        catalog = release.generate(self.args)
        self.assertEqual(catalog["latest"]["version"], "12.1.0")


if __name__ == "__main__":
    unittest.main()
