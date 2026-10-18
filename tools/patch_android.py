"""เพิ่มสิทธิ์ Bluetooth/อินเทอร์เน็ตลงใน AndroidManifest.xml ที่ Flutter สร้างให้"""
import pathlib
import sys

path = pathlib.Path("android/app/src/main/AndroidManifest.xml")
text = path.read_text(encoding="utf-8")

permissions = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
"""

if "BLUETOOTH_SCAN" in text:
    print("มีสิทธิ์ Bluetooth อยู่แล้ว ข้ามขั้นตอนนี้")
    sys.exit(0)

if "<application" not in text:
    print("ไม่พบแท็ก <application> ใน AndroidManifest.xml")
    sys.exit(1)

text = text.replace("<application", permissions + "    <application", 1)
path.write_text(text, encoding="utf-8")
print("เพิ่มสิทธิ์ Bluetooth เรียบร้อย")
