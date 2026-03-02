class Question {
  final String id;
  final String questionText;

  Question({
    required this.id,
    required this.questionText,
  });

  /// Parse from a Bubble JSON object.
  /// Actual field names from API: question_id, question_text, linked_asset_id
  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['question_id'] as String? ??
          json['id'] as String? ??
          json['_id'] as String? ??
          '',
      questionText: json['question_text'] as String? ??
          json['questionText'] as String? ??
          json['Question text'] as String? ??
          '',
    );
  }
}
