/// Maps to the `answertype` field in the v2 checklist response.
/// Values are pipe-delimited, e.g. `"Yes|No"`, `"Satisfactory|Unsatisfactory|N/A"`.
enum AnswerOption {
  yesNo,
  yesNoNA,
  satisfactoryUnsatisfactory,
  satisfactoryUnsatisfactoryNA;

  /// The display labels for each choice in this option set.
  List<String> get labels => switch (this) {
        yesNo => ['Yes', 'No'],
        yesNoNA => ['Yes', 'No', 'N/A'],
        satisfactoryUnsatisfactory => ['Satisfactory', 'Unsatisfactory'],
        satisfactoryUnsatisfactoryNA => [
            'Satisfactory',
            'Unsatisfactory',
            'N/A'
          ],
      };

  /// Which labels count as "negative" (trigger photo when rule is
  /// "Only when unsatisfactory").
  Set<String> get negativeLabels => switch (this) {
        yesNo || yesNoNA => {'No'},
        satisfactoryUnsatisfactory ||
        satisfactoryUnsatisfactoryNA =>
          {'Unsatisfactory'},
      };

  /// Parse from the v2 API `answertype` string (pipe-delimited).
  static AnswerOption? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    return switch (value.trim()) {
      'Yes|No' => AnswerOption.yesNo,
      'Yes|No|N/A' => AnswerOption.yesNoNA,
      'Satisfactory|Unsatisfactory' => AnswerOption.satisfactoryUnsatisfactory,
      'Satisfactory|Unsatisfactory|N/A' =>
        AnswerOption.satisfactoryUnsatisfactoryNA,
      _ => null,
    };
  }

  /// Serialize back to the v2 API format for DB storage.
  String get displayText => switch (this) {
        yesNo => 'Yes|No',
        yesNoNA => 'Yes|No|N/A',
        satisfactoryUnsatisfactory => 'Satisfactory|Unsatisfactory',
        satisfactoryUnsatisfactoryNA => 'Satisfactory|Unsatisfactory|N/A',
      };
}

/// Maps to the `photorequirement` field in the v2 checklist response.
enum PhotoRequirement {
  always,
  onlyWhenNegative;

  /// Parse from the v2 API `photorequirement` string.
  static PhotoRequirement? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    return switch (value.toLowerCase().trim()) {
      'always' => PhotoRequirement.always,
      'only when unsatisfactory' => PhotoRequirement.onlyWhenNegative,
      _ => null,
    };
  }

  /// Serialize back to the v2 API format for DB storage.
  String get displayText => switch (this) {
        always => 'Always',
        onlyWhenNegative => 'Only when unsatisfactory',
      };

  /// Given an answer option type and the currently selected answer,
  /// returns whether a photo is required.
  bool isPhotoRequired(AnswerOption? answerOption, String? selectedAnswer) {
    return switch (this) {
      PhotoRequirement.always => true,
      PhotoRequirement.onlyWhenNegative => selectedAnswer != null &&
          answerOption != null &&
          answerOption.negativeLabels.contains(selectedAnswer),
    };
  }
}

/// A remedial item raised against a question in a prior inspection.
class Remedial {
  final String name;
  final String? description;
  final String? location;
  final DateTime? dueDate;
  final String? priority;

  Remedial({
    required this.name,
    this.description,
    this.location,
    this.dueDate,
    this.priority,
  });

  factory Remedial.fromJson(Map<String, dynamic> json) {
    return Remedial(
      name: json['remedialname'] as String? ?? '',
      description: _emptyToNull(json['remedialdesc'] as String?),
      location: _emptyToNull(json['remediallocation'] as String?),
      dueDate: _parseDate(json['remedialduedate']),
      priority: _emptyToNull(json['remedialpriority'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'remedialname': name,
        if (description != null) 'remedialdesc': description,
        if (location != null) 'remediallocation': location,
        if (dueDate != null) 'remedialduedate': dueDate!.toIso8601String(),
        if (priority != null) 'remedialpriority': priority,
      };

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _emptyToNull(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}

class Question {
  final String id;
  final String questionText;
  final String? description;
  final String chapterId;
  final int orderNumber;
  final AnswerOption? answerOption;
  final PhotoRequirement? photoRequirement;
  final List<Remedial> existingRemedials;

  Question({
    required this.id,
    required this.questionText,
    required this.chapterId,
    this.description,
    this.orderNumber = 0,
    this.answerOption,
    this.photoRequirement,
    this.existingRemedials = const [],
  });

  /// Parse from a v2 checklist question JSON object.
  factory Question.fromJson(
    Map<String, dynamic> json, {
    required String chapterId,
  }) {
    final remedialsRaw = json['existingremedials'];
    final remedials = remedialsRaw is List
        ? remedialsRaw
            .whereType<Map<String, dynamic>>()
            .map(Remedial.fromJson)
            .toList()
        : <Remedial>[];

    return Question(
      id: json['questionid'] as String? ?? '',
      questionText: json['questiontext'] as String? ?? '',
      description: _emptyToNull(json['questiondesc'] as String?),
      chapterId: chapterId,
      orderNumber: (json['questionordernumber'] as num?)?.toInt() ?? 0,
      answerOption: AnswerOption.fromString(json['answertype'] as String?),
      photoRequirement:
          PhotoRequirement.fromString(json['photorequirement'] as String?),
      existingRemedials: remedials,
    );
  }

  static String? _emptyToNull(String? value) {
    if (value == null || value.isEmpty) return null;
    return value;
  }
}

/// A chapter within a checklist — a named grouping of questions.
class Chapter {
  final String id;
  final String assetId;
  final String name;
  final int order;
  final List<Question> questions;

  Chapter({
    required this.id,
    required this.assetId,
    required this.name,
    required this.order,
    this.questions = const [],
  });

  /// Parse from a v2 checklist chapter JSON object.
  ///
  /// The chapter ID is synthesised as `{assetId}_{chapterorder}` because the
  /// API does not return a stable chapter ID.
  factory Chapter.fromJson(Map<String, dynamic> json, {required String assetId}) {
    final order = (json['chapterorder'] as num?)?.toInt() ?? 0;
    final id = '${assetId}_$order';
    final questionsRaw = json['questions'];
    final questions = questionsRaw is List
        ? questionsRaw
            .whereType<Map<String, dynamic>>()
            .map((q) => Question.fromJson(q, chapterId: id))
            .toList()
        : <Question>[];

    return Chapter(
      id: id,
      assetId: assetId,
      name: json['chaptername'] as String? ?? '',
      order: order,
      questions: questions,
    );
  }
}
