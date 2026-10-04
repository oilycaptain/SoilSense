import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/soil_data.dart';
import '../services/app_settings_service.dart';
import '../services/automatic_ai_service.dart';
import '../services/decision_support_service.dart';
import '../services/device_status_service.dart';
import '../services/firestore_service.dart';
import '../services/gemini_ai_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_skeleton_loader.dart';
import '../widgets/data_refresh_info_button.dart';
import '../widgets/motion.dart';

class SmartCropPlanningScreen extends StatefulWidget {
  const SmartCropPlanningScreen({super.key});

  @override
  State<SmartCropPlanningScreen> createState() =>
      _SmartCropPlanningScreenState();
}

class _SmartCropPlanningScreenState extends State<SmartCropPlanningScreen> {
  SoilData? _reading;
  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _recommendations;
  String _selectedCrop = '';
  bool _loading = true;
  bool _isAiLoading = false;
  GeminiAiResult? _geminiResult;
  AutomaticAiService? _automaticAiService;
  String? _lastAutomaticReadingSignature;
  bool _automaticSyncInProgress = false;

  Map<String, dynamic> get _soil => {
        'nitrogen': _reading?.nitrogen ?? 0,
        'phosphorus': _reading?.phosphorus ?? 0,
        'potassium': _reading?.potassium ?? 0,
        'ph': _reading?.ph ?? 0,
        'moisture': _reading?.moisture ?? 0,
        'timestamp': _reading?.timestamp,
        'source': 'IoT sensor',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<AutomaticAiService>();
    if (!identical(_automaticAiService, service)) {
      _automaticAiService?.removeListener(_handleAutomaticAiChange);
      _automaticAiService = service;
      service.addListener(_handleAutomaticAiChange);
      _handleAutomaticAiChange();
    }
  }

  void _handleAutomaticAiChange() {
    final reading = _automaticAiService?.reading;
    if (!mounted) return;
    if (reading == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _reading = null;
          _plan = null;
          _recommendations = null;
          _geminiResult = null;
          _isAiLoading = false;
          _lastAutomaticReadingSignature = null;
          _loading = false;
        });
      });
      return;
    }
    final signature = _readingSignature(reading);

    // A new completed reading refreshes the plan. Crop-planning AI is a
    // separate focused request, so the general Smart Recommendations response
    // is never reused as if it were a crop plan.
    if (_lastAutomaticReadingSignature != signature &&
        !_automaticSyncInProgress) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncAutomaticReading(reading);
      });
    }
  }

  Future<void> _syncAutomaticReading(SoilData reading) async {
    final signature = _readingSignature(reading);
    if (_lastAutomaticReadingSignature == signature ||
        _automaticSyncInProgress) {
      return;
    }
    _automaticSyncInProgress = true;
    try {
      final soil = <String, dynamic>{
        'nitrogen': reading.nitrogen,
        'phosphorus': reading.phosphorus,
        'potassium': reading.potassium,
        'ph': reading.ph,
        'moisture': reading.moisture,
        'timestamp': reading.timestamp,
        'source': 'IoT sensor',
      };
      final recommendations =
          await DecisionSupportService.getCropRecommendations(soil);
      final best = _map(recommendations['best_crop']);
      final crop = best.isNotEmpty ? (best['name'] ?? '').toString() : '';
      final plan = crop.isEmpty ? null : await _buildInitialPlan(soil, crop);
      if (!mounted) return;
      setState(() {
        _reading = reading;
        _recommendations = recommendations;
        _selectedCrop = crop;
        _plan = plan;
        _lastAutomaticReadingSignature = signature;
        _loading = false;
      });
      if (crop.isNotEmpty && context.read<AutomaticAiService>().canRunAi) {
        await _generateAiPlan();
      }
    } catch (error) {
      debugPrint('Automatic smart-plan refresh failed: $error');
    } finally {
      _automaticSyncInProgress = false;
    }
  }

  String _readingSignature(SoilData reading) => <Object?>[
        reading.id,
        reading.timestamp.millisecondsSinceEpoch,
        reading.nitrogen,
        reading.phosphorus,
        reading.potassium,
        reading.ph,
        reading.moisture,
      ].join('|');

  @override
  void dispose() {
    _automaticAiService?.removeListener(_handleAutomaticAiChange);
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final readings =
          await context.read<FirestoreService>().getSoilReadings(limit: 1, includeClearedHistory: true);
      _reading = readings.isEmpty ? null : readings.first;
      if (_reading != null) {
        _recommendations =
            await DecisionSupportService.getCropRecommendations(_soil);
        final best = _map(_recommendations?['best_crop']);
        _selectedCrop = best.isNotEmpty ? (best['name'] ?? '').toString() : '';
        _plan = _selectedCrop.isEmpty
            ? null
            : await _buildInitialPlan(_soil, _selectedCrop);
        _lastAutomaticReadingSignature = _readingSignature(_reading!);
        if (_selectedCrop.isNotEmpty &&
            context.read<AutomaticAiService>().canRunAi) {
          _generateAiPlan();
        }
      } else {
        _recommendations = null;
        _plan = null;
        _geminiResult = null;
      }
    } catch (error) {
      debugPrint('Smart crop planning refresh failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate(String crop) async {
    if (!context.read<DeviceStatusService>().hasDisplayReading) return;
    final cleanCrop = crop.trim();
    if (cleanCrop.length < 2) return;

    final automaticAi = context.read<AutomaticAiService>();
    setState(() {
      _selectedCrop = cleanCrop;
      _loading = true;
      _geminiResult = automaticAi.canRunAi
          ? GeminiAiResult(
              status: GeminiAiStatus.loading,
              message: 'AI is preparing the crop plan automatically.',
            )
          : GeminiAiResult(
              status: GeminiAiStatus.idle,
              message: automaticAi.pausedReason,
            );
    });

    try {
      final plan = await _buildInitialPlan(_soil, cleanCrop);
      if (mounted) setState(() => _plan = plan);
      if (automaticAi.canRunAi) {
        await _generateAiPlan();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>> _buildInitialPlan(
    Map<String, dynamic> soil,
    String crop,
  ) async {
    final canonical = _supportedCropName(crop);
    if (canonical != null) {
      return DecisionSupportService.getSmartPlanning(
        soilData: soil,
        crop: canonical,
      );
    }

    // Do not silently substitute Corn for crops that are outside the curated
    // Philippines-supported expert-system crop library. Gemini fills this plan after the user
    // finishes typing the crop name.
    final analysis = await DecisionSupportService.analyzeSoilWithoutCropRecursion(
      soil,
    );
    final apply = analysis['what_to_apply'];
    final firstAction = apply is List && apply.isNotEmpty
        ? apply.first.toString()
        : 'Review the current soil reading before planting.';
    return <String, dynamic>{
      'crop': crop,
      'planting_schedule': <String, dynamic>{
        'start_date': 'AI is preparing',
        'end_date': 'AI is preparing',
        'days_to_mature': 'AI is preparing',
        'season': 'AI is preparing',
      },
      'harvest_timeline': <String, dynamic>{
        'expected_date': 'AI is preparing',
        'note': 'Crop-specific guidance will appear automatically.',
      },
      'rotation_plan': <Map<String, dynamic>>[],
      'action_schedule': <Map<String, dynamic>>[
        <String, dynamic>{
          'timing': 'Before planting',
          'action': firstAction,
        },
      ],
      'water_requirements': <String, dynamic>{
        'guidance': 'AI is preparing crop-specific water guidance.',
        'current_moisture': soil['moisture'] ?? 0,
        'action': 'Reviewing the current moisture for $crop.',
      },
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String? _supportedCropName(String crop) {
    final lower = crop.trim().toLowerCase();
    for (final supported in DecisionSupportService.supportedCrops) {
      if (supported.toLowerCase() == lower) return supported;
    }
    return null;
  }

  Future<void> _refreshAll() async {
    await context.read<DeviceStatusService>().refresh();
    if (!mounted) return;
    await _load();
  }

  Future<void> _generateAiPlan() async {
    final reading = _reading;
    if (reading == null || _isAiLoading) return;

    final crop = _selectedCrop.trim();
    if (crop.isEmpty) return;
    final automaticAi = context.read<AutomaticAiService>();
    if (!automaticAi.canRunAi) {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _geminiResult = GeminiAiResult(
            status: GeminiAiStatus.idle,
            message: automaticAi.pausedReason,
          );
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isAiLoading = true;
        _geminiResult = GeminiAiResult(
          status: GeminiAiStatus.loading,
          message: 'AI is preparing the crop plan automatically.',
        );
      });
    }

    final result = await automaticAi.generateForCrop(crop);

    if (!mounted) return;
    final currentCrop = _selectedCrop;
    setState(() {
      if (currentCrop == crop) {
        _geminiResult = result;
        if (result.isSuccess) {
          _plan = _planFromAi(result.advice!, crop);
        }
      }
      _isAiLoading = false;
    });

    // A rapid crop change should never leave advice from the previous crop on
    // screen. Immediately process the latest selection after this call ends.
    if (currentCrop != crop) {
      await _generateAiPlan();
    }
  }

  Map<String, dynamic> _planFromAi(
    Map<String, dynamic> advice,
    String crop,
  ) {
    String text(String key, [String fallback = 'Not available']) {
      final value = advice[key]?.toString().trim() ?? '';
      return value.isEmpty || value.toLowerCase() == 'not selected'
          ? fallback
          : value;
    }

    return <String, dynamic>{
      'crop': crop,
      'planting_schedule': <String, dynamic>{
        'start_date': text('planningWindow'),
        'end_date': '',
        'days_to_mature': text('planningMaturity'),
        'season': text('planningSeason'),
      },
      'harvest_timeline': <String, dynamic>{
        'expected_date': text('planningHarvest'),
        'note': text('planningHarvestNote'),
      },
      'rotation_plan': <Map<String, dynamic>>[
        <String, dynamic>{
          'season': 'Cycle 1',
          'crop': crop,
          'reason': 'Selected crop for the current soil reading.',
        },
        <String, dynamic>{
          'season': 'Cycle 2',
          'crop': text('rotationCrop1', 'Locally suitable rotation crop'),
          'reason': text('rotationReason1', 'Rotate nutrient demand and support soil condition.'),
        },
        <String, dynamic>{
          'season': 'Cycle 3',
          'crop': text('rotationCrop2', 'Alternative rotation crop'),
          'reason': text('rotationReason2', 'Avoid continuously planting the same crop family.'),
        },
        <String, dynamic>{
          'season': 'Cycle 4',
          'crop': text('rotationCrop3', 'Cover crop'),
          'reason': text('rotationReason3', 'Protect the soil and add organic matter.'),
        },
      ],
      'action_schedule': <Map<String, dynamic>>[
        <String, dynamic>{
          'timing': 'Before planting',
          'action': text('planningBeforePlanting'),
        },
        <String, dynamic>{
          'timing': 'At planting',
          'action': text('planningAtPlanting'),
        },
        <String, dynamic>{
          'timing': 'During growth',
          'action': text('planningMonitoring'),
        },
        <String, dynamic>{
          'timing': 'Before harvest',
          'action': text('planningBeforeHarvest'),
        },
      ],
      'water_requirements': <String, dynamic>{
        'guidance': text('planningWaterGuidance'),
        'current_moisture': _reading?.moisture ?? 0,
        'action': text('planningWaterAction'),
      },
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final deviceStatus = context.watch<DeviceStatusService>();
    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 96 : 56,
        leading: SoilSenseAppBarLeading(showBackButton: canPop),
        title: Text(context.watch<AppSettingsService>().text('Smart Crop Planning', 'Smart Crop Planning')),
        centerTitle: true,
      ),
      body: _buildBody(deviceStatus),
    );
  }

  Widget _buildBody(DeviceStatusService deviceStatus) {
    if ((deviceStatus.isLoading || _loading) && _reading == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: const [
          AiSkeletonLoader(cards: 4),
        ],
      );
    }

    final isLive = deviceStatus.hasDisplayReading;
    final aiPlanLoading = isLive &&
        (_isAiLoading || _geminiResult?.status == GeminiAiStatus.loading);
    final hasSuitableCrop = isLive && _planningCropChoices().isNotEmpty;
    if (isLive && !hasSuitableCrop && !_loading) {
      return RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.block_rounded,
                            color: AppTheme.warningOrange),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.watch<AppSettingsService>().text(
                              'No suitable crop plan yet',
                              'Wala pang angkop na crop plan',
                            ),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text(
                      context.watch<AppSettingsService>().text(
                        'All evaluated crops are currently below the 50% recommendation threshold, so SoilSense will not generate a crop plan. Improve the soil condition and complete a new scan.',
                        'Lahat ng sinuring pananim ay kasalukuyang mas mababa sa 50% recommendation threshold, kaya hindi muna gagawa ang SoilSense ng crop plan. Ayusin ang kondisyon ng lupa at mag-scan muli.',
                      ),
                      style: TextStyle(
                        height: 1.45,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    // The crop selector remains usable/visible, while the plan content uses
    // a skeleton for exactly as long as the focused Gemini request is running.
    // As soon as AI succeeds or fails, the skeleton is replaced by the final
    // AI plan or the built-in fallback plan.
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SoilSenseReveal(child: _selector(isLive: isLive)),
          const SizedBox(height: 14),
          if (aiPlanLoading)
            const AiSkeletonLoader(cards: 4)
          else ...[
            SoilSenseReveal(
              delay: const Duration(milliseconds: 45),
              child: _overview(isLive: isLive),
            ),
            const SizedBox(height: 14),
            SoilSenseReveal(
              delay: const Duration(milliseconds: 90),
              child: _timeline(isLive: isLive),
            ),
            const SizedBox(height: 14),
            SoilSenseReveal(
              delay: const Duration(milliseconds: 135),
              child: _rotation(isLive: isLive),
            ),
            const SizedBox(height: 14),
            SoilSenseReveal(
              delay: const Duration(milliseconds: 180),
              child: _water(isLive: isLive),
            ),
          ],
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _selector({required bool isLive}) {
    final choices = _planningCropChoices();
    final selected = choices.any((crop) => crop['name'] == _selectedCrop)
        ? _selectedCrop
        : (choices.isNotEmpty ? choices.first['name'].toString() : null);

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
                    context.watch<AppSettingsService>().text(
                      'Plan a Recommended Crop',
                      'Planuhin ang Inirerekomendang Pananim',
                    ),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                if (isLive) _aiStatusBadge(),
              ],
            ),
            SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: isLive ? selected : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: isLive
                    ? 'Crop from suitability ranking'
                    : 'Crop plan unavailable',
                prefixIcon: Icon(Icons.agriculture),
              ),
              items: choices
                  .map(
                    (crop) => DropdownMenuItem<String>(
                      value: crop['name'].toString(),
                      child: Text(_cropChoiceLabel(crop)),
                    ),
                  )
                  .toList(),
              onChanged: isLive && choices.isNotEmpty && !_loading
                  ? (crop) {
                      if (crop != null && crop != _selectedCrop) {
                        _generate(crop);
                      }
                    }
                  : null,
            ),
            SizedBox(height: 8),
            Text(
              isLive
                  ? 'Choices come from the latest soil-based crop suitability ranking and update after a new scan.'
                  : 'Complete a soil scan to see suitable crop choices.',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _planningCropChoices() {
    final high = _list(_recommendations?['highly_suitable']);
    final medium = _list(_recommendations?['moderately_suitable']);
    final recommended = <Map<String, dynamic>>[...high, ...medium];
    if (recommended.isNotEmpty) return recommended;

    final best = _map(_recommendations?['best_crop']);
    return best.isEmpty ? <Map<String, dynamic>>[] : <Map<String, dynamic>>[best];
  }

  String _cropChoiceLabel(Map<String, dynamic> crop) {
    final name = (crop['name'] ?? 'Crop').toString();
    final score = (crop['score'] as num?)?.round();
    final high = _list(_recommendations?['highly_suitable'])
        .any((item) => item['name'] == crop['name']);
    final medium = _list(_recommendations?['moderately_suitable'])
        .any((item) => item['name'] == crop['name']);
    final rank = high
        ? 'Highly suitable'
        : medium
            ? 'Moderately suitable'
            : 'Highest ranked';
    return score == null ? '$name • $rank' : '$name • $rank • $score%';
  }



  Widget _overview({required bool isLive}) {
    final Map<String, dynamic> schedule = isLive
        ? _map(_plan?['planting_schedule'])
        : <String, dynamic>{};
    final Map<String, dynamic> harvest = isLive
        ? _map(_plan?['harvest_timeline'])
        : <String, dynamic>{};
    final advice = isLive && _geminiResult?.isSuccess == true
        ? _geminiResult!.advice
        : null;
    final aiPlanningGuidance = _aiText(advice, 'planningGuidance');
    final planningGuidance = aiPlanningGuidance.isNotEmpty
        ? aiPlanningGuidance
        : _localPlanGuidance(_plan);
    final whenToAct = _aiText(advice, 'whenToAct');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    isLive ? _selectedCrop : 'No Active Crop Plan',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isLive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            _row(
              'Planting window',
              isLive
                  ? _plantingWindowText(schedule)
                  : 'None',
            ),
            _row(
              'Preferred season',
              isLive ? '${schedule['season'] ?? 'None'}' : 'None',
            ),
            _row(
              'Maturity',
              isLive ? '${schedule['days_to_mature'] ?? 'None'}' : 'None',
            ),
            _row(
              'Expected harvest',
              isLive ? '${harvest['expected_date'] ?? 'None'}' : 'None',
            ),
            _row(
              'Harvest note',
              isLive ? '${harvest['note'] ?? 'None'}' : 'None',
            ),
            if (planningGuidance.isNotEmpty) ...[
              Divider(height: 22),
              Text(
                'Plan guidance',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                planningGuidance,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            if (whenToAct.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                'Priority: $whenToAct',
                style: TextStyle(
                  fontSize: 12,
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

  Widget _aiStatusBadge() {
    final aiService = context.read<AutomaticAiService>();
    final status = _geminiResult?.status;
    final loading = aiService.canRunAi &&
        (_isAiLoading || status == GeminiAiStatus.loading);
    final ready = status == GeminiAiStatus.ready;

    final label = ready
        ? 'AI ready'
        : loading
            ? (aiService.isUsingSavedReading ? 'Analyzing saved data' : 'Enhancing')
            : !aiService.canRunAi
                ? 'AI after scan'
                : 'Plan ready';
    final color = loading
        ? AppTheme.warningOrange
        : ready
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant;

    return Tooltip(
      message: !aiService.canRunAi && !ready
          ? aiService.pausedReason
          : (_geminiResult?.message ?? aiService.aiReadingContext),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }


  String _aiText(Map<String, dynamic>? advice, String key) {
    return advice?[key]?.toString().trim() ?? '';
  }

  String _localPlanGuidance(Map<String, dynamic>? plan) {
    if (plan == null) return '';
    final schedule = _map(plan['planting_schedule']);
    final water = _map(plan['water_requirements']);
    final harvest = _map(plan['harvest_timeline']);
    final start = (schedule['start_date'] ?? '').toString().trim();
    final end = (schedule['end_date'] ?? '').toString().trim();
    final season = (schedule['season'] ?? '').toString().trim();
    final waterAction = (water['action'] ?? '').toString().trim();
    final harvestDate = (harvest['expected_date'] ?? '').toString().trim();
    final window = start.isEmpty
        ? 'the recommended planting period'
        : (end.isEmpty ? start : '$start – $end');
    final parts = <String>[
      'Plant $_selectedCrop during $window${season.isEmpty ? '' : ' ($season)'}.',
      if (waterAction.isNotEmpty) waterAction,
      if (harvestDate.isNotEmpty) 'Expected harvest is around $harvestDate.',
      'Continue checking the soil reading and follow the action timeline as field conditions change.',
    ];
    return parts.join(' ');
  }

  Widget _timeline({required bool isLive}) {
    final actions = isLive ? _list(_plan?['action_schedule']) : const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Action Timeline',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (actions.isEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.schedule, color: Theme.of(context).colorScheme.onSurfaceVariant),
                title: Text('None'),
                subtitle: Text('Waiting for a live device scan.'),
              )
            else
              ...actions.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.schedule, color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    '${item['timing']}',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text('${item['action']}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rotation({required bool isLive}) {
    final items = isLive ? _list(_plan?['rotation_plan']) : const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Crop Rotation Plan',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            if (items.isEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('0')),
                title: Text('None'),
                subtitle: Text('No active rotation plan.'),
              )
            else
              ...items.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryGreen.withOpacity(.1),
                    child: Text(
                      '${item['season']}'.replaceAll('Cycle ', ''),
                    ),
                  ),
                  title: Text(
                    '${item['crop']}',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text('${item['reason']}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _water({required bool isLive}) {
    final Map<String, dynamic> water = isLive
        ? _map(_plan?['water_requirements'])
        : <String, dynamic>{};
    final advice = isLive && _geminiResult?.isSuccess == true
        ? _geminiResult!.advice
        : null;
    final soilManagement = _aiText(advice, 'soilManagement');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Irrigation Guidance',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text('Current moisture: ${isLive ? water['current_moisture'] ?? 0 : 0}%'),
            Text(
              isLive ? '${water['action'] ?? 'None'}' : 'None',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isLive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 4),
            Text(
              isLive
                  ? '${water['guidance'] ?? 'None'}'
                  : 'No live moisture reading is available.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (soilManagement.isNotEmpty) ...[
              Divider(height: 20),
              Text(
                'Soil management',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                soilManagement,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _plantingWindowText(Map<String, dynamic> schedule) {
    final start = (schedule['start_date'] ?? 'None').toString().trim();
    final end = (schedule['end_date'] ?? '').toString().trim();
    if (end.isEmpty || end == 'None') return start;
    return '$start – $end';
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 125,
              child: Text(
                label,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return {};
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return [];
    return value.map(_map).where((item) => item.isNotEmpty).toList();
  }
}
