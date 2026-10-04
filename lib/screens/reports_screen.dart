import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../models/soil_data.dart';
import '../services/firestore_service.dart';
import '../services/file_download_service.dart';
import '../services/report_service.dart';
import '../services/decision_support_service.dart';
import '../services/device_status_service.dart';
import '../widgets/navigation_bar.dart';
import '../widgets/user_app_bar_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/data_refresh_info_button.dart';
import '../widgets/motion.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  bool _isGeneratingReport = false;
  final Set<String> _deletingReportIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadReports();
  }


  Future<void> _loadReports() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final firestore = context.read<FirestoreService>();
      try {
        await firestore.trimReportsToLimit(8);
      } catch (error) {
        debugPrint('Report retention cleanup failed: $error');
      }
      final reports = await firestore.getReports(limit: 8);
      if (mounted) setState(() => _reports = reports);
    } catch (e) {
      _showSnackBar('Could not load reports: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    final deviceStatus = context.read<DeviceStatusService>();
    await deviceStatus.refresh();
    if (!mounted) return;
    await _loadReports();
  }


  @override
  Widget build(BuildContext context) {
    final deviceStatus = context.watch<DeviceStatusService>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: SoilSenseInfoButton(),
        title: Text('Reports'),
        centerTitle: true,
        actions: soilSenseUserActions(context),
      ),
      body: _buildBody(deviceStatus),
      bottomNavigationBar: SoilSenseNavBar(currentIndex: 3),
    );
  }

  Widget _buildBody(DeviceStatusService deviceStatus) {
    final hasReading = deviceStatus.hasDisplayReading;
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (!hasReading) ...[
            _buildNoReadingNotice(),
            SizedBox(height: 14),
          ],
          SoilSenseReveal(
            child: _buildReportGeneratorCard(hasReading: hasReading),
          ),
          SizedBox(height: 20),
          Text(
            'Saved Reports (${_reports.length}/8)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 10),
          if (_reports.isEmpty && !_isLoading)
            Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 52,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No saved reports yet. Previous reports will remain available here even when the device is offline.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._reports.map(_buildReportCard),
        ],
      ),
    );
  }

  Widget _buildNoReadingNotice() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.sensors_off_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No device reading yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Connect the SoilSense device and complete its first scan to generate a new report. Saved reports can still be opened below.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportGeneratorCard({required bool hasReading}) {
    final reading = context.watch<DeviceStatusService>().displayReading;
    final alreadySaved = _hasReportForReading(reading);
    final canGenerate = hasReading && reading != null && !_isGeneratingReport;
    final limitReached = _reports.length >= 8;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (hasReading ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant)
                        .withOpacity(.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: hasReading ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasReading ? 'Generate Soil Report' : 'Soil Report Unavailable',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                              ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        hasReading
                            ? 'Creates the report from the latest completed reading, saves it in SoilSense, and downloads the PDF directly to your phone. No AI request is required.'
                            : 'Complete a new soil scan first. Saved reports remain available below.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (alreadySaved) ...[
              SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(.055),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'A report for this soil reading is already saved. You can generate another copy if needed.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canGenerate ? _handleGenerateReport : null,
                icon: _isGeneratingReport
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.description_outlined),
                label: Text(
                  _isGeneratingReport ? 'Generating & Downloading...' : 'Generate & Download Report',
                ),
              ),
            ),
            if (limitReached && canGenerate) ...[
              SizedBox(height: 8),
              Text(
                'Saved report limit reached. Generating a new report will remove the oldest saved report after confirmation.',
                style: TextStyle(
                  fontSize: 10.8,
                  height: 1.35,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final date = _toDate(report['timestamp'] ?? report['generatedAt']);
    final analysis = _asMap(report['analysis']);
    final recommendations = _asMap(report['recommendations']);
    final rawBestCrop = _asMap(recommendations['best_crop']);
    final bestCropScore = (rawBestCrop['score'] as num?)?.toDouble() ?? 0;
    final bestCrop = bestCropScore >=
            DecisionSupportService.minimumRecommendedCropScore
        ? rawBestCrop
        : <String, dynamic>{};
    final reportId = (report['id'] ?? '').toString();
    final isDeleting = _deletingReportIds.contains(reportId);

    return SoilSenseReveal(
      child: Card(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(.1),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.analytics_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (report['title'] ?? 'SoilSense Report').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                              ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${date.day}/${date.month}/${date.year}  ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 4),
                if (isDeleting)
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  PopupMenuButton<String>(
                    tooltip: 'Report options',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      ),
                    onSelected: (value) {
                      switch (value) {
                        case 'download':
                          _downloadReport(report);
                          break;
                        case 'print':
                          _printReport(report);
                          break;
                        case 'delete':
                          _confirmDeleteReport(report);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      _reportMenuItem(
                        value: 'download',
                        icon: Icons.download_rounded,
                        label: 'Download PDF',
                      ),
                      _reportMenuItem(
                        value: 'print',
                        icon: Icons.print_outlined,
                        label: 'Print report',
                      ),
                      PopupMenuDivider(),
                      _reportMenuItem(
                        value: 'delete',
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete report',
                        destructive: true,
                      ),
                    ],
                  ),
              ],
            ),
            SizedBox(height: 14),
            _buildReportSummary(analysis: analysis, bestCrop: bestCrop),
          ],
        ),
      ),
      ),
    );
  }

  PopupMenuItem<String> _reportMenuItem({
    required String value,
    required IconData icon,
    required String label,
    bool destructive = false,
  }) {
    final color = destructive
        ? AppTheme.warningRed
        : Theme.of(context).colorScheme.onSurface;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportSummary({
    required Map<String, dynamic> analysis,
    required Map<String, dynamic> bestCrop,
  }) {
    final scoreValue = analysis['balance_score'] ?? analysis['fertility_score'];
    final numericScore = scoreValue is num
        ? scoreValue.toDouble()
        : double.tryParse(scoreValue?.toString() ?? '') ?? 0;
    final condition = (analysis['soil_condition'] ??
            (numericScore >= 75
                ? 'Balanced'
                : numericScore >= 50
                    ? 'Fair'
                    : 'Needs Attention'))
        .toString();
    final score = '${numericScore.toStringAsFixed(1)}%';
    final crop = bestCrop.isEmpty
        ? 'No suitable crop yet'
        : (bestCrop['name'] ?? 'No suitable crop yet').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(.055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(.14),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryMetric(
                  icon: Icons.spa_outlined,
                  label: 'Soil condition',
                  value: condition,
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: Theme.of(context).colorScheme.primary.withOpacity(.14),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: _summaryMetric(
                    icon: Icons.speed_rounded,
                    label: 'Balance score',
                    value: score,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
              height: 1,
              color: Theme.of(context).colorScheme.primary.withOpacity(.14),
            ),
          ),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.eco_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CROP RECOMMENDATION',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: .7,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      crop,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: .55,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  bool _hasReportForReading(SoilData? reading) {
    if (reading == null) return false;
    final fingerprint = _readingFingerprint(reading);
    return _reports.any((report) {
      final sameReading =
          (report['sourceReadingId'] ?? '').toString() == reading.id;
      final savedFingerprint =
          (report['sourceReadingFingerprint'] ?? '').toString();
      return sameReading &&
          (savedFingerprint.isEmpty || savedFingerprint == fingerprint);
    });
  }

  Future<void> _handleGenerateReport() async {
    if (_isGeneratingReport) return;

    final reading = context.read<DeviceStatusService>().displayReading;
    if (reading == null) {
      _showSnackBar('Complete a soil scan before generating a report.', error: true);
      return;
    }

    final alreadySaved = _hasReportForReading(reading);
    final limitReached = _reports.length >= 8;
    if (alreadySaved || limitReached) {
      final confirmed = await _confirmGenerateAnother(
        alreadySaved: alreadySaved,
        limitReached: limitReached,
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isGeneratingReport = true);
    try {
      final soil = <String, dynamic>{
        'nitrogen': reading.nitrogen,
        'phosphorus': reading.phosphorus,
        'potassium': reading.potassium,
        'ph': reading.ph,
        'moisture': reading.moisture,
        if (reading.soilTemperature != null)
          'soilTemperature': reading.soilTemperature,
        if (reading.electricalConductivity != null)
          'electricalConductivity': reading.electricalConductivity,
      };
      final analysis = await DecisionSupportService.analyzeSoil(soil);
      final recommendations =
          await DecisionSupportService.getCropRecommendations(soil);
      final bestCrop = _asMap(recommendations['best_crop']);
      final cropName = (bestCrop['name'] ?? '').toString().trim();
      final plan = cropName.isEmpty
          ? <String, dynamic>{}
          : await DecisionSupportService.getSmartPlanning(
              soilData: soil,
              crop: cropName,
            );

      final report = <String, dynamic>{
        'title': alreadySaved
            ? 'SoilSense Soil Report (Regenerated)'
            : 'SoilSense Soil Report',
        'type': alreadySaved ? 'manual_regenerated' : 'manual_generated',
        'sourceReadingId': reading.id,
        'sourceReadingFingerprint': _readingFingerprint(reading),
        'generatedAt': DateTime.now(),
        'soil': <String, dynamic>{
          'nitrogen': reading.nitrogen,
          'phosphorus': reading.phosphorus,
          'potassium': reading.potassium,
          'ph': reading.ph,
          'moisture': reading.moisture,
          if (reading.soilTemperature != null)
            'soilTemperature': reading.soilTemperature,
          if (reading.electricalConductivity != null)
            'electricalConductivity': reading.electricalConductivity,
          'timestamp': reading.timestamp,
          'source': 'IoT sensor',
        },
        'analysis': analysis,
        'recommendations': recommendations,
        'plan': plan,
        'generationMode': 'deterministic',
        'automatic': false,
        'regenerated': alreadySaved,
      };

      await context.read<FirestoreService>().saveReport(report);

      String? downloadedPath;
      Object? downloadError;
      try {
        final bytes = await ReportService.buildPdf(report);
        downloadedPath = await FileDownloadService.savePdf(
          bytes: bytes,
          fileName: _newReportFileName(),
        );
      } catch (error) {
        downloadError = error;
        debugPrint('Automatic report download failed: $error');
      }

      if (!mounted) return;
      await _loadReports();
      if (!mounted) return;

      if (downloadedPath != null) {
        _showSnackBar(
          alreadySaved
              ? 'Report regenerated and downloaded to Downloads/SoilSense.'
              : 'Report generated and downloaded to Downloads/SoilSense.',
        );
      } else {
        _showSnackBar(
          'Report was saved in SoilSense, but the PDF could not be downloaded automatically${downloadError == null ? '.' : ': $downloadError'}',
          error: true,
        );
      }
    } catch (error) {
      _showSnackBar('Could not generate report: $error', error: true);
    } finally {
      if (mounted) setState(() => _isGeneratingReport = false);
    }
  }

  Future<bool?> _confirmGenerateAnother({
    required bool alreadySaved,
    required bool limitReached,
  }) {
    String content;
    if (alreadySaved && limitReached) {
      content =
          'A report for this soil reading already exists, and you already have 8 saved reports. Generate another copy anyway? The oldest saved report will be removed.';
    } else if (alreadySaved) {
      content =
          'A report for this soil reading already exists. Generate another saved copy using the same reading? SoilSense will reuse the same deterministic assessment and crop plan.';
    } else {
      content =
          'You already have 8 saved reports. Generating a new report will remove the oldest saved report. Continue?';
    }

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(alreadySaved ? 'Report already exists' : 'Saved report limit'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(alreadySaved ? 'Generate Again' : 'Continue'),
          ),
        ],
      ),
    );
  }

  String _readingFingerprint(SoilData reading) => <Object?>[
        reading.id,
        reading.timestamp.millisecondsSinceEpoch,
        reading.nitrogen,
        reading.phosphorus,
        reading.potassium,
        reading.ph,
        reading.moisture,
      ].join('|');


  Future<void> _confirmDeleteReport(Map<String, dynamic> report) async {
    final reportId = (report['id'] ?? '').toString();
    if (reportId.isEmpty) {
      _showSnackBar('This report cannot be deleted because its ID is missing.', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete report?'),
        content: Text(
          'This report will be permanently removed from your account. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingReportIds.add(reportId));
    try {
      await context.read<FirestoreService>().deleteReport(reportId);
      if (!mounted) return;
      setState(() => _reports.removeWhere(
            (item) => (item['id'] ?? '').toString() == reportId,
          ));
      _showSnackBar('Report deleted.');
    } catch (error) {
      _showSnackBar('Could not delete report: $error', error: true);
    } finally {
      if (mounted) setState(() => _deletingReportIds.remove(reportId));
    }
  }

  Future<void> _downloadReport(Map<String, dynamic> report) async {
    try {
      final bytes = await ReportService.buildPdf(report);
      await FileDownloadService.savePdf(
        bytes: bytes,
        fileName: _newReportFileName(),
      );
      _showSnackBar('PDF downloaded to Downloads/SoilSense.');
    } catch (e) {
      _showSnackBar('Could not download this report: $e', error: true);
    }
  }

  String _newReportFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'soilsense_report_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.pdf';
  }

  Future<void> _printReport(Map<String, dynamic> report) async {
    try {
      final bytes = await ReportService.buildPdf(report);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'SoilSense Report');
    } catch (e) {
      _showSnackBar('Could not print this report: $e', error: true);
    }
  }

  void _showSnackBar(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? AppTheme.warningRed : AppTheme.primaryGreen),
    );
  }

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map((item) => _asMap(item)).where((item) => item.isNotEmpty).toList();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
    return {};
  }

  static DateTime _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }
}
