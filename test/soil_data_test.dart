import 'package:flutter_test/flutter_test.dart';
import 'package:soilsense/models/soil_data.dart';

void main() {
  test('SoilData parses numeric strings and ISO timestamps safely', () {
    final reading = SoilData.fromMap('reading-1', {
      'fieldId': 'Field A',
      'nitrogen': '45.5',
      'phosphorus': 60,
      'potassium': 150,
      'ph': '6.4',
      'moisture': '55',
      'timestamp': '2026-08-03T12:00:00Z',
      'userId': 'user-1',
      'source': 'esp32_https',
    });

    expect(reading.nitrogen, 45.5);
    expect(reading.ph, 6.4);
    expect(reading.moisture, 55);
    expect(reading.timestamp.toUtc(), DateTime.utc(2026, 8, 3, 12));
    expect(reading.source, 'esp32_https');
  });
}
