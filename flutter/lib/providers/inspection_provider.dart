import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/assets_dao.dart';
import '../database/daos/drafts_dao.dart';
import '../database/database.dart';
import '../models/new_remedial.dart';
import '../models/outbox_entry.dart';
import '../models/question.dart';
import '../services/outbox_drainer.dart';
import '../utils/completion_photo_store.dart';
import '../utils/draft_photo_store.dart';
import '../utils/frequency.dart';
import '../utils/outbox_store.dart';
import 'auth_provider.dart';
import 'connectivity_provider.dart';
import 'database_provider.dart';
import 'outbox_drain_provider.dart';
import 'outbox_provider.dart';

/// State for a single question's answer during an in-progress inspection.
class QuestionAnswer {
  final Question question;
  final String? chapterName;
  final String? selectedAnswer;
  final List<File> photos;

  /// Remedial the inspector is raising against this question (at most one).
  /// Only meaningful while the answer is negative; cleared otherwise.
  final NewRemedial? remedial;

  QuestionAnswer({
    required this.question,
    this.chapterName,
    this.selectedAnswer,
    this.photos = const [],
    this.remedial,
  });

  QuestionAnswer copyWith({
    String? selectedAnswer,
    bool clearAnswer = false,
    List<File>? photos,
    NewRemedial? remedial,
    bool clearRemedial = false,
  }) {
    return QuestionAnswer(
      question: question,
      chapterName: chapterName,
      selectedAnswer: clearAnswer ? null : (selectedAnswer ?? this.selectedAnswer),
      photos: photos ?? this.photos,
      remedial: clearRemedial ? null : (remedial ?? this.remedial),
    );
  }

  /// Whether the currently selected answer is a negative one (No /
  /// Unsatisfactory) — drives the inline "Add a remedial" section.
  bool get isNegative =>
      selectedAnswer != null &&
      (question.answerOption?.negativeLabels.contains(selectedAnswer) ??
          false);

  /// The remedial to persist/submit — null when none or title is blank.
  NewRemedial? get effectiveRemedial =>
      (remedial == null || remedial!.isBlank) ? null : remedial;

  /// Whether a photo is currently required based on the question's rules
  /// and the currently selected answer.
  bool get isPhotoRequired {
    final req = question.photoRequirement;
    if (req == null) return false;
    return req.isPhotoRequired(question.answerOption, selectedAnswer);
  }

  /// Whether the photo section should be visible.
  bool get showPhotoSection {
    final req = question.photoRequirement;
    if (req == null) return true; // backwards compat: always show if no rule
    return req.isPhotoRequired(question.answerOption, selectedAnswer);
  }

  /// Whether this answer is valid for submission.
  bool get isValid {
    // If the question has answer options, an answer must be selected
    if (question.answerOption != null && selectedAnswer == null) return false;
    // If a photo is required and none are provided, invalid
    if (isPhotoRequired && photos.isEmpty) return false;
    return true;
  }
}

/// Full state for an in-progress inspection.
class InspectionState {
  final String assetId;
  final List<QuestionAnswer> answers;
  final bool isSubmitting;
  final String? submitError;
  final bool isComplete;

  /// When [isComplete], whether the completion was queued offline (true) rather
  /// than sent right away (false). Drives the "saved — will submit when online"
  /// vs "submitted successfully" messaging.
  final bool isQueued;

  InspectionState({
    required this.assetId,
    this.answers = const [],
    this.isSubmitting = false,
    this.submitError,
    this.isComplete = false,
    this.isQueued = false,
  });

  InspectionState copyWith({
    List<QuestionAnswer>? answers,
    bool? isSubmitting,
    String? submitError,
    bool? isComplete,
    bool? isQueued,
  }) {
    return InspectionState(
      assetId: assetId,
      answers: answers ?? this.answers,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError: submitError,
      isComplete: isComplete ?? this.isComplete,
      isQueued: isQueued ?? this.isQueued,
    );
  }
}

class InspectionNotifier extends StateNotifier<InspectionState> {
  InspectionNotifier(
    this._draftsDao,
    this._assetsDao,
    this._photoStore,
    this._completionPhotoStore,
    this._outboxStore,
    this._drainer,
    this._onOutboxChanged,
    this._uid,
    this._isOffline,
    String assetId,
    this._frequency,
    List<QuestionAnswer> answers,
  )   : _initial = answers
            .map((a) => (
                  answer: a.selectedAnswer,
                  photoCount: a.photos.length,
                  remedialJson: _encodeRemedial(a),
                ))
            .toList(growable: false),
        super(InspectionState(assetId: assetId, answers: answers));

  /// Canonical encoding of an answer's effective remedial for change
  /// detection — null when none (or blank-titled, which never persists).
  static String? _encodeRemedial(QuestionAnswer a) {
    final r = a.effectiveRemedial;
    return r == null ? null : jsonEncode(r.toJson());
  }

  final DraftsDao _draftsDao;
  final AssetsDao _assetsDao;
  final DraftPhotoStore _photoStore;
  final CompletionPhotoStore _completionPhotoStore;
  final OutboxStore _outboxStore;
  final OutboxDrainer _drainer;
  final void Function() _onOutboxChanged;
  final String? _uid;
  final bool Function() _isOffline;
  final String? _frequency;

  /// Snapshot of the answers/photos/remedials as first loaded (including any
  /// restored draft), used to detect whether the user has made unsaved changes.
  final List<({String? answer, int photoCount, String? remedialJson})> _initial;

  /// Whether the current answers differ from what was first loaded.
  /// Drives the "save draft?" prompt when leaving the screen.
  bool get isDirty {
    final current = state.answers;
    if (current.length != _initial.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i].selectedAnswer != _initial[i].answer) return true;
      if (current[i].photos.length != _initial[i].photoCount) return true;
      if (_encodeRemedial(current[i]) != _initial[i].remedialJson) return true;
    }
    return false;
  }

  void updateAnswer(int index, String? answer) {
    final updated = List<QuestionAnswer>.from(state.answers);
    final current = updated[index];
    // Check if switching away from a negative answer
    final wasPhotoRequired = current.isPhotoRequired;
    updated[index] = current.copyWith(selectedAnswer: answer);
    final isNowPhotoRequired = updated[index].isPhotoRequired;
    // Clear photos when photo is no longer required
    if (wasPhotoRequired && !isNowPhotoRequired) {
      updated[index] = updated[index].copyWith(photos: []);
    }
    // Discard any in-progress remedial when the answer is no longer negative
    // (same policy as photo-clearing above).
    if (!updated[index].isNegative) {
      updated[index] = updated[index].copyWith(clearRemedial: true);
    }
    state = state.copyWith(answers: updated);
  }

  void clearAnswer(int index) {
    final updated = List<QuestionAnswer>.from(state.answers);
    updated[index] = updated[index]
        .copyWith(clearAnswer: true, photos: [], clearRemedial: true);
    state = state.copyWith(answers: updated);
  }

  /// Replace the remedial being raised against the question at [index].
  void updateRemedial(int index, NewRemedial remedial) {
    final updated = List<QuestionAnswer>.from(state.answers);
    updated[index] = updated[index].copyWith(remedial: remedial);
    state = state.copyWith(answers: updated);
  }

  void addPhoto(int index, File photo) {
    final updated = List<QuestionAnswer>.from(state.answers);
    updated[index] = updated[index].copyWith(
      photos: [...updated[index].photos, photo],
    );
    state = state.copyWith(answers: updated);
  }

  void removePhoto(int questionIndex, int photoIndex) {
    final updated = List<QuestionAnswer>.from(state.answers);
    final photos = List<File>.from(updated[questionIndex].photos);
    photos.removeAt(photoIndex);
    updated[questionIndex] = updated[questionIndex].copyWith(photos: photos);
    state = state.copyWith(answers: updated);
  }

  /// Persist the current answers + photos as a local draft for this asset.
  ///
  /// Photos are copied to durable storage so their paths survive an app
  /// restart. Only questions that have an answer and/or photos are stored.
  Future<void> saveDraft() async {
    final rows = <DraftAnswersTableCompanion>[];
    for (final answer in state.answers) {
      final hasAnswer = (answer.selectedAnswer ?? '').isNotEmpty;
      if (!hasAnswer && answer.photos.isEmpty) continue;

      final paths = <String>[];
      for (final photo in answer.photos) {
        paths.add(await _photoStore.persistPhoto(photo, state.assetId));
      }

      rows.add(DraftAnswersTableCompanion.insert(
        assetId: state.assetId,
        questionId: answer.question.id,
        answerText: Value(answer.selectedAnswer),
        photoPaths: Value(paths.isEmpty ? null : paths.join('\n')),
        remedialJson: Value(_encodeRemedial(answer)),
      ));
    }
    await _draftsDao.saveDraft(state.assetId, rows);
  }

  /// Complete the inspection.
  ///
  /// Enqueue-first: the full completion (answers + durable photos) is captured
  /// into the offline outbox BEFORE any network call, the asset is optimistically
  /// marked completed, the in-progress draft is dropped, and the drainer is fired
  /// (not awaited). Online, the drain sends it within ~instant; offline, it stays
  /// queued and is sent automatically when connectivity returns. Either way the
  /// user's work is durable the moment they tap Complete.
  Future<void> submit() async {
    // Validate all answers.
    final invalidIndex = state.answers.indexWhere((a) => !a.isValid);
    if (invalidIndex != -1) {
      final answer = state.answers[invalidIndex];
      final reason = answer.question.answerOption != null &&
              answer.selectedAnswer == null
          ? 'Please answer question ${invalidIndex + 1}'
          : 'Photo required for question ${invalidIndex + 1}';
      state = state.copyWith(submitError: reason);
      return;
    }

    // Don't race an in-flight drain of a prior queued completion for this asset.
    final existing = await _outboxStore.readAll();
    final forAsset =
        existing.where((e) => e.assetId == state.assetId).toList();
    if (forAsset.any((e) => e.status == OutboxStatus.sending)) {
      state = state.copyWith(
        submitError:
            'This inspection is being submitted. Please wait a moment.',
      );
      return;
    }

    state = state.copyWith(isSubmitting: true, submitError: null);

    try {
      final submissionId = generateSubmissionId();

      // Persist every photo to durable, submission-scoped storage so the queued
      // completion survives an app restart / temp-cache purge.
      final photos = <OutboxPhoto>[];
      var photoIndex = 0;
      for (final answer in state.answers) {
        for (final photo in answer.photos) {
          final durablePath = await _completionPhotoStore.persistPhoto(
            photo,
            submissionId,
            index: photoIndex,
          );
          photos.add(OutboxPhoto(
            localPath: durablePath,
            questionId: answer.question.id,
          ));
          photoIndex++;
        }
      }

      // Freeze the answer payload exactly as the backend expects (`answer` +
      // `question` text), tagged with questionId for re-open re-mapping.
      final answers = state.answers
          .map((a) => OutboxAnswer(
                question: a.question.questionText,
                answer: a.selectedAnswer ?? '',
                questionId: a.question.id,
                remedial: a.effectiveRemedial,
              ))
          .toList();

      final checklistLastModified =
          await _assetsDao.getChecklistLastModifiedFor(state.assetId);

      final now = DateTime.now();
      final entry = OutboxEntry(
        submissionId: submissionId,
        uid: _uid,
        assetId: state.assetId,
        frequency: _frequency,
        checklistLastModified: checklistLastModified?.toIso8601String(),
        answers: answers,
        photos: photos,
        status: OutboxStatus.pending,
        createdAt: now.millisecondsSinceEpoch,
      );

      // Supersede any prior (non-sending) queued completion for this asset so
      // there's at most one — the amended answers fully replace the old ones.
      for (final old in forAsset) {
        await _outboxStore.remove(old.submissionId);
      }
      await _outboxStore.enqueue(entry);
      _onOutboxChanged();

      // Optimistic local completion + drop the now-redundant draft (the payload
      // lives durably in the outbox).
      await _assetsDao.markCompleted(
        state.assetId,
        lastCompleted: now,
        dueDate: nextDueDate(_frequency, from: now),
      );
      await _draftsDao.deleteDraft(state.assetId);
      await _photoStore.deleteAssetPhotos(state.assetId);

      final queued = _isOffline();
      state = state.copyWith(
        isSubmitting: false,
        isComplete: true,
        isQueued: queued,
      );

      // Fire-and-forget: online sends immediately; offline leaves it queued.
      unawaited(_drainer.drain());
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        submitError: error.toString(),
      );
    }
  }
}

/// Provider for an in-progress inspection.
/// Create with (assetId, frequency, answers) tuple — callers flatten
/// chapters/questions into a list of [QuestionAnswer] so chapter context is
/// preserved; [frequency] drives the optimistic due-date update on submit.
final inspectionNotifierProvider = StateNotifierProvider.autoDispose.family<
    InspectionNotifier,
    InspectionState,
    ({String assetId, String? frequency, List<QuestionAnswer> answers})>(
  (ref, params) {
    final db = ref.watch(appDatabaseProvider);
    final outboxStore = ref.watch(outboxStoreProvider);
    final completionPhotoStore = ref.watch(completionPhotoStoreProvider);
    final drainer = ref.watch(outboxDrainerProvider);
    final authRepo = ref.watch(authRepositoryProvider);
    return InspectionNotifier(
      db.draftsDao,
      db.assetsDao,
      const DraftPhotoStore(),
      completionPhotoStore,
      outboxStore,
      drainer,
      () => ref.read(outboxEntriesProvider.notifier).refresh(),
      authRepo.uid,
      () => ref.read(isOfflineProvider).valueOrNull ?? false,
      params.assetId,
      params.frequency,
      params.answers,
    );
  },
);
