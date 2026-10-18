# แอปเช็คโค้ดรถ OBD2 (ภาษาไทย)

แอป Flutter สำหรับ Android และ iPhone เชื่อมต่อกับเครื่อง OBD2 ที่ใช้ชิป ELM327 ทั้งแบบ Bluetooth (BLE) และ Wi-Fi
ทำได้: อ่านโค้ดปัญหา (Mode 03), ล้างโค้ด (Mode 04), ดูข้อมูลสด (Mode 01) พร้อมคำอธิบายโค้ดภาษาไทย

> สถานะ: ร่างแรก ยังไม่ได้ทดสอบกับเครื่อง VPEAK และรถจริง ควรทดสอบบนรถที่จอดอยู่ก่อน

## วิธีเริ่มต้น

1. ติดตั้ง Flutter SDK (https://docs.flutter.dev/get-started/install)
2. สร้างโปรเจกต์เปล่าแล้วคัดลอกไฟล์ในชุดนี้ทับ

   ```
   flutter create obd_thai --platforms=android,ios
   ```

   คัดลอกโฟลเดอร์ `lib/` และไฟล์ `pubspec.yaml` ในชุดนี้ไปทับของโปรเจกต์ที่เพิ่งสร้าง
3. ติดตั้งแพ็กเกจ แล้วเพิ่มสิทธิ์ตามหัวข้อด้านล่าง

   ```
   flutter pub get
   ```
4. ต่อโทรศัพท์จริง (Bluetooth ใช้ในตัวจำลองไม่ได้) แล้วรัน

   ```
   flutter run
   ```

## สิทธิ์ที่ต้องเพิ่ม

### Android: `android/app/src/main/AndroidManifest.xml`

เพิ่มไว้ก่อนแท็ก `<application>`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
```

ถ้า `flutter run` แจ้งว่า minSdkVersion ต่ำเกินไป ให้ตั้ง `minSdk = 21` (หรือสูงกว่าตามที่แจ้ง) ใน `android/app/build.gradle`

### iPhone: `ios/Runner/Info.plist`

เพิ่มภายใน `<dict>`

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>ใช้เชื่อมต่อกับเครื่องอ่านโค้ด OBD2</string>
<key>NSLocalNetworkUsageDescription</key>
<string>ใช้เชื่อมต่อกับเครื่อง OBD2 แบบ Wi-Fi</string>
```

## โครงสร้างโค้ด

| ไฟล์ | หน้าที่ |
|---|---|
| `lib/obd/transport.dart` | ช่องทางสื่อสาร BLE และ Wi-Fi (TCP) |
| `lib/obd/elm327.dart` | คำสั่ง AT/OBD2, ตัวแยกคำตอบ, อ่าน/ล้างโค้ด, ข้อมูลสด |
| `lib/obd/dtc_database.dart` | คำอธิบายโค้ดภาษาไทย (โค้ดมาตรฐานที่พบบ่อย) |
| `lib/screens/` | หน้าเชื่อมต่อ, ภาพรวม, โค้ดปัญหา, ข้อมูลสด |

## ข้อจำกัดที่ควรรู้

- **เครื่อง Bluetooth Classic ไม่ใช่ BLE** แอปนี้ค้นหาไม่เจอ และ iPhone ใช้ไม่ได้เลย ถ้าเครื่องของคุณเป็นแบบนี้และใช้ Android อย่างเดียว ต้องเพิ่มการเชื่อมต่อแบบ Classic แยก
- **เครื่อง Wi-Fi**: ค่าเริ่มต้น `192.168.0.10:35000` เป็นค่าที่พบบ่อย ถ้าเครื่องของคุณต่างออกไปให้แก้ที่ `WifiTransport` ใน `transport.dart`
- **โค้ดเฉพาะยี่ห้อ** (เช่น P1xxx) และระบบอื่นนอกเครื่องยนต์ (ABS, airbag) ไม่ครอบคลุมในเวอร์ชันนี้ แอปแสดงเพียงคำอธิบายทั่วไปตามหมวด
- คำอธิบายภาษาไทยมีเฉพาะโค้ดที่พบบ่อยประมาณ 30 โค้ด เพิ่มได้ใน `dtc_database.dart`
- แพ็กเกจ `flutter_blue_plus` ล็อกไว้ที่เวอร์ชัน 1.x หากอัปเกรดเป็น 2.x อาจต้องแก้ชื่อ API บางส่วน
