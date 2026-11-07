#!/usr/bin/env python3
"""Generate target-specific signing settings and verify the watch-only package."""
import argparse
import datetime as dt
import os
from pathlib import Path
import plistlib
import re
import uuid

CONTAINER_ID = "jp.trap.traQ-Watch"
WATCH_ID = CONTAINER_ID + ".watchkitapp"


def profile_uuid(profile, bundle_id, team_id):
    if profile.get("TeamIdentifier") != [team_id]:
        raise ValueError(f"Provisioning profile team does not match {bundle_id}")
    entitlements = profile.get("Entitlements", {})
    application_id = entitlements.get("application-identifier", "")
    if application_id.partition(".")[2] != bundle_id:
        raise ValueError(f"Provisioning profile must use the explicit App ID {bundle_id}")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, dt.datetime) or expiry.replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc):
        raise ValueError(f"Provisioning profile expired: {bundle_id}")
    if entitlements.get("get-task-allow", False) or "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices", False):
        raise ValueError(f"App Store Connect distribution profile required: {bundle_id}")
    value = profile["UUID"]
    uuid.UUID(value)
    return value


def read_plist(path):
    with Path(path).open("rb") as stream:
        return plistlib.load(stream)


def prepare(directory, team_id):
    if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
        raise ValueError("APPLE_TEAM_ID must be a 10-character team identifier")
    app_uuid = profile_uuid(read_plist(directory / "container-profile.plist"), CONTAINER_ID, team_id)
    watch_uuid = profile_uuid(read_plist(directory / "watch-profile.plist"), WATCH_ID, team_id)
    if app_uuid == watch_uuid:
        raise ValueError("Container and Watch app require different provisioning profiles")
    export = {
        "method": "app-store-connect", "destination": "export", "signingStyle": "manual",
        "teamID": team_id, "signingCertificate": "Apple Distribution",
        "provisioningProfiles": {CONTAINER_ID: app_uuid, WATCH_ID: watch_uuid},
        "manageAppVersionAndBuildNumber": False, "testFlightInternalTestingOnly": True,
        "uploadSymbols": True,
    }
    with (directory / "ExportOptions.plist").open("wb") as stream:
        plistlib.dump(export, stream)
    # SDK conditions prevent either target's profile from overriding the other.
    (directory / "Signing.xcconfig").write_text(
        "CODE_SIGN_STYLE = Manual\n"
        "CODE_SIGN_IDENTITY = Apple Distribution\n"
        f"DEVELOPMENT_TEAM = {team_id}\n"
        f"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = {app_uuid}\n"
        f"PROVISIONING_PROFILE_SPECIFIER[sdk=watchos*] = {watch_uuid}\n"
    )
    with Path(os.environ["GITHUB_ENV"]).open("a") as stream:
        stream.write(f"CONTAINER_PROFILE_UUID={app_uuid}\nWATCH_PROFILE_UUID={watch_uuid}\n")


def verify_app(app, build_number):
    parent = read_plist(app / "Info.plist")
    watches = list((app / "Watch").glob("*.app"))
    if parent.get("CFBundleIdentifier") != CONTAINER_ID or len(watches) != 1:
        raise ValueError("Expected the distribution container with exactly one embedded Watch app")
    watch = read_plist(watches[0] / "Info.plist")
    if watch.get("CFBundleIdentifier") != WATCH_ID or watch.get("WKWatchOnly") is not True:
        raise ValueError("The embedded app must retain the Watch-only configuration")
    for info in (parent, watch):
        if info.get("CFBundleVersion") != build_number:
            raise ValueError("Container and Watch app build numbers must match the requested build")
    if parent.get("CFBundleShortVersionString") != watch.get("CFBundleShortVersionString"):
        raise ValueError("Container and Watch app marketing versions must match")
    icon = watch.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconName")
    if icon != "AppIcon" or not (watches[0] / "Assets.car").is_file():
        raise ValueError("The Watch app icon or asset catalog is missing")
    print(f"Verified Watch-only package: {CONTAINER_ID} / {WATCH_ID}, build {build_number}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    config = sub.add_parser("prepare")
    config.add_argument("directory", type=Path)
    verify = sub.add_parser("verify")
    verify.add_argument("app", type=Path)
    verify.add_argument("build_number")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.directory, os.environ["APPLE_TEAM_ID"])
    else:
        verify_app(args.app, args.build_number)


if __name__ == "__main__":
    main()
