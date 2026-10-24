/// ถอดความหมายเลขตัวถัง (VIN) เท่าที่ทำได้อย่างปลอดภัย
/// ทุกค่าเป็น "ค่าโดยประมาณ" ไม่ใช่ข้อมูลทะเบียนทางการ
class VinInfo {
  const VinInfo({required this.country, this.maker, this.modelYear, required this.warnings});

  final String? country;
  final String? maker;
  final int? modelYear;
  final List<String> warnings;
}

class VinDecoder {
  /// ผู้ผลิตที่พบบ่อยในไทย ตามรหัส 3 ตัวแรก (WMI) ใช้แสดงแบบ "คาดว่า"
  static const Map<String, String> _makers = {
    'MR0': 'Toyota (ผลิตในไทย)',
    'MR2': 'Toyota (ผลิตในไทย)',
    'MHF': 'Toyota (ผลิตในไทย)',
    'MPA': 'Isuzu (ผลิตในไทย)',
    'MMT': 'Mitsubishi (ผลิตในไทย)',
    'MMB': 'Mitsubishi (ผลิตในไทย)',
    'MRH': 'Honda (ผลิตในไทย)',
    'MMM': 'Chevrolet (ผลิตในไทย)',
    'MNB': 'Ford (ผลิตในไทย)',
    'MNT': 'Nissan (ผลิตในไทย)',
    'MM8': 'Mazda (ผลิตในไทย)',
  };

  /// อักษรตำแหน่งที่ 10 บอกปีรุ่น (วนรอบ 30 ปี) สมมติว่าเป็นรอบ 2010-2039
  static const String _yearChars = 'ABCDEFGHJKLMNPRSTVWXY123456789';

  static VinInfo decode(String vin) {
    final v = vin.toUpperCase();
    final warnings = <String>[];
    if (v.length != 17) warnings.add('เลขตัวถังที่อ่านได้มี ${v.length} ตัวอักษร (ปกติ 17 ตัว) อาจอ่านไม่ครบ');
    if (RegExp(r'[IOQ]').hasMatch(v)) warnings.add('พบตัวอักษร I, O หรือ Q ซึ่งไม่ใช้ในเลขตัวถัง อาจอ่านผิด');

    String? country;
    if (v.length >= 2) {
      final c = v.substring(0, 2);
      if (c.compareTo('ML') >= 0 && c.compareTo('MR') <= 0 && c.codeUnitAt(0) == 0x4D) {
        country = 'ประเทศไทย';
      } else if (v[0] == 'J') {
        country = 'ญี่ปุ่น';
      } else if (v[0] == 'K' && c.compareTo('KL') >= 0 && c.compareTo('KR') <= 0) {
        country = 'เกาหลีใต้';
      } else if (v[0] == 'L') {
        country = 'จีน';
      } else if (c.compareTo('MA') >= 0 && c.compareTo('ME') <= 0) {
        country = 'อินเดีย';
      } else if (c.compareTo('MF') >= 0 && c.compareTo('MK') <= 0) {
        country = 'อินโดนีเซีย';
      }
    }

    final maker = v.length >= 3 ? _makers[v.substring(0, 3)] : null;

    int? year;
    if (v.length >= 10) {
      final i = _yearChars.indexOf(v[9]);
      if (i >= 0) year = 2010 + i;
    }
    return VinInfo(country: country, maker: maker, modelYear: year, warnings: warnings);
  }
}
