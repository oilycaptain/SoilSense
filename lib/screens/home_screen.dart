import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/soil_data.dart';
import '../services/auth_service.dart';
import '../services/automatic_ai_service.dart';
import '../services/decision_support_service.dart';
import '../services/device_status_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_ai_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_skeleton_loader.dart';
import '../widgets/data_refresh_info_button.dart';
import '../widgets/motion.dart';
import '../widgets/navigation_bar.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/user_app_bar_actions.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SoilData? _latestSoilData;
  Map<String, dynamic>? _soilAnalysis;
  bool _isLoading = true;
  StreamSubscription<SoilData?>? _soilSubscription;
  StreamSubscription<bool>? _ownerSubscription;
  bool _hasOwnerAccess = false;
  bool _ownerAccessLoading = true;

  @override
  void initState() {
    super.initState();
    _subscribeToOwnerAccess();
    _loadData();
    _subscribeToRealtimeData();
  }

  @override
  void dispose() {
    _soilSubscription?.cancel();
    _ownerSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToOwnerAccess() {
    _ownerSubscription = context.read<FirestoreService>().watchOwnerAccess().listen(
      (hasAccess) {
        if (!mounted) return;
        final gainedAccess = !_hasOwnerAccess && hasAccess;
        setState(() {
          _hasOwnerAccess = hasAccess;
          _ownerAccessLoading = false;
        });
        if (gainedAccess) {
          _loadData();
          context.read<DeviceStatusService>().refresh();
        }
      },
      onError: (Object error) {
        debugPrint('Owner access stream error: $error');
        if (!mounted) return;
        setState(() {
          _hasOwnerAccess = false;
          _ownerAccessLoading = false;
        });
      },
    );
  }

  void _subscribeToRealtimeData() {
    final firestore = context.read<FirestoreService>();
    _soilSubscription = firestore.watchLatestSoilReading().listen(
      _handleRealtimeReading,
      onError: (Object error) =>
          debugPrint('Realtime soil stream error: $error'),
    );
  }

  Future<void> _handleRealtimeReading(SoilData? reading) async {
    if (reading == null) {
      if (mounted) {
        setState(() {
          _latestSoilData = null;
          _soilAnalysis = null;
          _isLoading = false;
        });
      }
      return;
    }
    if (_sameReading(_latestSoilData, reading)) return;
    final analysis = await DecisionSupportService.analyzeSoil({
      'nitrogen': reading.nitrogen,
      'phosphorus': reading.phosphorus,
      'potassium': reading.potassium,
      'ph': reading.ph,
      'moisture': reading.moisture,
    });
    if (!mounted) return;
    setState(() {
      _latestSoilData = reading;
      _soilAnalysis = analysis;
      _isLoading = false;
    });
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final firestore = context.read<FirestoreService>();
      final readings = await firestore.getSoilReadings(limit: 1, includeClearedHistory: true);
      final reading = readings.isEmpty ? null : readings.first;
      Map<String, dynamic>? analysis;
      if (reading != null) {
        analysis = await DecisionSupportService.analyzeSoil({
          'nitrogen': reading.nitrogen,
          'phosphorus': reading.phosphorus,
          'potassium': reading.potassium,
          'ph': reading.ph,
          'moisture': reading.moisture,
        });
      }
      if (!mounted) return;
      setState(() {
        _latestSoilData = reading;
        _soilAnalysis = analysis;
      });
    } catch (error) {
      debugPrint('Home data loading failed: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await context.read<DeviceStatusService>().refresh();
    if (!mounted) return;
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final deviceStatus = context.watch<DeviceStatusService>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: SoilSenseInfoButton(),
        title: Text('SoilSense'),
        actions: soilSenseUserActions(context),
      ),
      body: _buildBody(deviceStatus),
      bottomNavigationBar: SoilSenseNavBar(currentIndex: 0),
    );
  }

  Widget _buildBody(DeviceStatusService deviceStatus) {
    if (_ownerAccessLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if ((deviceStatus.isLoading || _isLoading) &&
        _latestSoilData == null &&
        deviceStatus.displayReading == null) {
      return Center(child: CircularProgressIndicator());
    }

    // DeviceStatusService is the shared source of truth. If the Home stream is
    // temporarily waiting on an index, use its latest live sensor reading.
    final sharedReading = deviceStatus.displayReading;
    if (sharedReading != null &&
        (_latestSoilData == null ||
            sharedReading.timestamp.isAfter(_latestSoilData!.timestamp))) {
      _latestSoilData = sharedReading;
    }

    final isLive = deviceStatus.isDeviceOnline;
    final hasData = _latestSoilData != null;

    if (!_hasOwnerAccess && !hasData) {
      return _buildNoOwnerAccess();
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: [
          SoilSenseReveal(
            child: _buildGreeting(isLive: isLive),
          ),
          if (!_hasOwnerAccess) ...[
            SizedBox(height: 12),
            _buildOwnershipNotice(),
          ] else if (!isLive && hasData) ...[
            SizedBox(height: 12),
            _buildSavedReadingNotice(),
          ],
          SizedBox(height: 18),
          SoilSenseReveal(
            delay: Duration(milliseconds: 40),
            child: _buildSoilHealthCard(isLive: hasData),
          ),
          SizedBox(height: 18),
          SoilSenseReveal(
            delay: Duration(milliseconds: 80),
            child: _buildNutrientChart(
              isLive: hasData,
              isScanning: deviceStatus.isScanning,
            ),
          ),
          SizedBox(height: 18),
          SoilSenseReveal(
            delay: Duration(milliseconds: 120),
            child: _buildRecommendations(isLive: hasData),
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNoOwnerAccess() {
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          SizedBox(height: 70),
          Icon(
            Icons.admin_panel_settings_outlined,
            size: 62,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(height: 18),
          Text(
            'SoilSense Device Not Assigned',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'This account is not the current SoilSense device owner and has no saved readings yet. Ask the administrator to assign the device when you need to take new scans.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45),
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/wifi-setup'),
            icon: Icon(Icons.wifi_tethering),
            label: Text('SoilSense Wi-Fi Setup'),
          ),
        ],
      ),
    );
  }


  Widget _buildOwnershipNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warningOrange.withOpacity(.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warningOrange.withOpacity(.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_outlined, color: AppTheme.warningOrange),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This account is not the current device owner. Your previous SoilSense readings remain private and visible here, but new scans will be saved only to the currently assigned owner.',
              style: TextStyle(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedReadingNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history_rounded, color: Theme.of(context).colorScheme.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'The IoT device is offline. SoilSense is showing your last saved reading so you can still review your soil data, analysis, and recommendations.',
              style: TextStyle(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting({required bool isLive}) {
    final user = context.read<AuthService>().currentUser;
    final readingLabel = _latestSoilData == null
        ? 'No soil reading yet'
        : isLive && _hasOwnerAccess
            ? 'Latest soil reading'
            : 'Last saved soil reading';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greetingForNow()}, ${user?.displayName ?? 'Farmer'} 🌱',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                readingLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SizedBox(width: 10),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (isLive ? AppTheme.primaryGreen : AppTheme.warningOrange)
                  .withOpacity(.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isLive
                        ? AppTheme.primaryGreen
                        : AppTheme.warningOrange,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 7),
                Text(
                  isLive ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: isLive
                        ? Theme.of(context).colorScheme.primary
                        : AppTheme.warningOrange,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSoilHealthCard({required bool isLive}) {
    final score = isLive
        ? ((_soilAnalysis?['balance_score'] as num?)?.toDouble() ??
            (_soilAnalysis?['fertility_score'] as num?)?.toDouble() ??
            0)
        : 0.0;
    final level = isLive
        ? (_soilAnalysis?['soil_condition'] ?? 'Unavailable').toString()
        : 'No reading yet';
    return Container(
      height: 182,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryGreen, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(.25),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Soil Balance Index',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  isLive ? '${score.round()}%' : '--',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  level,
                  style: TextStyle(
                    color: Colors.white.withOpacity(.92),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isLive && _latestSoilData != null
                        ? 'Last updated: ${_getTimeAgo(_latestSoilData!.timestamp)}'
                        : 'Waiting for a new device scan',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.agriculture, size: 50, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildNutrientChart({
    required bool isLive,
    required bool isScanning,
  }) {
    final data = isLive ? _latestSoilData : null;
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
                    'Soil Measurements',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isScanning)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Scanning...',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/soil-analysis'),
                    child: Text('View All'),
                  ),
              ],
            ),
            if (isScanning) ...[
              SizedBox(height: 8),
              LinearProgressIndicator(),
              SizedBox(height: 8),
              Text(
                'Collecting and averaging sensor samples. The values below remain the last saved reading until the scan finishes.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
            SizedBox(height: 10),
            _nutrientRow('Nitrogen', data?.nitrogen ?? 0, 40, 100, 150,
                unit: 'mg/kg', available: isLive),
            _nutrientRow('Phosphorus', data?.phosphorus ?? 0, 50, 120, 150,
                unit: 'mg/kg', available: isLive),
            _nutrientRow('Potassium', data?.potassium ?? 0, 100, 300, 300,
                unit: 'mg/kg', available: isLive),
            _nutrientRow('pH', data?.ph ?? 0, 5.5, 7.5, 14,
                unit: '', available: isLive),
            _nutrientRow('Moisture', data?.moisture ?? 0, 40, 90, 100,
                unit: '%', available: isLive),
            Divider(height: 24),
            Text(
              'Additional Sensor Data',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _supplementalSensorTile(
                    'Temperature',
                    data?.soilTemperature == null
                        ? '--'
                        : '${data!.soilTemperature!.toStringAsFixed(1)} °C',
                    Icons.thermostat_outlined,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _supplementalSensorTile(
                    'EC',
                    data?.electricalConductivity == null
                        ? '--'
                        : '${data!.electricalConductivity} µS/cm',
                    Icons.electric_bolt_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nutrientRow(
    String label,
    double value,
    double min,
    double max,
    double visualMax, {
    required String unit,
    required bool available,
  }) {
    final color = !available
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : value < min
            ? Colors.red
            : value > max
                ? Colors.orange
                : Theme.of(context).colorScheme.primary;
    final percentage = !available || visualMax <= 0
        ? 0.0
        : (value / visualMax).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  available ? value.toStringAsFixed(1) : '--',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
                if (available && unit.isNotEmpty)
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.0,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _supplementalSensorTile(
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(.12)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendations({required bool isLive}) {
    final aiService = context.watch<AutomaticAiService>();
    final aiResult = isLive ? aiService.result : null;
    final aiEligible = isLive && aiService.canRunAi;
    final aiLoading =
        aiEligible && aiResult?.status == GeminiAiStatus.loading;
    final currentAiAdvice =
        aiResult?.isSuccess == true ? aiResult!.advice : null;
    final previousAiAdvice = aiService.lastReadyAdvice;
    final isFirstAiLoad =
        aiLoading && currentAiAdvice == null && previousAiAdvice == null;
    final isAiUpdating =
        aiLoading && currentAiAdvice == null && previousAiAdvice != null;
    final aiAdvice = currentAiAdvice ?? (isAiUpdating ? previousAiAdvice : null);

    final crops = isLive
        ? ((_soilAnalysis?['recommended_crops'] as List?) ?? const [])
        : const [];
    final cropNames = crops
        .map((item) => item is Map
            ? (item['name'] ?? '').toString()
            : item.toString())
        .where((name) => name.trim().isNotEmpty)
        .take(5)
        .toList();

    final builtInCrop = cropNames.isEmpty
        ? 'No suitable crop for the current reading'
        : cropNames.join(', ');
    final builtInFertilizer = _fertilizerAdvice(isLive: isLive);
    final builtInSoil = _soilManagementAdvice(isLive: isLive);

    final cropNamesValue = cropNames.isEmpty
        ? builtInCrop
        : _aiText(aiAdvice, 'cropSuggestion', builtInCrop);
    final cropReasoning = _aiText(aiAdvice, 'cropReasoning', '');
    final cropValue = cropReasoning.isEmpty
        ? cropNamesValue
        : '$cropNamesValue\n$cropReasoning';
    final fertilizerValue =
        _aiText(aiAdvice, 'fertilizerAdvice', builtInFertilizer);
    final soilValue = _aiText(aiAdvice, 'soilManagement', builtInSoil);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Smart Recommendations',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            if (isLive) _buildAutomaticAiStatus(aiService),
          ],
        ),
        SizedBox(height: 4),
        Text(
          !isLive
              ? 'Waiting for a completed soil reading.'
              : aiEligible
                  ? (isFirstAiLoad
                      ? 'AI is analyzing this soil reading for the first time.'
                      : isAiUpdating
                          ? 'Updating AI recommendations from the latest completed soil reading. Previous AI guidance stays visible until the update finishes.'
                          : aiService.isUsingSavedReading
                              ? 'AI can analyze your latest saved private reading even while the device is offline or this account is Not Owner.'
                              : 'AI runs automatically after a new completed scan.')
                  : 'Complete a soil scan first so AI has soil data to analyze.',
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 10),
        if (isFirstAiLoad)
          const AiSkeletonLoader(cards: 3)
        else ...[
          if (isAiUpdating) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
            SizedBox(height: 10),
          ],
          RecommendationCard(
            title: 'Crop Suggestion',
            subtitle: '',
            value: cropValue,
            icon: Icons.agriculture,
            color: Theme.of(context).colorScheme.primary,
          ),
          SizedBox(height: 10),
          RecommendationCard(
            title: 'Fertilizer Advice',
            subtitle: '',
            value: fertilizerValue,
            icon: Icons.science,
            color: AppTheme.warningOrange,
          ),
          SizedBox(height: 10),
          RecommendationCard(
            title: 'Soil Management',
            subtitle: '',
            value: soilValue,
            icon: Icons.eco_outlined,
            color: AppTheme.primaryDark,
          ),
        ],
      ],
    );
  }

  Widget _buildAutomaticAiStatus(AutomaticAiService service) {
    final result = service.result;
    String label;
    Color color;
    IconData icon;

    if (result?.status == GeminiAiStatus.ready && result?.isSuccess == true) {
      label = service.isUsingSavedReading ? 'AI READY • SAVED DATA' : 'AI READY';
      color = Theme.of(context).colorScheme.primary;
      icon = Icons.auto_awesome;
    } else if (service.canRunAi &&
        result?.status == GeminiAiStatus.loading) {
      label = service.isUsingSavedReading
          ? 'AI ANALYZING SAVED'
          : 'AI ANALYZING';
      color = AppTheme.warningOrange;
      icon = Icons.auto_awesome;
    } else if (!service.canRunAi) {
      label = 'AI AFTER SCAN';
      color = Theme.of(context).colorScheme.onSurfaceVariant;
      icon = Icons.pause_circle_outline_rounded;
    } else {
      switch (result?.status) {
        case GeminiAiStatus.quotaLimited:
          label = 'AI LIMIT REACHED';
          color = AppTheme.warningRed;
          icon = Icons.hourglass_bottom_rounded;
          break;
        case GeminiAiStatus.notConfigured:
          label = 'AI KEY ERROR';
          color = AppTheme.warningRed;
          icon = Icons.key_off_outlined;
          break;
        case GeminiAiStatus.unavailable:
          label = 'AI UNAVAILABLE';
          color = AppTheme.warningOrange;
          icon = Icons.cloud_off_outlined;
          break;
        case GeminiAiStatus.authenticationRequired:
          label = 'SIGN IN AGAIN';
          color = AppTheme.warningRed;
          icon = Icons.lock_outline;
          break;
        case GeminiAiStatus.ready:
        case GeminiAiStatus.idle:
        case GeminiAiStatus.loading:
        case null:
          label = 'AI READY AFTER SCAN';
          color = Theme.of(context).colorScheme.onSurfaceVariant;
          icon = Icons.auto_awesome_outlined;
          break;
      }
    }

    final message = result?.message.isNotEmpty == true
        ? result!.message
        : (service.canRunAi
            ? service.aiReadingContext
            : service.pausedReason);
    return Tooltip(
      message: message,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(.09),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _aiText(
    Map<String, dynamic>? advice,
    String key,
    String fallback,
  ) {
    final value = advice?[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  String _fertilizerAdvice({required bool isLive}) {
    final data = _latestSoilData;
    if (!isLive || data == null) return 'None';

    final actions = <String>[];
    if (data.nitrogen < 40) {
      actions.add('Nitrogen is low at ${data.nitrogen.toStringAsFixed(1)} mg/kg; use a locally appropriate nitrogen source and recheck before adding more.');
    } else if (data.nitrogen > 100) {
      actions.add('Nitrogen is high at ${data.nitrogen.toStringAsFixed(1)} mg/kg; avoid additional nitrogen until the reading is confirmed.');
    }
    if (data.phosphorus < 50) {
      actions.add('Phosphorus is low at ${data.phosphorus.toStringAsFixed(1)} mg/kg; consider a locally verified phosphorus source before planting.');
    } else if (data.phosphorus > 120) {
      actions.add('Phosphorus is high at ${data.phosphorus.toStringAsFixed(1)} mg/kg; avoid phosphorus fertilizer until the high level is confirmed locally.');
    }
    if (data.potassium < 100) {
      actions.add('Potassium is low at ${data.potassium.toStringAsFixed(1)} mg/kg; use a locally appropriate potassium source and avoid over-application.');
    } else if (data.potassium > 300) {
      actions.add('Potassium is high at ${data.potassium.toStringAsFixed(1)} mg/kg; avoid additional potassium until the reading is confirmed.');
    }

    if (actions.isEmpty) {
      return 'Nitrogen, phosphorus, and potassium are within the SoilSense reference bands. Avoid unnecessary fertilizer and match any future application to the selected crop and a locally verified recommendation.';
    }
    return actions.take(2).join(' ');
  }

  String _soilManagementAdvice({required bool isLive}) {
    final data = _latestSoilData;
    if (!isLive || data == null) return 'None';

    final parts = <String>[];
    if (data.ph > 7.5) {
      parts.add(
        'The soil is alkaline at pH ${data.ph.toStringAsFixed(1)}. Add well-decomposed organic matter and avoid unverified acidifying amendments until local guidance confirms what is appropriate.',
      );
    } else if (data.ph < 5.5) {
      parts.add(
        'The soil is acidic at pH ${data.ph.toStringAsFixed(1)}. Confirm lime requirement locally before applying lime, because the correct amount depends on soil buffering and crop needs.',
      );
    } else {
      parts.add(
        'Soil pH ${data.ph.toStringAsFixed(1)} is within the SoilSense reference band, so maintain the current pH management.',
      );
    }

    if (data.moisture < 40) {
      parts.add('Moisture is low at ${data.moisture.toStringAsFixed(1)}%; irrigate and recheck after water has infiltrated.');
    } else if (data.moisture > 90) {
      parts.add('Moisture is high at ${data.moisture.toStringAsFixed(1)}%; pause irrigation and inspect drainage before planting.');
    } else {
      parts.add('Moisture ${data.moisture.toStringAsFixed(1)}% is within the current reference band; keep monitoring rather than changing irrigation unnecessarily.');
    }

    return parts.join(' ');
  }

  bool _sameReading(SoilData? a, SoilData b) {
    if (a == null) return false;
    return a.id == b.id &&
        a.timestamp == b.timestamp &&
        a.nitrogen == b.nitrogen &&
        a.phosphorus == b.phosphorus &&
        a.potassium == b.potassium &&
        a.ph == b.ph &&
        a.moisture == b.moisture;
  }

  String _greetingForNow() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getTimeAgo(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}
