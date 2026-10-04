import 'package:flutter_test/flutter_test.dart';
import 'package:soilsense/services/decision_support_service.dart';

void main() {
  const optimalReading = <String, dynamic>{
    'nitrogen': 70,
    'phosphorus': 80,
    'potassium': 200,
    'ph': 6.5,
    'moisture': 60,
  };

  group('DecisionSupportService', () {
    test('classifies an in-range reading as balanced', () async {
      final result = await DecisionSupportService.analyzeSoil(optimalReading);

      expect(result['engine_type'], 'rule_based_expert_system');
      expect(result['engine_version'], '1.3.0');
      expect(result['soil_condition'], 'Balanced');
      expect((result['balance_score'] as num).toDouble(), 100);
      expect(result['deficiencies'], isEmpty);
      expect(result['imbalances'], isEmpty);
    });

    test('identifies low nutrient and moisture conditions', () async {
      final result = await DecisionSupportService.analyzeSoil({
        'nitrogen': 10,
        'phosphorus': 20,
        'potassium': 40,
        'ph': 4.8,
        'moisture': 15,
      });

      final deficiencies = (result['deficiencies'] as List).cast<String>();
      final imbalances = (result['imbalances'] as List).cast<String>();

      expect(deficiencies, containsAll(<String>[
        'Nitrogen',
        'Phosphorus',
        'Potassium',
        'Moisture',
      ]));
      expect(imbalances, contains('Acidic pH'));
      expect(result['soil_condition'], 'Needs Attention');
    });

    test('returns ranked crop recommendations', () async {
      final result =
          await DecisionSupportService.getCropRecommendations(optimalReading);
      final bestCrop = result['best_crop'] as Map<String, dynamic>?;
      final total = (result['highly_suitable'] as List).length +
          (result['moderately_suitable'] as List).length +
          (result['not_recommended'] as List).length;

      expect(bestCrop, isNotNull);
      expect(bestCrop!['name'], isNotEmpty);
      expect((bestCrop['score'] as num).toDouble(), inInclusiveRange(0, 100));
      expect(total, 5);
    });


    test('does not recommend a crop when all top matches are below 50 percent', () async {
      const excessiveReading = <String, dynamic>{
        'nitrogen': 259.1,
        'phosphorus': 645.4,
        'potassium': 642.5,
        'ph': 7.3,
        'moisture': 86.9,
      };

      final analysis = await DecisionSupportService.analyzeSoil(excessiveReading);
      final ranking =
          await DecisionSupportService.getCropRecommendations(excessiveReading);

      expect(analysis['soil_condition'], 'Needs Attention');
      expect((analysis['imbalances'] as List), contains('Excess nitrogen'));
      expect((analysis['imbalances'] as List), contains('Excess phosphorus'));
      expect((analysis['imbalances'] as List), contains('Excess potassium'));
      expect(ranking['best_crop'], isNull);
      expect(ranking['has_recommended_crop'], isFalse);
      expect((ranking['highly_suitable'] as List), isEmpty);
      expect((ranking['moderately_suitable'] as List), isEmpty);
      expect((ranking['not_recommended'] as List), isNotEmpty);
    });

    test('creates a crop plan with dates and actions', () async {
      final plan = await DecisionSupportService.getSmartPlanning(
        soilData: optimalReading,
        crop: 'Corn',
      );

      expect(plan['crop'], 'Corn');
      expect(plan['planting_schedule'], isA<Map<String, dynamic>>());
      expect(plan['harvest_timeline'], isA<Map<String, dynamic>>());
      expect((plan['action_schedule'] as List), isNotEmpty);
      expect((plan['rotation_plan'] as List), hasLength(4));
    });
  });
}
