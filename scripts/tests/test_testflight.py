import copy
import datetime as dt
import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("testflight", Path(__file__).resolve().parents[1] / "testflight.py")
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)
TEAM = "ABCDE12345"


def profile(bundle_id, profile_id):
    return {
        "UUID": profile_id, "TeamIdentifier": [TEAM],
        "ExpirationDate": dt.datetime.now(dt.timezone.utc).replace(tzinfo=None) + dt.timedelta(days=30),
        "Entitlements": {"application-identifier": f"{TEAM}.{bundle_id}", "get-task-allow": False},
    }


class TestDistribution(unittest.TestCase):
    def test_rejects_wrong_app_team_expired_or_device_profiles(self):
        valid = profile(ci.WATCH_ID, "11111111-1111-1111-1111-111111111111")
        self.assertEqual(ci.profile_uuid(valid, ci.WATCH_ID, TEAM), valid["UUID"])
        bad_profiles = []
        for key, value in [("TeamIdentifier", ["OTHER12345"]), ("ExpirationDate", dt.datetime(2000, 1, 1)),
                           ("ProvisionedDevices", ["device"]), ("ProvisionsAllDevices", True)]:
            bad = copy.deepcopy(valid)
            bad[key] = value
            bad_profiles.append(bad)
        for app in [ci.CONTAINER_ID, "jp.trap.FirstApp", "*"]:
            bad = copy.deepcopy(valid)
            bad["Entitlements"]["application-identifier"] = f"{TEAM}.{app}"
            bad_profiles.append(bad)
        bad = copy.deepcopy(valid)
        bad["Entitlements"]["get-task-allow"] = True
        bad_profiles.append(bad)
        for bad in bad_profiles:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                ci.profile_uuid(bad, ci.WATCH_ID, TEAM)

    def test_prepare_maps_each_profile_and_limits_distribution_to_internal_testflight(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app = profile(ci.CONTAINER_ID, "11111111-1111-1111-1111-111111111111")
            watch = profile(ci.WATCH_ID, "22222222-2222-2222-2222-222222222222")
            for filename, value in [("container-profile.plist", app), ("watch-profile.plist", watch)]:
                (root / filename).write_bytes(plistlib.dumps(value))
            with patch.dict(os.environ, {"GITHUB_ENV": str(root / "env")}):
                ci.prepare(root, TEAM)
            exported = ci.read_plist(root / "ExportOptions.plist")
            self.assertEqual(exported["provisioningProfiles"], {ci.CONTAINER_ID: app["UUID"], ci.WATCH_ID: watch["UUID"]})
            self.assertTrue(exported["testFlightInternalTestingOnly"])
            self.assertFalse(exported["manageAppVersionAndBuildNumber"])
            config = (root / "Signing.xcconfig").read_text()
            self.assertIn(f'PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = {app["UUID"]}', config)
            self.assertIn(f'PROVISIONING_PROFILE_SPECIFIER[sdk=watchos*] = {watch["UUID"]}', config)
            self.assertNotIn("PRODUCT_BUNDLE_IDENTIFIER", config)

    def test_verify_package_requires_watch_only_matching_versions_and_icon(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / "App.app"
            watch = app / "Watch" / "Watch.app"
            watch.mkdir(parents=True)
            parent_info = {"CFBundleIdentifier": ci.CONTAINER_ID, "CFBundleVersion": "1.1", "CFBundleShortVersionString": "1.0"}
            watch_info = {"CFBundleIdentifier": ci.WATCH_ID, "CFBundleVersion": "1.1", "CFBundleShortVersionString": "1.0",
                          "WKWatchOnly": True, "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon"}}}
            (app / "Info.plist").write_bytes(plistlib.dumps(parent_info))
            (watch / "Info.plist").write_bytes(plistlib.dumps(watch_info))
            (watch / "Assets.car").touch()
            ci.verify_app(app, "1.1")
            for key, value in [("CFBundleVersion", "2"), ("CFBundleShortVersionString", "2.0"),
                               ("WKWatchOnly", False), ("CFBundleIdentifier", "jp.trap.FirstApp")]:
                altered = dict(watch_info, **{key: value})
                (watch / "Info.plist").write_bytes(plistlib.dumps(altered))
                with self.subTest(key=key), self.assertRaises(ValueError):
                    ci.verify_app(app, "1.1")


if __name__ == "__main__":
    unittest.main()
