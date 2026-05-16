#!/usr/bin/env python3
"""Idempotently patch the generated AndroidManifest.xml.

`flutter create` regenerates a vanilla manifest in CI every run, so we inject
the permissions + the flutter_overlay_window service here instead of committing
a hand-edited android/ folder. Safe to run multiple times.
"""
import re
import sys

MANIFEST = "android/app/src/main/AndroidManifest.xml"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.SYSTEM_ALERT_WINDOW",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.REQUEST_INSTALL_PACKAGES",
]

SERVICE = (
    '        <service\n'
    '            android:name="flutter.overlay.window.flutter_overlay_window.OverlayService"\n'
    '            android:exported="false"\n'
    '            android:stopWithTask="true"\n'
    '            android:foregroundServiceType="specialUse" />\n'
)


def main() -> int:
    with open(MANIFEST, "r", encoding="utf-8") as f:
        xml = f.read()

    # 1. Permissions: insert any missing ones right after <manifest ...>
    missing = [p for p in PERMISSIONS if f'android:name="{p}"' not in xml]
    if missing:
        block = "".join(
            f'    <uses-permission android:name="{p}"/>\n' for p in missing
        )
        xml = re.sub(
            r"(<manifest[^>]*>\n)",
            r"\1" + block,
            xml,
            count=1,
        )

    # 2. Overlay service: insert before </application> if not present
    if "flutter_overlay_window.OverlayService" not in xml:
        xml = xml.replace("    </application>", SERVICE + "    </application>", 1)

    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(xml)

    print(f"patched: +{len(missing)} permission(s), "
          f"service={'added' if 'OverlayService' in xml else 'MISSING'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
