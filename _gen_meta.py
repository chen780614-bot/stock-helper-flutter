# -*- coding: utf-8 -*-
from pathlib import Path
root = Path(r"C:\Users\user\Documents\stock-helper-flutter")

# Update pubspec
pub = (root / "pubspec.yaml").read_text(encoding="utf-8")
pub = pub.replace("version: 1.0.3+4", "version: 1.0.4+5")
if "google_mlkit_text_recognition" not in pub:
    pub = pub.replace(
        "  google_mobile_ads: 9.1.0\n",
        "  google_mobile_ads: 9.1.0\n"
        "  image_picker: ^1.2.0\n"
        "  google_mlkit_text_recognition: ^0.15.0\n",
    )
(root / "pubspec.yaml").write_text(pub, encoding="utf-8")
print("pubspec updated")

# AndroidManifest permissions
manifest_path = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
man = manifest_path.read_text(encoding="utf-8")
if "READ_MEDIA_IMAGES" not in man:
    man = man.replace(
        '    <uses-permission android:name="com.google.android.gms.permission.AD_ID"/>\n',
        '    <uses-permission android:name="com.google.android.gms.permission.AD_ID"/>\n'
        '    <!-- Gallery / camera for on-device holdings OCR import -->\n'
        '    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>\n'
        '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>\n'
        '    <uses-permission android:name="android.permission.CAMERA"/>\n'
        '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n',
    )
    manifest_path.write_text(man, encoding="utf-8")
    print("manifest updated")
else:
    print("manifest already has READ_MEDIA_IMAGES")
