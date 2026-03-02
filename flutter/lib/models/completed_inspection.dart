class InspectionAnswer {
  final String questionText;
  final String answerText;

  InspectionAnswer({
    required this.questionText,
    required this.answerText,
  });

  factory InspectionAnswer.fromJson(Map<String, dynamic> json) {
    return InspectionAnswer(
      questionText: json['questionText'] as String? ??
          json['question_text'] as String? ??
          json['Question text'] as String? ??
          '',
      answerText: json['answerText'] as String? ??
          json['answer_text'] as String? ??
          json['Answer text'] as String? ??
          '',
    );
  }
}

class CompletedInspection {
  final String id;
  final DateTime? date;
  final List<InspectionAnswer> answers;

  CompletedInspection({
    required this.id,
    this.date,
    this.answers = const [],
  });

  factory CompletedInspection.fromJson(Map<String, dynamic> json) {
    final rawAnswers = json['answers'] ??
        json['list_of_question_answers'] ??
        json['List of question answers'];
    final answers = rawAnswers is List
        ? rawAnswers
            .whereType<Map<String, dynamic>>()
            .map((e) => InspectionAnswer.fromJson(e))
            .toList()
        : <InspectionAnswer>[];

    DateTime? date;
    final rawDate = json['date'] ?? json['Date'];
    if (rawDate is String) date = DateTime.tryParse(rawDate);

    return CompletedInspection(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      date: date,
      answers: answers,
    );
  }
}
