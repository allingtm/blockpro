import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/assets_dao.dart';
import '../database/daos/drafts_dao.dart';
import '../database/database.dart';
import '../models/question.dart';
import '../repositories/api_repository.dart';
import '../utils/draft_photo_store.dart';
import '../utils/frequency.dart';
import 'database_provider.dart';

/// State for a single question's answer during an in-progress inspection.
class QuestionAnswer {
  final Question question;
  final String? chapterName;
  final String? selectedAnswer;
  final List<File> photos;

  QuestionAnswer({
    required this.question,
    this.chapterName,
    this.selectedAnswer,
    this.photos = const [],
  });

  QuestionAnswer copyWith({
    String? selectedAnswer,
    bool clearAnswer = false,
    List<File>? photos,
  }) {
    return QuestionAnswer(
      question: question,
      chapterName: chapterName,
      selectedAnswer: clearAnswer ? null : (selectedAnswer ?? this.selectedAnswer),
      photos: photos ?? this.photos,
    );
  }

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

  InspectionState({
    required this.assetId,
    this.answers = const [],
    this.isSubmitting = false,
    this.submitError,
    this.isComplete = false,
  });

  InspectionState copyWith({
    List<QuestionAnswer>? answers,
    bool? isSubmitting,
    String? submitError,
    bool? isComplete,
  }) {
    return InspectionState(
      assetId: assetId,
      answers: answers ?? this.answers,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError: submitError,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

class InspectionNotifier extends StateNotifier<InspectionState> {
  InspectionNotifier(
    this._apiRepository,
    this._draftsDao,
    this._assetsDao,
    this._photoStore,
    String assetId,
    this._frequency,
    List<QuestionAnswer> answers,
  )   : _initial = answers
            .map((a) => (
                  answer: a.selectedAnswer,
                  photoCount: a.photos.length,
                ))
            .toList(growable: false),
        super(InspectionState(assetId: assetId, answers: answers));

  final ApiRepository _apiRepository;
  final DraftsDao _draftsDao;
  final AssetsDao _assetsDao;
  final DraftPhotoStore _photoStore;
  final String? _frequency;

  /// Snapshot of the answers/photos as first loaded (including any restored
  /// draft), used to detect whether the user has made unsaved changes.
  final List<({String? answer, int photoCount})> _initial;

  /// Whether the current answers differ from what was first loaded.
  /// Drives the "save draft?" prompt when leaving the screen.
  bool get isDirty {
    final current = state.answers;
    if (current.length != _initial.length) return true;
    for (var i = 0; i < current.length; i++) {
      if (current[i].selectedAnswer != _initial[i].answer) return true;
      if (current[i].photos.length != _initial[i].photoCount) return true;
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
    state = state.copyWith(answers: updated);
  }

  void clearAnswer(int index) {
    final updated = List<QuestionAnswer>.from(state.answers);
    updated[index] = updated[index].copyWith(clearAnswer: true, photos: []);
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
      ));
    }
    await _draftsDao.saveDraft(state.assetId, rows);
  }

  Future<void> submit() async {
    // Validate all answers
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

    state = state.copyWith(isSubmitting: true, submitError: null);

    try {
      // Upload photos first
      final uploadedPhotoIds = <String>[];
      for (final answer in state.answers) {
        for (final photo in answer.photos) {
          debugPrint('── UPLOAD IMAGE REQUEST ──');
          final bytes = await photo.readAsBytes();
          final base64Image = base64Encode(bytes);

          try {
            final result = await _apiRepository.authenticatedPost(
              'app_upload-image_Adam',
              body: {
                'base64': base64Image,
                'asset_id': state.assetId,
              },
            );
            debugPrint('── UPLOAD IMAGE RESPONSE ──');
            debugPrint('Result: $result');
            final imageId = result['response']?['image_id'] as String?;
            if (imageId != null) uploadedPhotoIds.add(imageId);
          } catch (e) {
            debugPrint('── UPLOAD IMAGE ERROR ──');
            debugPrint('Error: $e');
            // Continue with submission even if photo upload fails
          }
        }
      }

      // Submit completed inspection
      debugPrint('── COMPLETED INSPECTION REQUEST ──');
      // Bubble's app_completed-inspection reads each item's `answer` and
      // `question` sub-fields (Step 3 passes them to app_create-completed-question),
      // so the keys must match exactly.
      final answersPayload = state.answers.map((a) => {
        'answer': a.selectedAnswer ?? '',
        'question': a.question.questionText,
      }).toList();

      final body = {
        'asset_id': state.assetId,
        'answers': answersPayload,
        if (uploadedPhotoIds.isNotEmpty) 'photo_ids': uploadedPhotoIds,
      };
      debugPrint('Body: ${jsonEncode(body)}');

      final result = await _apiRepository.authenticatedPost(
        'app_completed-inspection',
        body: body,
      );
      debugPrint('── COMPLETED INSPECTION RESPONSE ──');
      debugPrint('Result: $result');

      // Inspection submitted — discard any local draft for this asset.
      await _draftsDao.deleteDraft(state.assetId);
      await _photoStore.deleteAssetPhotos(state.assetId);

      // Optimistically mark the asset completed locally so its card turns
      // green right away. dueDate is recomputed from the frequency; if it
      // can't be parsed it's left as-is for the next sync to correct.
      final now = DateTime.now();
      await _assetsDao.markCompleted(
        state.assetId,
        lastCompleted: now,
        dueDate: nextDueDate(_frequency, from: now),
      );

      state = state.copyWith(isSubmitting: false, isComplete: true);
    } catch (error) {
      debugPrint('── COMPLETED INSPECTION ERROR ──');
      debugPrint('Error: $error');
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
    final apiRepository = ref.watch(apiRepositoryProvider);
    return InspectionNotifier(
      apiRepository,
      db.draftsDao,
      db.assetsDao,
      const DraftPhotoStore(),
      params.assetId,
      params.frequency,
      params.answers,
    );
  },
);
