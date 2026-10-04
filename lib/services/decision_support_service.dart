import 'package:intl/intl.dart';

/// Explainable decision-support engine driven entirely by the latest sensor
/// values. It does not fabricate readings and does not require an API key.
class DecisionSupportService {
  static const List<String> supportedCrops = [
    'Rice',
    'Corn',
    'Tomato',
    'Mung Bean',
    'Peanut',
    'Cassava',
    'Eggplant',
    'Okra',
    'Chili Pepper',
    'Bell Pepper',
    'Squash',
    'Bitter Gourd (Ampalaya)',
    'Cucumber',
    'Sitaw',
    'Pechay',
    'Kangkong',
    'Mustard Greens',
    'Cabbage',
    'Lettuce',
    'Sweet Potato (Kamote)',
    'Taro (Gabi)',
    'Onion',
    'Garlic',
    'Ginger',
    'Turmeric',
    'Soybean',
    'Watermelon',
    'Melon',
    'Pineapple',
    'Papaya',
    'Banana',
  ];

  /// SoilSense project reference bands used for the balance score and the
  /// Low / Normal / High labels. These are decision-support reference bands,
  /// not universal laboratory sufficiency ranges for every crop or soil type.
  static const Map<String, List<double>> referenceRanges = {
    'nitrogen': [40.0, 100.0],
    'phosphorus': [50.0, 120.0],
    'potassium': [100.0, 300.0],
    'ph': [5.5, 7.5],
    'moisture': [40.0, 90.0],
  };

  /// Crops below this score are kept visible as Not Recommended, but are not
  /// allowed to become a Best Match, Smart Recommendation, crop plan, or
  /// report planting recommendation.
  static const double minimumRecommendedCropScore = 50.0;

  static const Map<String, Map<String, dynamic>> _cropProfiles = {
    'Rice': {
      'n': [40.0, 100.0], 'p': [30.0, 80.0], 'k': [60.0, 160.0],
      'ph': [5.0, 7.0], 'moisture': [60.0, 95.0],
      'months': [6, 7, 8, 9, 10, 11], 'season': 'Wet season (June-November)',
      'maturity': 120, 'water': 'Maintain consistently moist soil; avoid prolonged drying.',
    },
    'Corn': {
      'n': [50.0, 100.0], 'p': [35.0, 80.0], 'k': [80.0, 180.0],
      'ph': [5.5, 7.5], 'moisture': [45.0, 70.0],
      'months': [11, 12, 1, 2, 3, 4, 5], 'season': 'Dry season (November-May)',
      'maturity': 100, 'water': 'Water deeply when moisture falls below 45%.',
    },
    'Tomato': {
      'n': [45.0, 90.0], 'p': [40.0, 90.0], 'k': [100.0, 220.0],
      'ph': [5.8, 7.0], 'moisture': [45.0, 70.0],
      'months': [11, 12, 1, 2, 3, 4], 'season': 'Cooler dry months (November-April)',
      'maturity': 85, 'water': 'Keep moisture even; avoid waterlogging and sudden drying.',
    },
    'Mung Bean': {
      'n': [20.0, 60.0], 'p': [30.0, 70.0], 'k': [50.0, 130.0],
      'ph': [5.8, 7.2], 'moisture': [35.0, 60.0],
      'months': [1, 2, 3, 4, 10, 11, 12], 'season': 'Dry season',
      'maturity': 70, 'water': 'Use light irrigation; do not keep the root zone saturated.',
    },
    'Peanut': {
      'n': [20.0, 60.0], 'p': [30.0, 75.0], 'k': [60.0, 150.0],
      'ph': [5.8, 7.0], 'moisture': [35.0, 60.0],
      'months': [11, 12, 1, 2, 3, 4, 5], 'season': 'Dry season (November-May)',
      'maturity': 105, 'water': 'Keep moderately moist during flowering and pod formation.',
    },
    'Cassava': {
      'n': [30.0, 80.0], 'p': [25.0, 70.0], 'k': [80.0, 200.0],
      'ph': [5.0, 7.0], 'moisture': [35.0, 70.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round when drainage is adequate',
      'maturity': 270, 'water': 'Water during establishment, then mainly during extended dry periods.',
    },
    'Eggplant': {
      'n': [45.0, 90.0], 'p': [30.0, 75.0], 'k': [80.0, 180.0],
      'ph': [5.5, 7.0], 'moisture': [45.0, 70.0],
      'months': [1, 2, 3, 4, 5, 10, 11, 12], 'season': 'Best in relatively dry months; can be grown year-round with drainage',
      'maturity': 90, 'water': 'Keep soil evenly moist without waterlogging.',
    },
    'Okra': {
      'n': [35.0, 80.0], 'p': [30.0, 70.0], 'k': [60.0, 140.0],
      'ph': [6.0, 7.5], 'moisture': [40.0, 65.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round in warm conditions',
      'maturity': 60, 'water': 'Maintain moderate moisture, especially during flowering and pod development.',
    },
    'Chili Pepper': {
      'n': [40.0, 90.0], 'p': [35.0, 80.0], 'k': [90.0, 200.0],
      'ph': [5.5, 7.0], 'moisture': [45.0, 70.0],
      'months': [10, 11, 12, 1, 2, 3, 4, 5], 'season': 'Relatively dry months are preferred',
      'maturity': 95, 'water': 'Keep moisture steady and avoid prolonged saturation.',
    },
    'Bell Pepper': {
      'n': [45.0, 95.0], 'p': [40.0, 85.0], 'k': [100.0, 220.0],
      'ph': [5.8, 7.0], 'moisture': [45.0, 70.0],
      'months': [11, 12, 1, 2, 3, 4], 'season': 'Cooler dry months',
      'maturity': 95, 'water': 'Maintain even moisture and good drainage.',
    },
    'Squash': {
      'n': [35.0, 80.0], 'p': [30.0, 70.0], 'k': [80.0, 180.0],
      'ph': [5.5, 7.5], 'moisture': [40.0, 70.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round with adequate drainage',
      'maturity': 90, 'water': 'Water deeply but allow the surface soil to drain between irrigations.',
    },
    'Bitter Gourd (Ampalaya)': {
      'n': [40.0, 85.0], 'p': [35.0, 80.0], 'k': [90.0, 190.0],
      'ph': [5.5, 7.0], 'moisture': [45.0, 70.0],
      'months': [1, 2, 3, 4, 5, 10, 11, 12], 'season': 'Best in relatively dry months',
      'maturity': 75, 'water': 'Keep the root zone consistently moist but well drained.',
    },
    'Cucumber': {
      'n': [40.0, 85.0], 'p': [35.0, 80.0], 'k': [90.0, 190.0],
      'ph': [5.5, 7.0], 'moisture': [50.0, 75.0],
      'months': [11, 12, 1, 2, 3, 4, 5], 'season': 'Dry to early wet season',
      'maturity': 55, 'water': 'Maintain consistent moisture during flowering and fruiting.',
    },
    'Sitaw': {
      'n': [20.0, 60.0], 'p': [30.0, 70.0], 'k': [50.0, 130.0],
      'ph': [5.5, 7.0], 'moisture': [40.0, 65.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round in warm conditions',
      'maturity': 60, 'water': 'Provide regular light irrigation and avoid standing water.',
    },
    'Pechay': {
      'n': [40.0, 90.0], 'p': [30.0, 70.0], 'k': [60.0, 140.0],
      'ph': [5.8, 7.0], 'moisture': [50.0, 75.0],
      'months': [10, 11, 12, 1, 2, 3], 'season': 'Cooler months are preferred',
      'maturity': 40, 'water': 'Keep soil consistently moist and avoid water stress.',
    },
    'Kangkong': {
      'n': [30.0, 80.0], 'p': [25.0, 60.0], 'k': [50.0, 120.0],
      'ph': [5.5, 7.5], 'moisture': [60.0, 90.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round',
      'maturity': 35, 'water': 'Maintain high soil moisture while avoiding stagnant polluted water.',
    },
    'Mustard Greens': {
      'n': [35.0, 80.0], 'p': [30.0, 65.0], 'k': [60.0, 130.0],
      'ph': [5.8, 7.2], 'moisture': [50.0, 75.0],
      'months': [10, 11, 12, 1, 2, 3], 'season': 'Cooler months are preferred',
      'maturity': 45, 'water': 'Maintain even soil moisture for tender leafy growth.',
    },
    'Cabbage': {
      'n': [50.0, 100.0], 'p': [40.0, 80.0], 'k': [100.0, 220.0],
      'ph': [6.0, 7.5], 'moisture': [55.0, 75.0],
      'months': [10, 11, 12, 1, 2], 'season': 'Cooler months/highland conditions are preferred',
      'maturity': 100, 'water': 'Maintain even moisture, especially during head formation.',
    },
    'Lettuce': {
      'n': [35.0, 75.0], 'p': [30.0, 65.0], 'k': [60.0, 130.0],
      'ph': [6.0, 7.0], 'moisture': [50.0, 70.0],
      'months': [11, 12, 1, 2], 'season': 'Cooler months/highland conditions are preferred',
      'maturity': 50, 'water': 'Keep the root zone evenly moist and cool when possible.',
    },
    'Sweet Potato (Kamote)': {
      'n': [25.0, 65.0], 'p': [25.0, 60.0], 'k': [70.0, 160.0],
      'ph': [5.2, 6.8], 'moisture': [35.0, 65.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round where drainage is good',
      'maturity': 120, 'water': 'Water during establishment, then avoid excessive moisture.',
    },
    'Taro (Gabi)': {
      'n': [30.0, 75.0], 'p': [25.0, 65.0], 'k': [70.0, 160.0],
      'ph': [5.5, 7.0], 'moisture': [60.0, 90.0],
      'months': [4, 5, 6, 7, 8, 9, 10], 'season': 'Wet-season planting is favorable where drainage is managed',
      'maturity': 210, 'water': 'Maintain high moisture but avoid damaging prolonged flooding for upland types.',
    },
    'Onion': {
      'n': [35.0, 75.0], 'p': [35.0, 75.0], 'k': [70.0, 150.0],
      'ph': [5.8, 7.0], 'moisture': [35.0, 60.0],
      'months': [11, 12, 1, 2, 3, 4], 'season': 'Dry season',
      'maturity': 110, 'water': 'Use light regular irrigation and reduce water near maturity.',
    },
    'Garlic': {
      'n': [30.0, 70.0], 'p': [30.0, 70.0], 'k': [60.0, 140.0],
      'ph': [5.5, 7.0], 'moisture': [30.0, 55.0],
      'months': [11, 12, 1, 2, 3], 'season': 'Dry, cooler months',
      'maturity': 120, 'water': 'Keep moderately moist early, then reduce irrigation before harvest.',
    },
    'Ginger': {
      'n': [35.0, 80.0], 'p': [30.0, 70.0], 'k': [80.0, 170.0],
      'ph': [5.5, 6.8], 'moisture': [50.0, 75.0],
      'months': [3, 4, 5, 6], 'season': 'Plant near the start of the rainy season with good drainage',
      'maturity': 240, 'water': 'Maintain steady moisture without waterlogging the rhizomes.',
    },
    'Turmeric': {
      'n': [35.0, 80.0], 'p': [30.0, 65.0], 'k': [80.0, 170.0],
      'ph': [5.5, 7.0], 'moisture': [50.0, 75.0],
      'months': [3, 4, 5, 6], 'season': 'Plant near the start of the rainy season with good drainage',
      'maturity': 240, 'water': 'Keep soil moist during active growth and reduce water near maturity.',
    },
    'Soybean': {
      'n': [20.0, 60.0], 'p': [30.0, 75.0], 'k': [50.0, 130.0],
      'ph': [5.8, 7.0], 'moisture': [40.0, 65.0],
      'months': [10, 11, 12, 1, 2, 3], 'season': 'Dry season is generally easier to manage',
      'maturity': 95, 'water': 'Maintain moderate moisture during flowering and pod filling.',
    },
    'Watermelon': {
      'n': [35.0, 80.0], 'p': [35.0, 75.0], 'k': [80.0, 180.0],
      'ph': [5.5, 7.0], 'moisture': [35.0, 60.0],
      'months': [11, 12, 1, 2, 3, 4], 'season': 'Dry season',
      'maturity': 80, 'water': 'Water consistently during establishment and fruit set; avoid saturation.',
    },
    'Melon': {
      'n': [35.0, 80.0], 'p': [35.0, 75.0], 'k': [80.0, 180.0],
      'ph': [5.8, 7.0], 'moisture': [35.0, 60.0],
      'months': [11, 12, 1, 2, 3, 4], 'season': 'Dry season',
      'maturity': 80, 'water': 'Maintain moderate moisture and reduce excess water as fruits mature.',
    },
    'Pineapple': {
      'n': [25.0, 60.0], 'p': [20.0, 55.0], 'k': [80.0, 180.0],
      'ph': [4.5, 6.5], 'moisture': [35.0, 65.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round in suitable tropical sites',
      'maturity': 540, 'water': 'Avoid waterlogging; established plants tolerate short dry periods.',
    },
    'Papaya': {
      'n': [40.0, 90.0], 'p': [35.0, 80.0], 'k': [90.0, 200.0],
      'ph': [5.5, 7.0], 'moisture': [45.0, 70.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round with good drainage',
      'maturity': 270, 'water': 'Keep moisture regular while preventing waterlogging around roots.',
    },
    'Banana': {
      'n': [50.0, 110.0], 'p': [35.0, 85.0], 'k': [120.0, 280.0],
      'ph': [5.5, 7.0], 'moisture': [55.0, 80.0],
      'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'season': 'Year-round in warm tropical conditions',
      'maturity': 330, 'water': 'Maintain consistent moisture and good drainage throughout growth.',
    },
  };

  static Map<String, double> _values(Map<String, dynamic> soilData) => {
        'n': _asDouble(soilData['nitrogen']),
        'p': _asDouble(soilData['phosphorus']),
        'k': _asDouble(soilData['potassium']),
        'ph': _asDouble(soilData['ph']),
        'moisture': _asDouble(soilData['moisture']),
      };

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _rangeScore(double value, List<dynamic> rawRange) {
    final min = (rawRange[0] as num).toDouble();
    final max = (rawRange[1] as num).toDouble();
    if (value >= min && value <= max) return 100;
    final span = (max - min).abs().clamp(1.0, double.infinity);
    final distance = value < min ? min - value : value - max;
    return (100 - (distance / span * 100)).clamp(0, 100).toDouble();
  }

  static String _status(double value, double low, double high) {
    if (value < low) return 'Low';
    if (value > high) return 'High';
    return 'Normal';
  }

  static String _soilCondition(double score) {
    if (score >= 75) return 'Balanced';
    if (score >= 50) return 'Fair';
    return 'Needs Attention';
  }

  static Future<Map<String, dynamic>> analyzeSoil(
    Map<String, dynamic> soilData,
  ) async {
    final values = _values(soilData);
    final nitrogen = values['n']!;
    final phosphorus = values['p']!;
    final potassium = values['k']!;
    final ph = values['ph']!;
    final moisture = values['moisture']!;

    final nScore = _rangeScore(nitrogen, referenceRanges['nitrogen']!);
    final pScore = _rangeScore(phosphorus, referenceRanges['phosphorus']!);
    final kScore = _rangeScore(potassium, referenceRanges['potassium']!);
    final phScore = _rangeScore(ph, referenceRanges['ph']!);
    final moistureScore = _rangeScore(moisture, referenceRanges['moisture']!);
    final score = nScore * .22 + pScore * .22 + kScore * .22 + phScore * .18 + moistureScore * .16;

    final deficiencies = <String>[];
    final imbalances = <String>[];
    if (nitrogen < 40) deficiencies.add('Nitrogen');
    if (phosphorus < 50) deficiencies.add('Phosphorus');
    if (potassium < 100) deficiencies.add('Potassium');
    if (moisture < 40) deficiencies.add('Moisture');
    if (nitrogen > 100) imbalances.add('Excess nitrogen');
    if (phosphorus > 120) imbalances.add('Excess phosphorus');
    if (potassium > 300) imbalances.add('Excess potassium');
    if (moisture > 90) imbalances.add('Excess moisture');
    if (ph < 5.5) imbalances.add('Acidic pH');
    if (ph > 7.5) imbalances.add('Alkaline pH');

    final crops = await getCropRecommendations(soilData);
    final bestCrop = crops['best_crop'] as Map<String, dynamic>?;
    final applyActions = <String>[];
    if (nitrogen < 40) applyActions.add('Apply a nitrogen source based on a local soil-test recommendation.');
    if (phosphorus < 50) applyActions.add('Apply a phosphorus source before planting and incorporate it into the soil.');
    if (potassium < 100) applyActions.add('Apply a potassium source in split doses to reduce nutrient loss.');
    if (ph < 5.5) applyActions.add('Apply agricultural lime only after confirming the lime requirement with a laboratory test.');
    if (ph > 7.5) applyActions.add('Add organic matter and seek local guidance before using acidifying amendments.');
    if (moisture < 40) applyActions.add('Irrigate now and recheck moisture after water has infiltrated.');
    if (moisture > 90) applyActions.add('Stop irrigation and inspect drainage immediately.');
    if (nitrogen > 100) {
      applyActions.add('Avoid additional nitrogen until a calibrated soil test confirms that more is needed.');
    }
    if (phosphorus > 120) {
      applyActions.add('Avoid additional phosphorus until the high reading is confirmed locally.');
    }
    if (potassium > 300) {
      applyActions.add('Avoid additional potassium until the high reading is confirmed locally.');
    }
    if (applyActions.isEmpty) {
      applyActions.add('Maintain current soil management and continue sensor monitoring.');
    }

    final whenActions = <String>[];
    if (deficiencies.isNotEmpty || imbalances.isNotEmpty) {
      whenActions.add('Act before planting or within the next 24 hours for moisture-related issues.');
    } else {
      whenActions.add('Review readings at least daily and before any fertilizer or irrigation event.');
    }
    whenActions.add('Confirm fertilizer quantities with a calibrated soil test and local agricultural guidance.');

    return {
      'engine': 'SoilSense explainable expert-system decision support',
      'engine_type': 'rule_based_expert_system',
      'engine_version': '1.3.0',
      'model_notice': 'The SoilSense score measures balance against project reference ranges. Both deficient and excessive readings reduce the score.',
      // Keep the legacy fertility fields for previously written UI/report data,
      // but new screens use soil_condition + balance_score to avoid implying
      // that an excessive nutrient level means healthy fertility.
      'fertility_level': _soilCondition(score),
      'fertility_score': double.parse(score.toStringAsFixed(1)),
      'soil_condition': _soilCondition(score),
      'balance_score': double.parse(score.toStringAsFixed(1)),
      'reference_ranges': referenceRanges,
      'deficiencies': deficiencies,
      'imbalances': imbalances,
      'nutrient_status': {
        'nitrogen': {'level': _status(nitrogen, 40, 100), 'value': nitrogen, 'unit': 'mg/kg'},
        'phosphorus': {'level': _status(phosphorus, 50, 120), 'value': phosphorus, 'unit': 'mg/kg'},
        'potassium': {'level': _status(potassium, 100, 300), 'value': potassium, 'unit': 'mg/kg'},
        'ph': {'level': _status(ph, 5.5, 7.5), 'value': ph, 'unit': ''},
        'moisture': {'level': _status(moisture, 40, 90), 'value': moisture, 'unit': '%'},
      },
      'recommended_crops': <dynamic>[
        ...((crops['highly_suitable'] as List?) ?? const []),
        ...((crops['moderately_suitable'] as List?) ?? const []),
      ].take(5).toList(),
      'decision_support': {
        'what_to_plant': bestCrop == null
            ? 'No suitable crop is recommended for the current reading.'
            : '${bestCrop['name']} (${bestCrop['confidence']} match)',
        'what_to_apply': applyActions,
        'when_to_act': whenActions,
      },
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static Future<Map<String, dynamic>> getCropRecommendations(
    Map<String, dynamic> soilData,
  ) async {
    final values = _values(soilData);
    final month = DateTime.now().month;
    final ranked = <Map<String, dynamic>>[];

    for (final entry in _cropProfiles.entries) {
      final profile = entry.value;
      final nutrientScore =
          _rangeScore(values['n']!, profile['n'] as List) * .23 +
              _rangeScore(values['p']!, profile['p'] as List) * .18 +
              _rangeScore(values['k']!, profile['k'] as List) * .20 +
              _rangeScore(values['ph']!, profile['ph'] as List) * .19 +
              _rangeScore(values['moisture']!, profile['moisture'] as List) * .20;
      final inSeason = (profile['months'] as List).contains(month);
      final score = (nutrientScore * .9 + (inSeason ? 10 : 3)).clamp(0, 100);
      final limiting = _limitingFactors(values, profile);
      ranked.add({
        'name': entry.key,
        'score': double.parse(score.toStringAsFixed(1)),
        'confidence': '${score.round()}%',
        'season': profile['season'],
        'seasonal_compatibility': inSeason ? 'Compatible now' : 'Outside preferred season',
        'reason': limiting.isEmpty
            ? 'Current nutrient, pH, moisture, and seasonal conditions are within the preferred range.'
            : 'Main constraints: ${limiting.join(', ')}.',
      });
    }

    ranked.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    final topFive = ranked.take(5).toList();
    final high = topFive.where((item) => (item['score'] as double) >= 75).toList();
    final medium = topFive.where((item) {
      final score = item['score'] as double;
      return score >= 50 && score < 75;
    }).toList();
    final low = topFive.where((item) => (item['score'] as double) < 50).toList();

    final bestRecommended = topFive.isNotEmpty &&
            (topFive.first['score'] as double) >= minimumRecommendedCropScore
        ? topFive.first
        : null;

    return {
      'highly_suitable': high,
      'moderately_suitable': medium,
      'not_recommended': low,
      'best_crop': bestRecommended,
      'has_recommended_crop': bestRecommended != null,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static List<String> _limitingFactors(
    Map<String, double> values,
    Map<String, dynamic> profile,
  ) {
    const labels = {'n': 'nitrogen', 'p': 'phosphorus', 'k': 'potassium', 'ph': 'pH', 'moisture': 'moisture'};
    final result = <String>[];
    for (final key in labels.keys) {
      final range = profile[key] as List;
      final value = values[key]!;
      final min = (range[0] as num).toDouble();
      final max = (range[1] as num).toDouble();
      if (value < min) result.add('low ${labels[key]}');
      if (value > max) result.add('high ${labels[key]}');
    }
    return result.take(3).toList();
  }

  static Future<Map<String, dynamic>> getSmartPlanning({
    required Map<String, dynamic> soilData,
    required String crop,
    String? season,
  }) async {
    final profile = _cropProfiles[crop] ?? _cropProfiles['Corn']!;
    final values = _values(soilData);
    final now = DateTime.now();
    final preferredMonths = (profile['months'] as List).cast<int>();
    DateTime start = DateTime(now.year, now.month, now.day);
    if (!preferredMonths.contains(now.month)) {
      for (var offset = 1; offset <= 12; offset++) {
        final candidate = DateTime(now.year, now.month + offset, 1);
        if (preferredMonths.contains(candidate.month)) {
          start = candidate;
          break;
        }
      }
    }
    final end = start.add(const Duration(days: 21));
    final maturityDays = profile['maturity'] as int;
    final harvest = start.add(Duration(days: maturityDays));
    final analysis = await analyzeSoilWithoutCropRecursion(soilData);
    final rotationCrops = <String>[
      'Mung Bean',
      'Corn',
      'Sweet Potato (Kamote)',
      'Pechay',
      'Peanut',
    ].where((item) => item != crop).take(3).toList();

    return {
      'crop': crop,
      'planting_schedule': {
        'start_date': DateFormat('MMM d, yyyy').format(start),
        'end_date': DateFormat('MMM d, yyyy').format(end),
        'days_to_mature': maturityDays,
        'best_time': 'Early morning or late afternoon',
        'season': profile['season'],
      },
      'harvest_timeline': {
        'expected_date': DateFormat('MMM d, yyyy').format(harvest),
        'days_from_planting': maturityDays,
        'note': 'Actual harvest timing depends on variety, weather, and field conditions.',
      },
      'rotation_plan': [
        {'season': 'Cycle 1', 'crop': crop, 'reason': 'Recommended main crop for the current soil reading.'},
        {'season': 'Cycle 2', 'crop': rotationCrops[0], 'reason': 'Changes nutrient demand and supports crop rotation diversity.'},
        {'season': 'Cycle 3', 'crop': rotationCrops[1], 'reason': 'Provides a different rooting and nutrient-use pattern.'},
        {'season': 'Cycle 4', 'crop': rotationCrops[2], 'reason': 'Adds another Philippines-supported crop to the rotation sequence.'},
      ],
      'action_schedule': [
        {'timing': 'Before planting', 'action': (analysis['what_to_apply'] as List).first},
        {'timing': 'At planting', 'action': 'Record a baseline sensor reading and confirm field drainage.'},
        {'timing': 'Every 24 hours', 'action': 'Review moisture and nutrient alerts in SoilSense.'},
        {'timing': 'Before harvest', 'action': 'Review crop maturity and avoid unnecessary fertilizer applications.'},
      ],
      'water_requirements': {
        'guidance': profile['water'],
        'current_moisture': values['moisture'],
        'action': values['moisture']! < (profile['moisture'] as List)[0]
            ? 'Irrigation is needed.'
            : (values['moisture']! > (profile['moisture'] as List)[1]
                ? 'Pause irrigation and check drainage.'
                : 'Current moisture is acceptable.'),
      },
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static Future<Map<String, dynamic>> analyzeSoilWithoutCropRecursion(
    Map<String, dynamic> soilData,
  ) async {
    final values = _values(soilData);
    final actions = <String>[];
    if (values['n']! < 40) actions.add('Correct nitrogen deficiency using a locally recommended rate.');
    if (values['p']! < 50) actions.add('Correct phosphorus deficiency before planting.');
    if (values['k']! < 100) actions.add('Correct potassium deficiency using split applications.');
    if (values['ph']! < 5.5) actions.add('Confirm lime requirement before applying agricultural lime.');
    if (values['ph']! > 7.5) actions.add('Increase organic matter and obtain local amendment advice.');
    if (values['moisture']! < 40) actions.add('Irrigate now and recheck the sensor.');
    if (values['moisture']! > 90) actions.add('Pause irrigation and improve drainage.');
    if (actions.isEmpty) actions.add('No immediate soil correction is indicated by the current thresholds.');
    return {'what_to_apply': actions};
  }
}
