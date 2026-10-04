import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/alert.dart';
import '../models/soil_data.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StreamController<bool> _readingResetController = StreamController<bool>.broadcast();

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> get _deviceAssignment =>
      _firestore.collection('system').doc('device_assignment');

  DocumentReference<Map<String, dynamic>> get _scanSettings =>
      _firestore.collection('system').doc('scan_settings');

  static const int defaultScanDurationSeconds = 120;
  static const int minScanDurationSeconds = 30;
  static const int maxScanDurationSeconds = 300;

  int _normalizeScanDuration(dynamic value) {
    final parsed = value is num ? value.toInt() : defaultScanDurationSeconds;
    return parsed.clamp(minScanDurationSeconds, maxScanDurationSeconds).toInt();
  }

  Stream<int> watchScanDurationSeconds() async* {
    try {
      await for (final snapshot in _scanSettings.snapshots()) {
        yield _normalizeScanDuration(snapshot.data()?['durationSeconds']);
      }
    } catch (error) {
      debugPrint('Scan duration stream failed: $error');
      yield defaultScanDurationSeconds;
    }
  }

  Future<int> getScanDurationSeconds() async {
    try {
      final snapshot = await _scanSettings.get();
      return _normalizeScanDuration(snapshot.data()?['durationSeconds']);
    } catch (error) {
      debugPrint('Scan duration lookup failed: $error');
      return defaultScanDurationSeconds;
    }
  }

  Future<void> setScanDurationSeconds(int seconds) async {
    if (!await isCurrentUserOwner()) {
      throw StateError('Only the current SoilSense device owner can change the scan duration.');
    }

    final normalized = seconds.clamp(
      minScanDurationSeconds,
      maxScanDurationSeconds,
    ).toInt();

    await _scanSettings.set({
      'durationSeconds': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> isCurrentUserOwner() async {
    final userId = _userId;
    if (userId == null) return false;
    try {
      final snapshot = await _deviceAssignment.get();
      return snapshot.data()?['currentOwnerUid'] == userId;
    } catch (error) {
      debugPrint('Current owner check failed: $error');
      return false;
    }
  }

  Stream<bool> watchOwnerAccess() async* {
    final userId = _userId;
    if (userId == null) {
      yield false;
      return;
    }
    try {
      await for (final snapshot in _deviceAssignment.snapshots()) {
        yield snapshot.data()?['currentOwnerUid'] == userId;
      }
    } catch (error) {
      debugPrint('Current owner stream failed: $error');
      yield false;
    }
  }

  Future<List<SoilData>> getSoilReadings({
    String? fieldId,
    int limit = 100,
    bool includeClearedHistory = false,
  }) async {
    final userId = _userId;
    if (userId == null) return [];

    try {
      final snapshot = await _firestore
          .collection(AppConfig.soilReadingsCollection)
          .where('ownerUid', isEqualTo: userId)
          .get();

      var readings = snapshot.docs
          .where((doc) => _isLiveSensorReading(doc.id, doc.data()))
          .map((doc) => SoilData.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (!includeClearedHistory) {
        final clearedAt = await _getReadingHistoryClearedAt();
        if (clearedAt != null) {
          readings = readings
              .where((reading) => reading.timestamp.isAfter(clearedAt))
              .toList();
        }
      } else {
        // Current/live views respect the user's Reset Current Reading cutoff.
        // History intentionally does not, so Reset never destroys saved records.
        final resetAt = await _getCurrentReadingResetAt();
        if (resetAt != null) {
          readings = readings
              .where((reading) => reading.timestamp.isAfter(resetAt))
              .toList();
        }
      }

      return readings.take(limit).toList();
    } catch (error) {
      debugPrint('Private soil query failed: $error');
      return [];
    }
  }

  DocumentReference<Map<String, dynamic>>? get _readingHistoryPreference {
    final userId = _userId;
    if (userId == null) return null;
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('preferences')
        .doc('history');
  }

  Future<DateTime?> _getReadingHistoryClearedAt() async {
    final ref = _readingHistoryPreference;
    if (ref == null) return null;
    try {
      final snapshot = await ref.get();
      final value = snapshot.data()?['readingHistoryClearedAt'];
      return value is Timestamp ? value.toDate() : null;
    } catch (error) {
      debugPrint('Reading history preference lookup failed: $error');
      return null;
    }
  }

  String? get _currentReadingResetPreferenceKey {
    final userId = _userId;
    return userId == null ? null : 'soilsense_current_reading_reset_$userId';
  }

  Future<DateTime?> _getCurrentReadingResetAt() async {
    final key = _currentReadingResetPreferenceKey;
    if (key == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final milliseconds = prefs.getInt(key);
      return milliseconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(milliseconds);
    } catch (error) {
      debugPrint('Current reading reset preference lookup failed: $error');
      return null;
    }
  }

  Future<void> resetCurrentReading() async {
    final userId = _userId;
    final key = _currentReadingResetPreferenceKey;
    if (userId == null || key == null) {
      throw StateError('You must be signed in to reset the current reading.');
    }

    final snapshot = await _firestore
        .collection(AppConfig.soilReadingsCollection)
        .where('ownerUid', isEqualTo: userId)
        .get();
    final readings = snapshot.docs
        .where((doc) => _isLiveSensorReading(doc.id, doc.data()))
        .map((doc) => SoilData.fromMap(doc.id, doc.data()))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Reset affects only this app's Current Reading display. Saved Firestore
    // history is intentionally preserved, and no fake zero-valued reading is
    // uploaded. A newer completed scan automatically becomes visible again.
    final cutoff = readings.isEmpty ? DateTime.now() : readings.first.timestamp;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, cutoff.millisecondsSinceEpoch);
    _readingResetController.add(true);
  }

  Future<void> deleteSoilReading(String readingId) async {
    final userId = _userId;
    if (userId == null || readingId.trim().isEmpty) {
      throw StateError('You must be signed in to delete a soil reading.');
    }

    final ref = _firestore
        .collection(AppConfig.soilReadingsCollection)
        .doc(readingId.trim());
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return;
    if (data['ownerUid'] != userId) {
      throw StateError('This soil reading does not belong to the current account.');
    }
    await ref.delete();
  }

  Future<int> clearSoilReadingHistory() async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('You must be signed in to clear soil history.');
    }

    final snapshot = await _firestore
        .collection(AppConfig.soilReadingsCollection)
        .where('ownerUid', isEqualTo: userId)
        .get();
    final docs = snapshot.docs
        .where((doc) => _isLiveSensorReading(doc.id, doc.data()))
        .toList()
      ..sort((a, b) {
        final aReading = SoilData.fromMap(a.id, a.data());
        final bReading = SoilData.fromMap(b.id, b.data());
        return bReading.timestamp.compareTo(aReading.timestamp);
      });

    if (docs.isEmpty) return 0;

    // Clearing history intentionally keeps the newest completed reading as the
    // account's current reading. The cutoff hides that retained reading (and
    // anything older) from History/Trends while Home, Analysis, AI, Crops and
    // Reports can continue using it. New scans are newer than this cutoff and
    // start a fresh history automatically.
    final latest = SoilData.fromMap(docs.first.id, docs.first.data());
    final historyRef = _readingHistoryPreference;
    if (historyRef == null) {
      throw StateError("Could not access this account's history preference.");
    }
    await historyRef.set({
      'readingHistoryClearedAt': Timestamp.fromDate(latest.timestamp),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Older history is removed from Firestore. The newest document is retained
    // so clearing history never turns a real latest reading into a fake zero.
    final oldDocs = docs.skip(1).toList();
    const chunkSize = 450;
    for (var start = 0; start < oldDocs.length; start += chunkSize) {
      final batch = _firestore.batch();
      final end = (start + chunkSize < oldDocs.length)
          ? start + chunkSize
          : oldDocs.length;
      for (final doc in oldDocs.sublist(start, end)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // Count how many entries disappeared from the History UI, including the
    // retained latest reading which is now hidden behind the cutoff.
    return docs.length;
  }

  Stream<SoilData?> watchLatestSoilReading() async* {
    final userId = _userId;
    if (userId == null) {
      yield null;
      return;
    }

    final controller = StreamController<SoilData?>();
    List<SoilData> readings = const <SoilData>[];
    DateTime? resetAt = await _getCurrentReadingResetAt();
    bool readingsReady = false;

    void emitLatest() {
      if (!readingsReady || controller.isClosed) return;
      final visible = resetAt == null
          ? readings
          : readings.where((reading) => reading.timestamp.isAfter(resetAt!)).toList();
      controller.add(visible.isEmpty ? null : visible.first);
    }

    final readingSubscription = _firestore
        .collection(AppConfig.soilReadingsCollection)
        .where('ownerUid', isEqualTo: userId)
        .snapshots()
        .listen(
      (snapshot) {
        readings = snapshot.docs
            .where((doc) => _isLiveSensorReading(doc.id, doc.data()))
            .map((doc) => SoilData.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        readingsReady = true;
        emitLatest();
      },
      onError: (Object error) {
        debugPrint('Latest private soil stream failed: $error');
        if (!controller.isClosed) controller.add(null);
      },
    );

    final resetSubscription = _readingResetController.stream.listen((_) async {
      resetAt = await _getCurrentReadingResetAt();
      emitLatest();
    });

    try {
      await for (final reading in controller.stream) {
        yield reading;
      }
    } finally {
      await readingSubscription.cancel();
      await resetSubscription.cancel();
      await controller.close();
    }
  }

  Stream<SoilData?> getLatestSoilReading(String fieldId) async* {
    yield* watchLatestSoilReading();
  }

  Future<Map<String, dynamic>?> getLatestSoilAnalysis() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final snapshot = await _firestore
          .collection(AppConfig.soilAnalysesCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      return snapshot.docs.isEmpty ? null : snapshot.docs.first.data();
    } catch (e) {
      debugPrint('GetLatestSoilAnalysis Error: $e');
      return null;
    }
  }

  Future<List<Alert>> getAlerts({bool? unreadOnly}) async {
    final userId = _userId;
    if (userId == null) return [];
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(AppConfig.alertsCollection)
          .where('userId', isEqualTo: userId);
      if (unreadOnly == true) query = query.where('read', isEqualTo: false);
      final snapshot = await query
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();
      final alerts = snapshot.docs
          .where((doc) => _isLiveAlert(doc.id, doc.data()))
          .map((doc) => Alert.fromMap(doc.id, doc.data()))
          .toList();
      return alerts;
    } catch (e) {
      debugPrint('GetAlerts ordered query failed: $e');
      try {
        Query<Map<String, dynamic>> query = _firestore
            .collection(AppConfig.alertsCollection)
            .where('userId', isEqualTo: userId);
        if (unreadOnly == true) query = query.where('read', isEqualTo: false);
        final snapshot = await query.limit(200).get();
        final alerts = snapshot.docs
            .where((doc) => _isLiveAlert(doc.id, doc.data()))
            .map((doc) => Alert.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return alerts;
      } catch (fallbackError) {
        debugPrint('GetAlerts fallback failed: $fallbackError');
        return [];
      }
    }
  }

  Stream<List<Alert>> getAlertsStream() async* {
    final userId = _userId;
    if (userId == null) {
      yield [];
      return;
    }

    try {
      await for (final snapshot in _firestore
          .collection(AppConfig.alertsCollection)
          .where('userId', isEqualTo: userId)
          .limit(200)
          .snapshots()) {
        final alerts = snapshot.docs
            .where((doc) => _isLiveAlert(doc.id, doc.data()))
            .map((doc) => Alert.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        yield alerts;
      }
    } catch (error) {
      debugPrint('GetAlertsStream Error: $error');
      yield [];
    }
  }

  Future<void> markAlertRead(String alertId) async {
    await _firestore.collection(AppConfig.alertsCollection).doc(alertId).update({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAllAlertsRead() async {
    final userId = _userId;
    if (userId == null) return;
    final snapshot = await _firestore
        .collection(AppConfig.alertsCollection)
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> deleteAlert(String alertId) async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('You must be signed in to delete a notification.');
    }

    final reference =
        _firestore.collection(AppConfig.alertsCollection).doc(alertId);
    final snapshot = await reference.get();
    if (!snapshot.exists) return;

    final data = snapshot.data();
    if (data == null || data['userId'] != userId) {
      throw StateError('You cannot delete this notification.');
    }

    await reference.delete();
  }

  Future<void> deleteAllAlerts() async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('You must be signed in to clear notifications.');
    }

    // Firestore batches are limited to 500 operations. Delete in smaller
    // chunks so this remains safe even if a user has many notifications.
    while (true) {
      final snapshot = await _firestore
          .collection(AppConfig.alertsCollection)
          .where('userId', isEqualTo: userId)
          .limit(400)
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < 400) return;
    }
  }

  Future<List<Map<String, dynamic>>> getReports({int limit = 8}) async {
    final userId = _userId;
    if (userId == null) return [];
    try {
      final snapshot = await _firestore
          .collection(AppConfig.reportsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs
          .where((doc) => _isLiveReport(doc.id, doc.data()))
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      debugPrint('GetReports ordered query failed: $e');
      try {
        final snapshot = await _firestore
            .collection(AppConfig.reportsCollection)
            .where('userId', isEqualTo: userId)
            .limit(200)
            .get();
        final reports = snapshot.docs
            .where((doc) => _isLiveReport(doc.id, doc.data()))
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList();
        reports.sort((a, b) =>
            _dateFrom(a['timestamp']).compareTo(_dateFrom(b['timestamp'])) * -1);
        return reports.take(limit).toList();
      } catch (fallbackError) {
        debugPrint('GetReports fallback failed: $fallbackError');
        return [];
      }
    }
  }

  Future<String> saveReport(Map<String, dynamic> reportData) async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('You must be signed in to save a report.');
    }
    final reference = await _firestore.collection(AppConfig.reportsCollection).add({
      ...reportData,
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
    });
    try {
      await trimReportsToLimit(8);
    } catch (error) {
      debugPrint('Report retention cleanup failed: $error');
    }
    return reference.id;
  }


  Future<Map<String, dynamic>?> getReportForReading(
    String readingId, {
    String? readingFingerprint,
  }) async {
    final reports = await getReports(limit: 50);
    for (final report in reports) {
      final sameReading =
          (report['sourceReadingId'] ?? '').toString() == readingId;
      final fingerprint =
          (report['sourceReadingFingerprint'] ?? '').toString();
      final fingerprintMatches = readingFingerprint == null ||
          readingFingerprint.isEmpty ||
          fingerprint.isEmpty ||
          fingerprint == readingFingerprint;
      if (sameReading && fingerprintMatches) return report;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getAutomaticReportForReading(
    String readingId, {
    String? readingFingerprint,
  }) async {
    final reports = await getReports(limit: 50);
    for (final report in reports) {
      final sameReading =
          (report['sourceReadingId'] ?? '').toString() == readingId;
      final automatic = report['automatic'] == true;
      final fingerprint =
          (report['sourceReadingFingerprint'] ?? '').toString();
      final fingerprintMatches = readingFingerprint == null ||
          readingFingerprint.isEmpty ||
          fingerprint == readingFingerprint;
      if (sameReading && automatic && fingerprintMatches) return report;
    }
    return null;
  }

  /// Saves one automatic AI report for a completed soil reading.
  ///
  /// Existing reports are checked through an user-scoped query first so the
  /// mobile client never needs permission to read a missing document ID.
  Future<String> saveAutomaticReportForReading(
    Map<String, dynamic> reportData,
    String readingId,
  ) async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('You must be signed in to save a report.');
    }

    final readingFingerprint =
        (reportData['sourceReadingFingerprint'] ?? '').toString();
    final existing = await getAutomaticReportForReading(
      readingId,
      readingFingerprint: readingFingerprint,
    );
    if (existing != null) {
      return (existing['id'] ?? '').toString();
    }

    final reference = await _firestore.collection(AppConfig.reportsCollection).add({
      ...reportData,
      'userId': userId,
      'sourceReadingId': readingId,
      'timestamp': FieldValue.serverTimestamp(),
    });
    try {
      await trimReportsToLimit(8);
    } catch (error) {
      debugPrint('Automatic report retention cleanup failed: $error');
    }
    return reference.id;
  }

  Future<void> deleteReport(String reportId) async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('You must be signed in to delete a report.');
    }
    final reference =
        _firestore.collection(AppConfig.reportsCollection).doc(reportId);
    final snapshot = await reference.get();
    if (!snapshot.exists || snapshot.data()?['userId'] != userId) {
      throw StateError('This report is unavailable or does not belong to you.');
    }
    await reference.delete();
  }

  Future<void> trimReportsToLimit(int maxItems) async {
    final userId = _userId;
    if (userId == null || maxItems < 0) return;
    final snapshot = await _firestore
        .collection(AppConfig.reportsCollection)
        .where('userId', isEqualTo: userId)
        .get();
    final documents = snapshot.docs.toList()
      ..sort((a, b) =>
          _dateFrom(b.data()['timestamp']).compareTo(_dateFrom(a.data()['timestamp'])));
    await _deleteReferences(documents.skip(maxItems).map((doc) => doc.reference));
  }

  Future<void> trimSoilReadingsToLimit(int maxItems) async {
    // Private sensor history is never deleted by the mobile client. The UI may
    // limit how many readings it displays without removing Firestore data.
    return;
  }

  Future<void> _deleteReferences(
    Iterable<DocumentReference<Map<String, dynamic>>> references,
  ) async {
    final items = references.toList();
    for (var start = 0; start < items.length; start += 400) {
      final end = (start + 400 < items.length) ? start + 400 : items.length;
      final batch = _firestore.batch();
      for (final reference in items.sublist(start, end)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
  }

  Future<Map<String, int>> getProfileStats() async {
    final userId = _userId;
    if (userId == null) return {'readings': 0, 'reports': 0, 'notifications': 0};
    final readings = await getSoilReadings(limit: 250);
    final reports = await getReports();
    final alerts = await getAlerts();
    return {
      'readings': readings.length,
      'reports': reports.length,
      'notifications': alerts.length,
    };
  }
  static bool _isLiveSensorReading(
    String documentId,
    Map<String, dynamic> data,
  ) {
    return documentId.isNotEmpty && data['source'] == 'esp32_https';
  }

  static bool _isLiveAlert(String documentId, Map<String, dynamic> data) {
    return documentId.isNotEmpty && (data['message'] ?? '').toString().isNotEmpty;
  }

  static bool _isLiveReport(String documentId, Map<String, dynamic> data) {
    final readingId = (data['sourceReadingId'] ?? '').toString();
    return documentId.isNotEmpty && readingId.isNotEmpty;
  }

  static DateTime _dateFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
}
