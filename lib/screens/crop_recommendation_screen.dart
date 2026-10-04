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
import '../widgets/navigation_bar.dart';
import '../widgets/user_app_bar_actions.dart';

class CropRecommendationScreen extends StatefulWidget {
  const CropRecommendationScreen({super.key});

  @override
  State<CropRecommendationScreen> createState() =>
      _CropRecommendationScreenState();
}

class _CropRecommendationScreenState
    extends State<CropRecommendationScreen> {
  SoilData? _soilData;
  Map<String, dynamic>? _recommendations;
  Map<String, dynamic>? _smartPlan;
  bool _isLoading = true;
  bool _rankingLoading = false;
  String? _error;
  String _selectedCrop = '';
  AutomaticAiService? _automaticAiService;
  String? _lastAutomaticReadingSignature;
  bool _automaticSyncInProgress = false;
  GeminiAiResult? _planAiResult;
  bool _planAiLoading = false;

  Map<String, dynamic> get _soilMap => {
        'nitrogen': _soilData?.nitrogen ?? 0,
        'phosphorus': _soilData?.phosphorus ?? 0,
        'potassium': _soilData?.potassium ?? 0,
        'ph': _soilData?.ph ?? 0,
        'moisture': _soilData?.moisture ?? 0,
      };

  @override
  void initState() {
    super.initState();
    _loadData();
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
          _soilData = null;
          _recommendations = null;
          _smartPlan = null;
          _planAiResult = null;
          _rankingLoading = false;
          _planAiLoading = false;
          _lastAutomaticReadingSignature = null;
        });
      });
      return;
    }
    final signature = _readingSignature(reading);
    if (_lastAutomaticReadingSignature == signature ||
        _automaticSyncInProgress) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAutomaticReading(reading);
    });
  }

  Future<void> _syncAutomaticReading(SoilData reading) async {
    final signature = _readingSignature(reading);
    if (_lastAutomaticReadingSignature == signature ||
        _automaticSyncInProgress) {
      return;
    }
    _automaticSyncInProgress = true;
    if (mounted) {
      setState(() {
        _soilData = reading;
        _rankingLoading = true;
        _recommendations = null;
        _smartPlan = null;
        _planAiResult = null;
        _error = null;
      });
    }

    try {
      final soil = <String, dynamic>{
        'nitrogen': reading.nitrogen,
        'phosphorus': reading.phosphorus,
        'potassium': reading.potassium,
        'ph': reading.ph,
        'moisture': reading.moisture,
      };
      final recommendations =
          await DecisionSupportService.getCropRecommendations(soil);
      final best = _asMap(recommendations['best_crop']);
      final crop = best.isEmpty ? '' : (best['name'] ?? '').toString();
      final plan = crop.isEmpty
          ? null
          : await DecisionSupportService.getSmartPlanning(
              soilData: soil,
              crop: crop,
            );
      if (!mounted) return;
      setState(() {
        _soilData = reading;
        _recommendations = recommendations;
        _selectedCrop = crop;
        _smartPlan = plan;
        _planAiResult = null;
        _error = null;
        _isLoading = false;
        _rankingLoading = false;
        _lastAutomaticReadingSignature = signature;
      });

      // Only a deterministically suitable crop can receive a crop plan. AI
      // never upgrades a Not Recommended crop into a plan.
      if (crop.isNotEmpty && context.read<AutomaticAiService>().canRunAi) {
        await _generatePlanAi(crop);
      }
    } catch (error) {
      debugPrint('Automatic crop screen refresh failed: $error');
      if (mounted) {
        setState(() {
          _rankingLoading = false;
          _error = error.toString();
        });
      }
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

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _rankingLoading = true;
        _error = null;
      });
    }
    try {
      final readings =
          await context.read<FirestoreService>().getSoilReadings(limit: 1, includeClearedHistory: true);
      _soilData = readings.isEmpty ? null : readings.first;

      if (_soilData != null) {
        final recommendations =
            await DecisionSupportService.getCropRecommendations(_soilMap);
        final best = _asMap(recommendations['best_crop']);
        _selectedCrop = best.isEmpty ? '' : (best['name'] ?? '').toString();
        final plan = _selectedCrop.isEmpty
            ? null
            : await DecisionSupportService.getSmartPlanning(
                soilData: _soilMap,
                crop: _selectedCrop,
              );
        if (mounted) {
          setState(() {
            _recommendations = recommendations;
            _smartPlan = plan;
            _rankingLoading = false;
          });
        }

        // If the automatic AI service already has this reading, start the
        // focused crop-plan request now. Otherwise its reading listener will
        // trigger _syncAutomaticReading as soon as the scan reaches it.
        final aiReading = context.read<AutomaticAiService>().reading;
        if (aiReading != null &&
            _readingSignature(aiReading) == _readingSignature(_soilData!)) {
          _lastAutomaticReadingSignature = _readingSignature(_soilData!);
          if (_selectedCrop.isNotEmpty &&
              context.read<AutomaticAiService>().canRunAi) {
            await _generatePlanAi(_selectedCrop);
          }
        } else {
          _lastAutomaticReadingSignature = null;
        }
      } else if (mounted) {
        setState(() {
          _recommendations = null;
          _smartPlan = null;
          _planAiResult = null;
          _rankingLoading = false;
          _lastAutomaticReadingSignature = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _rankingLoading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changeCrop(String crop) async {
    if (!context.read<DeviceStatusService>().hasDisplayReading) return;
    final normalized = crop.trim();
    if (normalized.isEmpty) return;

    setState(() {
      _selectedCrop = normalized;
      _smartPlan = null;
      _planAiResult = null;
    });

    final plan = await DecisionSupportService.getSmartPlanning(
      soilData: _soilMap,
      crop: normalized,
    );
    if (mounted && _selectedCrop == normalized) {
      setState(() => _smartPlan = plan);
    }

    if (context.read<AutomaticAiService>().canRunAi) {
      await _generatePlanAi(normalized);
    }
  }

  Future<void> _generatePlanAi(String crop) async {
    if (_soilData == null || crop.trim().isEmpty) return;
    if (_planAiLoading) return;

    final automaticAi = context.read<AutomaticAiService>();
    if (!automaticAi.canRunAi) {
      if (mounted) {
        setState(() {
          _planAiLoading = false;
          _planAiResult = GeminiAiResult(
            status: GeminiAiStatus.idle,
            message: automaticAi.pausedReason,
          );
        });
      }
      return;
    }

    if (mounted) setState(() => _planAiLoading = true);
    final result = await automaticAi.generateForCrop(crop);
    if (!mounted) return;
    final currentCrop = _selectedCrop;
    setState(() {
      if (currentCrop == crop) {
        _planAiResult = result;
        if (result.isSuccess) {
          _smartPlan = _planFromAi(result.advice!, crop);
        }
      }
      _planAiLoading = false;
    });

    // If the user changed crops while the request was running, immediately
    // generate guidance for the newly selected crop instead of showing stale AI.
    if (currentCrop != crop) {
      await _generatePlanAi(currentCrop);
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
        title: Text(context.watch<AppSettingsService>().text('Crop Management', 'Pamamahala ng Pananim')),
        centerTitle: true,
        actions: soilSenseUserActions(context),
      ),
      body: _buildBody(deviceStatus),
      bottomNavigationBar: SoilSenseNavBar(currentIndex: 2),
    );
  }

  Widget _buildBody(DeviceStatusService deviceStatus) {
    if ((deviceStatus.isLoading || _isLoading) && _soilData == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: const [
          AiSkeletonLoader(cards: 3),
        ],
      );
    }

    final isLive = deviceStatus.hasDisplayReading;
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null && isLive) ...[
            _buildErrorCard(),
            SizedBox(height: 14),
          ],
          SoilSenseReveal(
            child: _buildRecommendations(isLive: isLive),
          ),
          SizedBox(height: 14),
          SoilSenseReveal(
            delay: Duration(milliseconds: 60),
            child: _buildPlanning(isLive: isLive),
          ),
          SizedBox(height: 14),
          SoilSenseReveal(
            delay: Duration(milliseconds: 120),
            child: _buildDisclaimer(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: AppTheme.warningRed),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Could not calculate recommendations. Pull down to try again.\n$_error',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );


  Widget _buildRecommendations({required bool isLive}) {
    final best = isLive ? _asMap(_recommendations?['best_crop']) : const {};
    final aiService = context.watch<AutomaticAiService>();
    final aiAdvice = isLive && aiService.hasAiAdvice ? aiService.advice : null;
    final aiCropSuggestion = _aiText(aiAdvice, 'cropSuggestion');
    final aiCropReasoning = _aiText(aiAdvice, 'cropReasoning');
    final rankingLoading = isLive && (_rankingLoading || _recommendations == null);
    final aiRankingLoading = isLive &&
        aiService.canRunAi &&
        aiService.result?.status == GeminiAiStatus.loading &&
        !aiService.hasAiAdvice;
    // The deterministic crop ranking should never disappear just because
    // optional AI guidance is still running or retrying in the background.
    // This keeps the screen stable and prevents loading/result flicker.

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
                      'Crop Suitability Ranking',
                      'Ranggo ng Angkop na Pananim',
                    ),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                if (isLive) _inlineAiStatus(aiService),
              ],
            ),
            SizedBox(height: 10),
            if (rankingLoading) ...[
              const AiSkeletonLoader(cards: 3, compact: true),
            ] else ...[
              if (aiRankingLoading) ...[
                Text(
                  'AI is refining the crop ranking...',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warningOrange,
                  ),
                ),
                SizedBox(height: 8),
                const AiSkeletonLoader(cards: 1, compact: true),
                SizedBox(height: 12),
              ],
              if (best.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warningOrange.withOpacity(.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.warningOrange.withOpacity(.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.warningOrange,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No suitable crop currently',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'All evaluated crops are below the 50% suitability threshold. Improve the limiting soil conditions and scan again before creating a crop plan.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(.22),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Best match: ${best['name']} (${best['confidence']})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        aiCropReasoning.isNotEmpty
                            ? aiCropReasoning
                            : (best['reason'] ?? '').toString(),
                        style: TextStyle(fontSize: 13),
                      ),
                      SizedBox(height: 3),
                      Text(
                        (best['seasonal_compatibility'] ?? '').toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                      if (aiCropSuggestion.isNotEmpty) ...[
                        SizedBox(height: 8),
                        Divider(height: 1),
                        SizedBox(height: 8),
                        Text(
                          aiCropSuggestion,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              SizedBox(height: 12),
              if (!isLive)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EmptyRankingRow(label: 'Highly Suitable', value: 'None'),
                    _EmptyRankingRow(
                        label: 'Moderately Suitable', value: 'None'),
                    _EmptyRankingRow(label: 'Not Recommended', value: 'None'),
                  ],
                )
              else ...[
                _group(
                  'Highly Suitable',
                  _asList(_recommendations?['highly_suitable']),
                  Theme.of(context).colorScheme.primary,
                ),
                _group(
                  'Moderately Suitable',
                  _asList(_recommendations?['moderately_suitable']),
                  AppTheme.warningOrange,
                ),
                _group(
                  'Not Recommended',
                  _asList(_recommendations?['not_recommended']),
                  AppTheme.warningRed,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _inlineAiStatus(AutomaticAiService service) {
    final status = service.result?.status;
    final loading =
        service.canRunAi && status == GeminiAiStatus.loading;
    final limited = status == GeminiAiStatus.quotaLimited;
    final ready = status == GeminiAiStatus.ready;

    final label = ready
        ? 'AI ready'
        : loading
            ? (service.isUsingSavedReading ? 'AI analyzing saved data' : 'AI analyzing')
            : !service.canRunAi
                ? 'AI after scan'
                : limited
                    ? 'AI limit reached'
                    : 'Built-in';
    final color = limited
        ? AppTheme.warningRed
        : loading
            ? AppTheme.warningOrange
            : ready
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant;

    return Tooltip(
      message: !service.canRunAi && !ready
          ? service.pausedReason
          : (service.result?.message ?? service.aiReadingContext),
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


  Widget _processingNotice({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warningOrange.withOpacity(.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warningOrange.withOpacity(.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppTheme.warningOrange),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          LinearProgressIndicator(),
        ],
      ),
    );
  }

  Widget _rankingAiNotice(AutomaticAiService service) {
    final status = service.result?.status;
    final loading =
        service.canRunAi && status == GeminiAiStatus.loading;
    final ready = status == GeminiAiStatus.ready;
    final limited = status == GeminiAiStatus.quotaLimited;

    if (!service.canRunAi && !ready) {
      return _smallStatusNotice(
        icon: Icons.schedule_rounded,
        title: 'AI available after first scan',
        message: service.pausedReason,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    if (loading) {
      return _smallStatusNotice(
        icon: Icons.auto_awesome,
        title: service.isUsingSavedReading
            ? 'Ranking ready • AI reviewing saved reading'
            : 'Ranking ready • AI review in progress',
        message: service.isUsingSavedReading
            ? "AI is analyzing this account's latest saved private soil reading. Device offline and Not Owner states do not block analysis of previously owned data."
            : 'The Philippines crop ranking is already available. AI is reviewing the same soil reading for additional recommendation guidance.',
        color: AppTheme.warningOrange,
        showProgress: true,
      );
    }
    if (ready) {
      return const SizedBox.shrink();
    }
    if (limited) {
      return _smallStatusNotice(
        icon: Icons.hourglass_bottom_rounded,
        title: 'Ranking ready • AI limit reached',
        message:
            'The crop ranking remains available from SoilSense scoring. AI enhancement will retry when the service allows it.',
        color: AppTheme.warningRed,
      );
    }
    if (status == GeminiAiStatus.unavailable ||
        status == GeminiAiStatus.notConfigured ||
        status == GeminiAiStatus.authenticationRequired) {
      return _smallStatusNotice(
        icon: Icons.info_outline_rounded,
        title: 'Ranking ready • AI unavailable',
        message:
            'The crop ranking is still usable because it is calculated from the soil reading by SoilSense built-in decision support.',
        color: AppTheme.warningOrange,
      );
    }
    return _smallStatusNotice(
      icon: Icons.schedule_rounded,
      title: 'Ranking ready • AI waiting',
      message:
          'The soil-based ranking is available while SoilSense waits for AI recommendation processing.',
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  Widget _smallStatusNotice({
    required IconData icon,
    required String title,
    required String message,
    required Color color,
    bool showProgress = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(.055),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: color),
              SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 10.8,
                        height: 1.35,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showProgress) ...[
            SizedBox(height: 8),
            LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  String _aiText(Map<String, dynamic>? advice, String key) {
    return advice?[key]?.toString().trim() ?? '';
  }

  String _localPlanGuidance(Map<String, dynamic>? plan) {
    if (plan == null) return '';
    final schedule = _asMap(plan['planting_schedule']);
    final water = _asMap(plan['water_requirements']);
    final harvest = _asMap(plan['harvest_timeline']);
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

  Widget _group(
    String title,
    List<Map<String, dynamic>> crops,
    Color color,
  ) {
    if (crops.isEmpty) {
      return _EmptyRankingRow(label: title, value: 'None');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          SizedBox(height: 4),
          ...crops.map(
            (crop) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: color.withOpacity(.1),
                child: Text(
                  '${(crop['score'] as num?)?.round() ?? 0}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              title: Text(
                (crop['name'] ?? '').toString(),
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '${crop['reason'] ?? ''}\n${crop['season'] ?? ''}',
                style: TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _planningCropChoices() {
    final high = _asList(_recommendations?['highly_suitable']);
    final medium = _asList(_recommendations?['moderately_suitable']);
    final recommended = <Map<String, dynamic>>[...high, ...medium];
    if (recommended.isNotEmpty) return recommended;

    final best = _asMap(_recommendations?['best_crop']);
    return best.isEmpty ? <Map<String, dynamic>>[] : <Map<String, dynamic>>[best];
  }

  String? _planningSelectedCrop() {
    final choices = _planningCropChoices();
    if (choices.isEmpty) return null;
    if (choices.any((crop) => crop['name'] == _selectedCrop)) {
      return _selectedCrop;
    }
    return choices.first['name'].toString();
  }

  String _cropChoiceLabel(Map<String, dynamic> crop) {
    final name = (crop['name'] ?? 'Crop').toString();
    final score = (crop['score'] as num?)?.round();
    final high = _asList(_recommendations?['highly_suitable'])
        .any((item) => item['name'] == crop['name']);
    final medium = _asList(_recommendations?['moderately_suitable'])
        .any((item) => item['name'] == crop['name']);
    final rank = high
        ? 'Highly suitable'
        : medium
            ? 'Moderately suitable'
            : 'Highest ranked';
    return score == null ? '$name • $rank' : '$name • $rank • $score%';
  }

  Widget _buildPlanning({required bool isLive}) {
    final plan = isLive ? _smartPlan : null;
    final schedule = _asMap(plan?['planting_schedule']);
    final harvest = _asMap(plan?['harvest_timeline']);
    final water = _asMap(plan?['water_requirements']);
    final actions = _asList(plan?['action_schedule']);
    final localAdvice = isLive && _planAiResult?.isSuccess == true
        ? _planAiResult!.advice
        : null;
    final aiPlanGuidance = _aiText(localAdvice, 'planningGuidance');
    final planGuidance = aiPlanGuidance.isNotEmpty
        ? aiPlanGuidance
        : _localPlanGuidance(plan);
    final hasSuitableCrop = isLive && _planningCropChoices().isNotEmpty;
    final planBuilding = hasSuitableCrop && _smartPlan == null;
    final firstPlanAiLoading = isLive &&
        hasSuitableCrop &&
        _planAiLoading &&
        _planAiResult == null;
    if (isLive && !hasSuitableCrop && !_rankingLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.watch<AppSettingsService>().text(
                  'Smart Crop Plan',
                  'Smart Crop Plan',
                ),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.block_rounded,
                    color: AppTheme.warningOrange,
                    size: 21,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'No crop plan is generated because every evaluated crop is currently Not Recommended. Improve the soil condition and complete a new scan first.',
                      style: TextStyle(height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    // While the first focused AI crop-plan request is running, use the
    // skeleton instead of showing half-finished plan details. Once a result
    // exists, later non-AI rendering can continue without a fake delay.

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
                      'Smart Crop Plan',
                      'Smart Crop Plan',
                    ),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                if (isLive) _planAiInlineStatus(),
              ],
            ),
            SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: isLive ? _planningSelectedCrop() : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: isLive
                    ? 'Crop from suitability ranking'
                    : 'Crop plan unavailable',
                prefixIcon: Icon(Icons.agriculture),
              ),
              items: _planningCropChoices()
                  .map(
                    (crop) => DropdownMenuItem<String>(
                      value: crop['name'].toString(),
                      child: Text(_cropChoiceLabel(crop)),
                    ),
                  )
                  .toList(),
              onChanged: isLive &&
                      _planningCropChoices().isNotEmpty &&
                      !_rankingLoading
                  ? (crop) {
                      if (crop != null && crop != _selectedCrop) {
                        _changeCrop(crop);
                      }
                    }
                  : null,
            ),
            SizedBox(height: 8),
            Text(
              isLive
                  ? 'Crop choices are taken from the latest soil-based suitability ranking and update after each new scan.'
                  : 'Complete a soil scan to see suitable crop choices.',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (isLive && _shouldShowPlanAiNotice(planBuilding)) ...[
              SizedBox(height: 10),
              _planAiStatusNotice(planBuilding: planBuilding),
            ],
            SizedBox(height: 14),
            if (planBuilding || firstPlanAiLoading)
              const AiSkeletonLoader(cards: 3, compact: true)
            else ...[
              _info(
                'Preferred planting window',
                isLive
                    ? '${schedule['start_date'] ?? 'None'} – ${schedule['end_date'] ?? 'None'}'
                    : 'None',
              ),
              _info('Season', isLive ? '${schedule['season'] ?? 'None'}' : 'None'),
              _info(
                'Days to mature',
                isLive ? '${schedule['days_to_mature'] ?? 0} days' : '0 days',
              ),
              _info(
                'Expected harvest',
                isLive ? '${harvest['expected_date'] ?? 'None'}' : 'None',
              ),
              _info(
                'Water action',
                isLive ? '${water['action'] ?? 'None'}' : 'None',
              ),
              if (planGuidance.isNotEmpty)
                _info('Plan guidance', planGuidance),
              Divider(height: 24),
              Text(
                'Action timeline',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              if (!isLive || actions.isEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.remove_circle_outline,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  title: Text('None'),
                  subtitle: Text('Waiting for a live device scan.'),
                )
              else
                ...actions.map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    title: Text(
                      (item['timing'] ?? '').toString(),
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text((item['action'] ?? '').toString()),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isLive
                      ? () => Navigator.pushNamed(
                            context,
                            '/smart-crop-planning',
                          )
                      : null,
                  icon: Icon(Icons.calendar_month),
                  label: Text('Open Full Planning Tool'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _shouldShowPlanAiNotice(bool planBuilding) {
    // Only show a body notice while the deterministic plan itself is being
    // built. AI progress/errors stay in the compact badge so the card does not
    // jump between loading and content states.
    return planBuilding;
  }

  Widget _planAiInlineStatus() {
    final aiService = context.read<AutomaticAiService>();
    final status = _planAiResult?.status;
    final loading = _planAiLoading || status == GeminiAiStatus.loading;
    final ready = status == GeminiAiStatus.ready;
    final limited = status == GeminiAiStatus.quotaLimited;
    final unavailable = status == GeminiAiStatus.unavailable ||
        status == GeminiAiStatus.notConfigured ||
        status == GeminiAiStatus.authenticationRequired;

    final label = ready
        ? 'AI ready'
        : loading
            ? 'AI working'
            : limited
                ? 'AI limit'
                : unavailable
                    ? 'AI unavailable'
                    : aiService.canRunAi
                        ? 'Plan ready'
                        : 'AI after scan';
    final color = ready
        ? Theme.of(context).colorScheme.primary
        : loading
            ? AppTheme.warningOrange
            : (limited || unavailable)
                ? AppTheme.warningRed
                : Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
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
    );
  }

  Widget _planAiStatusNotice({required bool planBuilding}) {
    final aiService = context.read<AutomaticAiService>();
    if (!aiService.canRunAi && _planAiResult?.status != GeminiAiStatus.ready) {
      return _smallStatusNotice(
        icon: Icons.schedule_rounded,
        title: 'AI available after first scan',
        message: aiService.pausedReason,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    if (planBuilding) {
      return _smallStatusNotice(
        icon: Icons.schedule_rounded,
        title: 'Preparing crop plan',
        message:
            'The selected crop came from the suitability ranking. SoilSense is building its plan from the current soil reading.',
        color: AppTheme.warningOrange,
        showProgress: true,
      );
    }
    if (_planAiLoading || _planAiResult?.status == GeminiAiStatus.loading) {
      return _smallStatusNotice(
        icon: Icons.auto_awesome,
        title: aiService.isUsingSavedReading
            ? 'Crop plan ready • AI analyzing saved reading'
            : 'Crop plan ready • AI enhancement in progress',
        message: aiService.isUsingSavedReading
            ? "AI is enhancing the crop plan from this account's latest saved private reading."
            : 'The complete SoilSense plan is already available from the latest soil reading. AI is adding optional crop-specific detail in the background.',
        color: AppTheme.warningOrange,
        showProgress: true,
      );
    }
    if (_planAiResult?.status == GeminiAiStatus.ready) {
      return const SizedBox.shrink();
    }
    return const SizedBox.shrink();
  }

  Map<String, dynamic> _planFromAi(
    Map<String, dynamic> advice,
    String crop,
  ) {
    String text(String key, [String fallback = 'Not available']) {
      final value = advice[key]?.toString().trim() ?? '';
      return value.isEmpty ? fallback : value;
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
          'reason': text('rotationReason1'),
        },
        <String, dynamic>{
          'season': 'Cycle 3',
          'crop': text('rotationCrop2', 'Alternative rotation crop'),
          'reason': text('rotationReason2'),
        },
        <String, dynamic>{
          'season': 'Cycle 4',
          'crop': text('rotationCrop3', 'Cover crop'),
          'reason': text('rotationReason3'),
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
        'current_moisture': _soilData?.moisture ?? 0,
        'action': text('planningWaterAction'),
      },
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildDisclaimer() => Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Recommendations are based on the latest available soil values. Confirm final crop and fertilizer decisions with a calibrated soil test and a local agricultural specialist.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return {};
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return [];
    return value.map(_asMap).where((item) => item.isNotEmpty).toList();
  }
}

class _EmptyRankingRow extends StatelessWidget {
  const _EmptyRankingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
