import 'dart:math';

import 'new_remedial.dart';
import 'register_item.dart';

/// Status of a queued offline completion as it moves through the outbox.
enum OutboxStatus {
  /// Captured locally, waiting to be sent (the normal resting state).
  pending,

  /// A send attempt is in flight. Persisted *before* the network call so a
  /// crash mid-send is recoverable (an entry found stuck in [sending] on the
  /// next launch is moved to [needsReview], never blind-resent).
  sending,

  /// The send outcome is ambiguous (a non-network error, or a crash while
  /// [sending]) — the server may already hold this completion, so it must NOT
  /// be auto-resent. Surfaced to the user for a manual re-confirm.
  needsReview,

  /// Repeatedly failed on a non-network error past the attempt cap. Surfaced as
  /// a tappable "Retry" so the user can re-queue it.
  failed;

  String get jsonValue => name;

  static OutboxStatus fromJson(String? value) => OutboxStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => OutboxStatus.pending,
      );
}

/// One photo attached to a queued completion.
///
/// [localPath] points to a durable file under
/// `<appDocs>/outbox/<submissionId>/` (see `CompletionPhotoStore`).
/// [uploadedImageId] is filled the instant `app_upload-image_Adam` returns, so a
/// retry only re-uploads photos that haven't succeeded yet.
class OutboxPhoto {
  final String localPath;
  final String? uploadedImageId;

  /// The question this photo belongs to. Used both to regroup photos
  /// per-question when a queued completion is re-opened for review, and to
  /// resolve each answer's `photoid` at drain time (null = inspection-level
  /// header photo, which goes in `inspection_photo_ids` instead).
  final String? questionId;

  const OutboxPhoto({
    required this.localPath,
    this.uploadedImageId,
    this.questionId,
  });

  bool get isUploaded =>
      uploadedImageId != null && uploadedImageId!.isNotEmpty;

  OutboxPhoto copyWith({String? uploadedImageId}) => OutboxPhoto(
        localPath: localPath,
        uploadedImageId: uploadedImageId ?? this.uploadedImageId,
        questionId: questionId,
      );

  Map<String, dynamic> toJson() => {
        'localPath': localPath,
        'uploadedImageId': uploadedImageId,
        'questionId': questionId,
      };

  factory OutboxPhoto.fromJson(Map<String, dynamic> json) => OutboxPhoto(
        localPath: json['localPath'] as String,
        uploadedImageId: json['uploadedImageId'] as String?,
        questionId: json['questionId'] as String?,
      );
}

/// One answer within a queued completion.
///
/// Mirrors the exact payload shape `InspectionNotifier.submit()` builds —
/// [question] is the question *text*, frozen at enqueue so it never has to be
/// re-resolved from the (wipeable) questions table at drain time.
class OutboxAnswer {
  final String question;
  final String answer;

  /// The source question's id. Used to re-map answers onto the checklist when a
  /// queued completion is re-opened (robust to question-text changes), and sent
  /// to the backend as `questionid` on each answer.
  final String? questionId;

  /// The source question's chapter id (`Question.chapterId`), frozen at enqueue.
  /// Sent to the backend as `chapterid` on each answer.
  final String? chapterId;

  /// Remedial raised against this question, frozen at enqueue (already
  /// filtered to non-blank by `QuestionAnswer.effectiveRemedial`).
  final NewRemedial? remedial;

  /// Whether a remedial was *mandatory* on this answer's negative path (true)
  /// rather than optional (false), frozen at enqueue from
  /// `QuestionAnswer.isRemedialRequired` (= negative answer with no prior
  /// remedials on the question). Only meaningful when [remedial] is present;
  /// surfaced to the backend as `remedialtype` ("mandatory"/"optional").
  final bool remedialRequired;

  const OutboxAnswer({
    required this.question,
    required this.answer,
    this.questionId,
    this.chapterId,
    this.remedial,
    this.remedialRequired = false,
  });

  Map<String, dynamic> toJson() => {
        'question': question,
        'answer': answer,
        'questionId': questionId,
        'chapterId': chapterId,
        if (remedial != null) 'remedial': remedial!.toJson(),
        'remedialRequired': remedialRequired,
      };

  factory OutboxAnswer.fromJson(Map<String, dynamic> json) => OutboxAnswer(
        question: (json['question'] as String?) ?? '',
        answer: (json['answer'] as String?) ?? '',
        questionId: json['questionId'] as String?,
        chapterId: json['chapterId'] as String?,
        remedial: json['remedial'] is Map<String, dynamic>
            ? NewRemedial.fromJson(json['remedial'] as Map<String, dynamic>)
            : null,
        remedialRequired: (json['remedialRequired'] as bool?) ?? false,
      );
}

/// A completed inspection captured on-device and queued for upload.
///
/// The entry is FULLY self-contained: replaying it needs nothing from the
/// disposable Drift cache. It is stored as one JSON object in the outbox
/// manifest (see `OutboxStore`) and survives every cache-wipe path (logout,
/// manual refresh, schema migration).
class OutboxEntry {
  /// Stable client idempotency key, generated once at enqueue and reused on
  /// every retry. Local-only for now (it names the photo folder and drives
  /// supersede + single-flight); it is the drop-in server dedup key if the
  /// backend change ever lands.
  final String submissionId;

  /// Owning user's id at enqueue time — the drainer refuses to send an entry
  /// whose uid != the currently authenticated user (cross-user safety).
  final String? uid;

  final String assetId;

  /// The asset's free-text frequency, for the optimistic next-due-date calc.
  final String? frequency;

  /// The asset's `checklistLastModified` at enqueue (ISO-8601), for detecting
  /// checklist drift before draining.
  final String? checklistLastModified;

  final List<OutboxAnswer> answers;
  final List<OutboxPhoto> photos;

  /// Asset register items the inspector tagged the whole inspection with,
  /// frozen at enqueue. Sent as the top-level `registeritems` field on
  /// `app_completed-inspection` (distinct from any per-remedial register items).
  final List<RegisterItem> registerItems;

  final OutboxStatus status;
  final int attemptCount;

  /// Epoch milliseconds. Drain order is [createdAt] ascending (FIFO).
  final int createdAt;
  final int? lastAttemptAt;
  final String? lastError;

  const OutboxEntry({
    required this.submissionId,
    required this.assetId,
    required this.createdAt,
    this.uid,
    this.frequency,
    this.checklistLastModified,
    this.answers = const [],
    this.photos = const [],
    this.registerItems = const [],
    this.status = OutboxStatus.pending,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  OutboxEntry copyWith({
    List<OutboxPhoto>? photos,
    OutboxStatus? status,
    int? attemptCount,
    int? lastAttemptAt,
    String? lastError,
    bool clearError = false,
  }) {
    return OutboxEntry(
      submissionId: submissionId,
      uid: uid,
      assetId: assetId,
      frequency: frequency,
      checklistLastModified: checklistLastModified,
      answers: answers,
      photos: photos ?? this.photos,
      registerItems: registerItems,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      createdAt: createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => {
        'submissionId': submissionId,
        'uid': uid,
        'assetId': assetId,
        'frequency': frequency,
        'checklistLastModified': checklistLastModified,
        'answers': answers.map((a) => a.toJson()).toList(),
        'photos': photos.map((p) => p.toJson()).toList(),
        'registerItems': registerItems.map((r) => r.toJson()).toList(),
        'status': status.jsonValue,
        'attemptCount': attemptCount,
        'createdAt': createdAt,
        'lastAttemptAt': lastAttemptAt,
        'lastError': lastError,
      };

  factory OutboxEntry.fromJson(Map<String, dynamic> json) {
    return OutboxEntry(
      submissionId: json['submissionId'] as String,
      uid: json['uid'] as String?,
      assetId: json['assetId'] as String,
      frequency: json['frequency'] as String?,
      checklistLastModified: json['checklistLastModified'] as String?,
      answers: (json['answers'] as List<dynamic>? ?? const [])
          .map((e) => OutboxAnswer.fromJson(e as Map<String, dynamic>))
          .toList(),
      photos: (json['photos'] as List<dynamic>? ?? const [])
          .map((e) => OutboxPhoto.fromJson(e as Map<String, dynamic>))
          .toList(),
      registerItems: (json['registerItems'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RegisterItem.fromJson)
          .toList(),
      status: OutboxStatus.fromJson(json['status'] as String?),
      attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      lastAttemptAt: (json['lastAttemptAt'] as num?)?.toInt(),
      lastError: json['lastError'] as String?,
    );
  }
}

/// Generate a v4-format UUID using a cryptographically secure RNG.
///
/// Avoids adding the `uuid` package (not in pubspec). Format per RFC 4122 §4.4.
String generateSubmissionId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).toList();
  return '${h[0]}${h[1]}${h[2]}${h[3]}-${h[4]}${h[5]}-${h[6]}${h[7]}-'
      '${h[8]}${h[9]}-${h[10]}${h[11]}${h[12]}${h[13]}${h[14]}${h[15]}';
}
