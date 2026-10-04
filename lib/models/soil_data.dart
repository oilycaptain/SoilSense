import 'package:cloud_firestore/cloud_firestore.dart';

class SoilData {
  final String id;
  final String fieldId;
  final double nitrogen;
  final double phosphorus;
  final double potassium;
  final double ph;
  final double moisture;
  final double? soilTemperature;
  final int? electricalConductivity;
  final DateTime timestamp;
  final String userId;
  final String source;

  SoilData({
    required this.id,
    required this.fieldId,
    required this.nitrogen,
    required this.phosphorus,
    required this.potassium,
    required this.ph,
    required this.moisture,
    this.soilTemperature,
    this.electricalConductivity,
    required this.timestamp,
    required this.userId,
    this.source = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'fieldId': fieldId,
      'nitrogen': nitrogen,
      'phosphorus': phosphorus,
      'potassium': potassium,
      'ph': ph,
      'moisture': moisture,
      if (soilTemperature != null) 'soilTemperature': soilTemperature,
      if (electricalConductivity != null)
        'electricalConductivity': electricalConductivity,
      'timestamp': timestamp,
      'userId': userId,
      'source': source,
    };
  }

  factory SoilData.fromMap(String id, Map<String, dynamic> map) {
    return SoilData(
      id: id,
      fieldId: (map['fieldId'] ?? '').toString(),
      nitrogen: _asDouble(map['nitrogen']),
      phosphorus: _asDouble(map['phosphorus']),
      potassium: _asDouble(map['potassium']),
      ph: _asDouble(map['ph']),
      moisture: _asDouble(map['moisture']),
      soilTemperature: _asNullableDouble(map['soilTemperature']),
      electricalConductivity: _asNullableInt(map['electricalConductivity']),
      timestamp: _asDate(map['timestamp']),
      userId: (map['userId'] ?? '').toString(),
      source: (map['source'] ?? '').toString(),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _asNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  static DateTime _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }

  String get fertilityLevel {
    double score = (nitrogen / 100 + phosphorus / 100 + potassium / 100) / 3 * 100;
    if (score > 70) return 'High';
    if (score > 40) return 'Medium';
    return 'Low';
  }

  List<String> get deficiencies {
    List<String> deficient = [];
    if (phosphorus < 50) deficient.add('Phosphorus');
    if (nitrogen < 40) deficient.add('Nitrogen');
    if (potassium < 100) deficient.add('Potassium');
    if (ph < 5.5 || ph > 7.5) deficient.add('pH Imbalance');
    if (moisture < 40) deficient.add('Moisture');
    return deficient;
  }
}
