import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Alert {
  final String id;
  final String title;
  final String type;
  final String severity;
  final String category;
  final String message;
  final double currentValue;
  final String optimalRange;
  final bool read;
  final DateTime timestamp;
  final String userId;

  Alert({
    required this.id,
    required this.title,
    required this.type,
    required this.severity,
    required this.category,
    required this.message,
    required this.currentValue,
    required this.optimalRange,
    required this.read,
    required this.timestamp,
    required this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'type': type,
      'severity': severity,
      'category': category,
      'message': message,
      'currentValue': currentValue,
      'optimalRange': optimalRange,
      'read': read,
      'timestamp': timestamp,
      'userId': userId,
    };
  }

  factory Alert.fromMap(String id, Map<String, dynamic> map) {
    return Alert(
      id: id,
      title: (map['title'] ?? map['category'] ?? 'SoilSense').toString(),
      type: (map['type'] ?? '').toString(),
      severity: (map['severity'] ?? 'low').toString(),
      category: (map['category'] ?? '').toString(),
      message: (map['message'] ?? '').toString(),
      currentValue: _asDouble(map['currentValue']),
      optimalRange: (map['optimalRange'] ?? '').toString(),
      read: map['read'] == true,
      timestamp: _asDate(map['timestamp']),
      userId: (map['userId'] ?? '').toString(),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }

  Color get severityColor {
    switch (severity) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}