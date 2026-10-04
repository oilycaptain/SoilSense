import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/soil_data.dart';
import '../services/app_settings_service.dart';
import '../services/decision_support_service.dart';
import '../services/device_status_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/data_refresh_info_button.dart';
import '../widgets/motion.dart';
import '../widgets/navigation_bar.dart';
import '../widgets/user_app_bar_actions.dart';

class SoilAnalysisScreen extends StatefulWidget {
  const SoilAnalysisScreen({super.key});

  @override
  State<SoilAnalysisScreen> createState() => _SoilAnalysisScreenState();
}

class _SoilAnalysisScreenState extends State<SoilAnalysisScreen> {
  List<SoilData> _readings = [];
  SoilData? _currentReading;
  Map<String, dynamic>? _analysis;
  bool _isLoading = true;
  String _chartMetric = 'Moisture';
  StreamSubscription<SoilData?>? _soilSubscription;

  @override
  void initState() {
    super.initState();
    _loadReadings();
    _soilSubscription = context
        .read<FirestoreService>()
        .watchLatestSoilReading()
        .listen((reading) {
      if (!mounted) return;
      if (reading == null) {
        // A Reset Current Reading hides the current/live value but intentionally
        // keeps saved history visible below.
        setState(() {
          _currentReading = null;
          _analysis = null;
          _isLoading = false;
        });
        return;
      }
      final currentId = _currentReading?.id;
      if (currentId != reading.id) unawaited(_loadReadings());
    });
  }

  @override
  void dispose() {
    _soilSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadReadings() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final firestore = context.read<FirestoreService>();
      // History/Trends respect the user's clear-history cutoff, while the
      // latest completed reading remains available as the current reading.
      final results = await Future.wait<List<SoilData>>([
        firestore.getSoilReadings(limit: 10),
        firestore.getSoilReadings(
          limit: 1,
          includeClearedHistory: true,
        ),
      ]);
      final readings = results[0];
      final currentReading = results[1].isEmpty ? null : results[1].first;
      Map<String, dynamic>? analysis;
      if (currentReading != null) {
        analysis = await DecisionSupportService.analyzeSoil({
          'nitrogen': currentReading.nitrogen,
          'phosphorus': currentReading.phosphorus,
          'potassium': currentReading.potassium,
          'ph': currentReading.ph,
          'moisture': currentReading.moisture,
        });
      }
      if (!mounted) return;
      setState(() {
        _readings = readings;
        _currentReading = currentReading;
        _analysis = analysis;
      });
    } catch (error) {
      debugPrint('Soil analysis refresh failed: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await context.read<DeviceStatusService>().refresh();
    if (!mounted) return;
    await _loadReadings();
  }


  @override
  Widget build(BuildContext context) {
    final deviceStatus = context.watch<DeviceStatusService>();
    final settings = context.watch<AppSettingsService>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: SoilSenseInfoButton(),
        title: Text(settings.text('Soil Analysis', 'Pagsusuri ng Lupa')),
        centerTitle: true,
        actions: soilSenseUserActions(context),
      ),
      body: _buildBody(deviceStatus),
      bottomNavigationBar: SoilSenseNavBar(currentIndex: 1),
    );
  }

  Widget _buildBody(DeviceStatusService deviceStatus) {
    if ((deviceStatus.isLoading || _isLoading) && _currentReading == null) {
      return Center(child: CircularProgressIndicator());
    }

    final isLive = deviceStatus.hasDisplayReading && _currentReading != null;
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SoilSenseReveal(
            child: _buildHealthSummary(isLive: isLive),
          ),
          SizedBox(height: 14),
          SoilSenseReveal(
            delay: Duration(milliseconds: 45),
            child: _buildLatestReading(
              isLive: isLive,
              isScanning: deviceStatus.isScanning,
            ),
          ),
          SizedBox(height: 14),
          SoilSenseReveal(
            delay: Duration(milliseconds: 90),
            child: _buildTrendChart(),
          ),
          SizedBox(height: 14),
          SoilSenseReveal(
            delay: Duration(milliseconds: 135),
            child: _buildHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthSummary({required bool isLive}) {
    final deficiencies = isLive
        ? ((_analysis?['deficiencies'] as List?) ?? const [])
        : const [];
    final imbalances = isLive
        ? ((_analysis?['imbalances'] as List?) ?? const [])
        : const [];
    final level = isLive
        ? (_analysis?['soil_condition'] ?? 'Unavailable').toString()
        : 'No reading yet';
    final score = isLive
        ? (((_analysis?['balance_score'] ?? _analysis?['fertility_score']) as num?)
                ?.toStringAsFixed(1) ??
            '0')
        : '--';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.read<AppSettingsService>().text(
                'Soil Condition Assessment',
                'Pagtatasa ng Kondisyon ng Lupa',
              ),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Condition: $level')),
                Chip(label: Text(isLive ? 'Balance: $score%' : 'Balance: --')),
              ],
            ),
            SizedBox(height: 6),
            Text(
              !isLive
                  ? 'Deficiencies and imbalances: None'
                  : deficiencies.isEmpty && imbalances.isEmpty
                      ? 'Readings are within the SoilSense reference bands.'
                      : 'Attention needed: ${[...deficiencies, ...imbalances].join(', ')}',
              style: TextStyle(
                color: !isLive ||
                        (deficiencies.isEmpty && imbalances.isEmpty)
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : AppTheme.warningRed,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestReading({
    required bool isLive,
    required bool isScanning,
  }) {
    final settings = context.read<AppSettingsService>();
    final data = isLive ? _currentReading : null;
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isLive
                        ? settings.text('Current Reading', 'Kasalukuyang Reading')
                        : settings.text(
                            'Current Reading Unavailable',
                            'Walang Kasalukuyang Reading',
                          ),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isLive && !isScanning)
                  IconButton(
                    tooltip: settings.text(
                      'Reset current reading',
                      'I-reset ang kasalukuyang reading',
                    ),
                    onPressed: _confirmResetCurrentReading,
                    icon: Icon(
                      Icons.restart_alt_rounded,
                      color: AppTheme.warningRed,
                    ),
                  ),
                if (isScanning) ...[
                  SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  SizedBox(width: 7),
                  Text(
                    settings.text('Scanning…', 'Nag-scan…'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            if (isScanning) ...[
              SizedBox(height: 10),
              LinearProgressIndicator(minHeight: 3),
              SizedBox(height: 7),
              Text(
                settings.text(
                  'Collecting a new soil sample. The values below remain the last completed reading until the scan finishes.',
                  'Kumukuha ng bagong soil sample. Ang values sa ibaba ay ang huling kumpletong reading hanggang matapos ang scan.',
                ),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            SizedBox(height: 12),
            _readingRow('Nitrogen', data?.nitrogen ?? 0, 'mg/kg', 40, 100,
                available: isLive),
            _readingRow(
                'Phosphorus', data?.phosphorus ?? 0, 'mg/kg', 50, 120,
                available: isLive),
            _readingRow('Potassium', data?.potassium ?? 0, 'mg/kg', 100, 300,
                available: isLive),
            _readingRow('pH Level', data?.ph ?? 0, '', 5.5, 7.5,
                available: isLive),
            _readingRow('Moisture', data?.moisture ?? 0, '%', 40, 90,
                available: isLive),
            SizedBox(height: 4),
            Text(
              settings.text(
                'SoilSense reference bands: N 40–100 mg/kg • P 50–120 mg/kg • K 100–300 mg/kg • pH 5.5–7.5 • Moisture 40–90%. High and Low values can both reduce the balance score.',
                'SoilSense reference bands: N 40–100 mg/kg • P 50–120 mg/kg • K 100–300 mg/kg • pH 5.5–7.5 • Moisture 40–90%. Ang sobrang taas o baba ay parehong maaaring magpababa ng balance score.',
              ),
              style: TextStyle(
                fontSize: 10.5,
                height: 1.35,
                color: colors.onSurfaceVariant,
              ),
            ),
            Divider(height: 22),
            _sensorOnlyRow(
              'Soil Temperature',
              data?.soilTemperature,
              '°C',
              available: isLive,
            ),
            _sensorOnlyRow(
              'Electrical Conductivity',
              data?.electricalConductivity?.toDouble(),
              'µS/cm',
              available: isLive,
              decimals: 0,
            ),
            SizedBox(height: 10),
            Text(
              isLive && data != null
                  ? settings.text(
                      'Updated after completed scan • ${_formatDate(data.timestamp)}',
                      'Na-update matapos ang kumpletong scan • ${_formatDate(data.timestamp)}',
                    )
                  : settings.text('Updated: None', 'Update: Wala'),
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readingRow(
    String label,
    double value,
    String unit,
    double min,
    double max, {
    required bool available,
  }) {
    final color = !available
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : value < min
            ? Colors.red
            : value > max
                ? Colors.orange
                : Theme.of(context).colorScheme.primary;
    final status = !available
        ? 'No data'
        : value < min
            ? 'Low'
            : value > max
                ? 'High'
                : 'Normal';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(
              available ? '${value.toStringAsFixed(1)} $unit' : '--',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sensorOnlyRow(
    String label,
    double? value,
    String unit, {
    required bool available,
    int decimals = 1,
  }) {
    final hasValue = available && value != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            'Supplemental',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(
              hasValue ? '${value.toStringAsFixed(decimals)} $unit' : '--',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: hasValue
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart() {
    final settings = context.read<AppSettingsService>();
    final colors = Theme.of(context).colorScheme;
    // Historical trends remain available even after Reset Current Reading,
    // because Reset hides only the current/live value and does not erase history.
    final chartReadings = _readings.take(10).toList().reversed.toList();

    if (chartReadings.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.text('Historical Trends', 'Historical Trends'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 18),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                    settings.text(
                      'Complete a scan to start building your trend chart.',
                      'Kumpletuhin ang scan para magsimulang gumawa ng trend chart.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final values = chartReadings.map(_metricValue).toList(growable: false);
    final spots = List.generate(
      chartReadings.length,
      (index) => FlSpot(index.toDouble(), values[index]),
    );
    final latest = values.last;
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final average = values.reduce((a, b) => a + b) / values.length;
    final maxY = _chartMaxY(maximum);
    final unit = _metricUnit(_chartMetric);
    final sameDay = chartReadings.every((reading) {
      final first = chartReadings.first.timestamp;
      final time = reading.timestamp;
      return time.year == first.year && time.month == first.month && time.day == first.day;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.text('Historical Trends', 'Historical Trends'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '${chartReadings.length} ${settings.text('recent readings', 'pinakabagong readings')} • ${settings.text('oldest to latest', 'luma hanggang bago')}',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                DropdownButton<String>(
                  value: _chartMetric,
                  underline: const SizedBox.shrink(),
                  items: const [
                    'Moisture',
                    'Nitrogen',
                    'Phosphorus',
                    'Potassium',
                    'pH',
                    'Temperature',
                    'EC'
                  ]
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(item),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _chartMetric = value);
                  },
                ),
              ],
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _trendStat('Latest', latest, unit),
                _trendStat('Average', average, unit),
                _trendStat('Min', minimum, unit),
                _trendStat('Max', maximum, unit),
              ],
            ),
            SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withOpacity(.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox(
                height: 230,
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: chartReadings.length <= 1
                        ? 1
                        : (chartReadings.length - 1).toDouble(),
                    minY: 0,
                    maxY: maxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY / 4,
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.round();
                            if (index < 0 || index >= chartReadings.length) {
                              return const SizedBox.shrink();
                            }
                            final last = chartReadings.length - 1;
                            final middle = last ~/ 2;
                            if (index != 0 && index != middle && index != last) {
                              return const SizedBox.shrink();
                            }
                            final date = chartReadings[index].timestamp;
                            final label = sameDay
                                ? DateFormat('HH:mm').format(date)
                                : DateFormat('d/M').format(date);
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Text(label, style: TextStyle(fontSize: 9)),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 46,
                          interval: maxY / 4,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              _axisValue(value),
                              style: TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      enabled: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((spot) {
                          final index = spot.x.round().clamp(0, chartReadings.length - 1).toInt();
                          final time = chartReadings[index].timestamp;
                          final value = _displayMetricValue(spot.y);
                          return LineTooltipItem(
                            '${DateFormat('d MMM, HH:mm').format(time)}\n$value${unit.isEmpty ? '' : ' $unit'}',
                            TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        // Straight segments avoid visually inventing negative
                        // values between non-negative sensor readings.
                        isCurved: false,
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 3,
                        dotData: FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Theme.of(context).colorScheme.primary.withOpacity(.08),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              settings.text(
                'Tap a point to see its exact date, time, and value.',
                'I-tap ang point para makita ang eksaktong petsa, oras, at value.',
              ),
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendStat(String label, double value, String unit) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withOpacity(.42),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: ${_displayMetricValue(value)}${unit.isEmpty ? '' : ' $unit'}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
    );
  }

  double _chartMaxY(double observedMaximum) {
    double floor;
    switch (_chartMetric) {
      case 'Moisture':
        floor = 20;
        break;
      case 'pH':
        floor = 14;
        break;
      case 'Temperature':
        floor = 40;
        break;
      case 'EC':
        floor = 20;
        break;
      default:
        floor = 20;
    }
    final padded = observedMaximum <= 0 ? floor : observedMaximum * 1.15;
    return padded > floor ? padded : floor;
  }

  String _metricUnit(String metric) {
    switch (metric) {
      case 'Moisture':
        return '%';
      case 'Nitrogen':
      case 'Phosphorus':
      case 'Potassium':
        return 'mg/kg';
      case 'Temperature':
        return '°C';
      case 'EC':
        return 'µS/cm';
      default:
        return '';
    }
  }

  String _displayMetricValue(double value) {
    if (_chartMetric == 'EC' || _chartMetric == 'Nitrogen' ||
        _chartMetric == 'Phosphorus' || _chartMetric == 'Potassium') {
      return value.toStringAsFixed(value.abs() >= 10 ? 0 : 1);
    }
    return value.toStringAsFixed(1);
  }

  String _axisValue(double value) {
    if (value.abs() >= 100) return value.toStringAsFixed(0);
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  double _metricValue(SoilData data) {
    switch (_chartMetric) {
      case 'Nitrogen':
        return data.nitrogen;
      case 'Phosphorus':
        return data.phosphorus;
      case 'Potassium':
        return data.potassium;
      case 'pH':
        return data.ph;
      case 'Temperature':
        return data.soilTemperature ?? 0;
      case 'EC':
        return data.electricalConductivity?.toDouble() ?? 0;
      default:
        return data.moisture;
    }
  }

  Widget _buildHistoryList() {
    final readings = _readings;
    final hasStoredReadings = _readings.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reading History (${readings.length}/10)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasStoredReadings) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 17, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      SizedBox(width: 5),
                      Text('Private', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Clear my reading history',
                    onPressed: _confirmClearHistory,
                    icon: Icon(Icons.delete_sweep_outlined, color: AppTheme.warningRed),
                  ),
                ],
              ],
            ),
            SizedBox(height: 6),
            if (readings.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No saved soil readings available',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ...readings.take(10).map(
                    (data) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        Icons.sensors,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        '${data.moisture.toStringAsFixed(1)}% moisture • saved soil reading',
                      ),
                      subtitle: Text(
                        'N ${data.nitrogen.toStringAsFixed(0)} | P ${data.phosphorus.toStringAsFixed(0)} | K ${data.potassium.toStringAsFixed(0)} | pH ${data.ph.toStringAsFixed(1)}'
                        '${data.soilTemperature == null ? '' : ' | ${data.soilTemperature!.toStringAsFixed(1)}°C'}'
                        '${data.electricalConductivity == null ? '' : ' | EC ${data.electricalConductivity}'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _shortDate(data.timestamp),
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 11),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Reading options',
                            onSelected: (value) {
                              if (value == 'delete') {
                                _confirmDeleteReading(data);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline, color: AppTheme.warningRed),
                                    SizedBox(width: 8),
                                    Text('Delete reading'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }


  Future<void> _confirmResetCurrentReading() async {
    final settings = context.read<AppSettingsService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(settings.text(
          'Reset current reading?',
          'I-reset ang kasalukuyang reading?',
        )),
        content: Text(settings.text(
          'This clears the values shown as the Current Reading and temporarily removes them from AI, crop guidance, and new reports. Your saved Reading History is kept. A new completed scan will automatically become the Current Reading.',
          'Aalisin nito ang values sa Kasalukuyang Reading at pansamantalang hindi gagamitin sa AI, crop guidance, at bagong reports. Mananatili ang naka-save na Reading History. Ang susunod na kumpletong scan ang awtomatikong magiging Kasalukuyang Reading.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(settings.text('Cancel', 'Kanselahin')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warningRed),
            icon: Icon(Icons.restart_alt_rounded),
            label: Text(settings.text('Reset', 'I-reset')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<FirestoreService>().resetCurrentReading();
      if (!mounted) return;
      setState(() {
        _currentReading = null;
        _analysis = null;
      });
      await context.read<DeviceStatusService>().refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(settings.text(
            'Current reading reset. Saved history was not deleted.',
            'Na-reset ang kasalukuyang reading. Hindi binura ang saved history.',
          )),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reset current reading: $error')),
      );
    }
  }

  Future<void> _confirmDeleteReading(SoilData reading) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete this reading?'),
        content: Text(
          'This permanently removes this soil reading from your private history. '
          'Historical trends and AI will then use your next newest saved reading.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warningRed),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<FirestoreService>().deleteSoilReading(reading.id);
      if (!mounted) return;
      await _loadReadings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Soil reading deleted.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete reading: $error')),
      );
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear reading history?'),
        content: Text(
          'This clears the Reading History and Historical Trends for this account. '
          'Your latest completed soil reading will stay available as the Current Reading '
          'for Soil Measurements, soil assessment, AI, crop guidance, and reports. '
          'New scans will start a fresh history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warningRed),
            child: Text('Clear History'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final deleted = await context.read<FirestoreService>().clearSoilReadingHistory();
      if (!mounted) return;
      await _loadReadings();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$deleted reading${deleted == 1 ? '' : 's'} cleared from history. '
            'Your latest completed reading is still available as Current Reading.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear history: $error')),
      );
    }
  }


  String _formatDate(DateTime time) =>
      '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';

  String _shortDate(DateTime time) =>
      '${time.day}/${time.month}\n${time.hour}:${time.minute.toString().padLeft(2, '0')}';
}
