import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  ApiConfig._();

  /// Bubble API base URL (e.g. https://app.blockpro.co.uk/version-test/api/1.1/wf/)
  static String get baseUrl => dotenv.env['BUBBLE_API_BASE_URL']!;
}
