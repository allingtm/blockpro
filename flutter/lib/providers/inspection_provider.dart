import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/question.dart';
import '../repositories/api_repository.dart';

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
  InspectionNotifier(this._apiRepository, String assetId, List<QuestionAnswer> answers)
      : super(InspectionState(assetId: assetId, answers: answers));

  final ApiRepository _apiRepository;

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
              'app_upload-image',
              body: {
                'base64': base64Image,
                'asset_id': state.assetId,
                'filename': photo.path.split('/').last,
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
      final answersPayload = state.answers.map((a) => {
        'question_text': a.question.questionText,
        'answer_text': a.selectedAnswer ?? '',
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
/// Create with (assetId, answers) tuple — callers flatten chapters/questions
/// into a list of [QuestionAnswer] so chapter context can be preserved.
final inspectionNotifierProvider = StateNotifierProvider.autoDispose
    .family<InspectionNotifier, InspectionState, ({String assetId, List<QuestionAnswer> answers})>(
  (ref, params) {
    final apiRepository = ref.watch(apiRepositoryProvider);
    return InspectionNotifier(apiRepository, params.assetId, params.answers);
  },
);
