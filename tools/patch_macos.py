"""เพิ่มสิทธิ์ Bluetooth/เครือข่ายให้โปรเจกต์ macOS ที่ Flutter สร้างให้"""
import pathlib
import plistlib
import sys


def load(path):
    with open(path, "rb") as f:
        return plistlib.load(f)


def save(path, data):
    with open(path, "wb") as f:
        plistlib.dump(data, f)


info_path = pathlib.Path("macos/Runner/Info.plist")
entitlement_paths = [
    pathlib.Path("macos/Runner/DebugProfile.entitlements"),
    pathlib.Path("macos/Runner/Release.entitlements"),
]

for p in [info_path, *entitlement_paths]:
    if not p.exists():
        print(f"ไม่พบไฟล์ {p}")
        sys.exit(1)

info = load(info_path)
info["NSBluetoothAlwaysUsageDescription"] = "ใช้เชื่อมต่อกับเครื่องอ่านโค้ด OBD2"
info["NSLocalNetworkUsageDescription"] = "ใช้เชื่อมต่อกับเครื่อง OBD2 แบบ Wi-Fi"
save(info_path, info)

for p in entitlement_paths:
    ent = load(p)
    ent["com.apple.security.device.bluetooth"] = True
    ent["com.apple.security.network.client"] = True
    save(p, ent)

print("เพิ่มสิทธิ์ Bluetooth และเครือข่ายเรียบร้อย")
