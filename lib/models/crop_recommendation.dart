class CropRecommendation {
  final String cropName;
  final String suitability;
  final String reason;
  final String season;

  CropRecommendation({
    required this.cropName,
    required this.suitability,
    required this.reason,
    required this.season,
  });

  factory CropRecommendation.fromMap(Map<String, dynamic> map) {
    return CropRecommendation(
      cropName: map['name'] ?? '',
      suitability: map['suitability'] ?? 'Low',
      reason: map['reason'] ?? '',
      season: map['season'] ?? '',
    );
  }
}

class SmartPlan {
  final String crop;
  final Map<String, dynamic> plantingSchedule;
  final Map<String, dynamic> harvestTimeline;
  final List<Map<String, dynamic>> rotationPlan;
  final List<Map<String, dynamic>> fertilizerSchedule;

  SmartPlan({
    required this.crop,
    required this.plantingSchedule,
    required this.harvestTimeline,
    required this.rotationPlan,
    required this.fertilizerSchedule,
  });

  factory SmartPlan.fromMap(Map<String, dynamic> map) {
    return SmartPlan(
      crop: map['crop'] ?? '',
      plantingSchedule: map['planting_schedule'] ?? {},
      harvestTimeline: map['harvest_timeline'] ?? {},
      rotationPlan: List<Map<String, dynamic>>.from(map['rotation_plan'] ?? []),
      fertilizerSchedule: List<Map<String, dynamic>>.from(map['fertilizer_schedule'] ?? []),
    );
  }
}