import '../../models/grading_scheme.dart';

abstract class GradingRepository {
  Future<List<GradingScheme>> getGradingSchemes();

  Future<void> saveGradingScheme(GradingScheme scheme);

  Future<void> deleteGradingScheme(int id);
}
