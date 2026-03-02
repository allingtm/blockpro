import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/question.dart';
import '../repositories/api_repository.dart';

/// State for a single question's answer during an in-progress inspection.
class QuestionAnswer {
  final Question question;
  final String answerText;
  final List<File> photos;

  QuestionAnswer({
    required this.question,
    this.answerText = '',
    this.photos = const [],
  });

  QuestionAnswer copyWith({
    String? answerText,
    List<File>? photos,
  }) {
    return QuestionAnswer(
      question: question,
      answerText: answerText ?? this.answerText,
      photos: photos ?? this.photos,
    );
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
  InspectionNotifier(this._apiRepository, String assetId, List<Question> questions)
      : super(InspectionState(
          assetId: assetId,
          answers: questions
              .map((q) => QuestionAnswer(question: q))
              .toList(),
        ));

  final ApiRepository _apiRepository;

  void updateAnswer(int index, String text) {
    final updated = List<QuestionAnswer>.from(state.answers);
    updated[index] = updated[index].copyWith(answerText: text);
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
              'upload-image',
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
        'answer_text': a.answerText,
      }).toList();

      final body = {
        'asset_id': state.assetId,
        'answers': answersPayload,
        if (uploadedPhotoIds.isNotEmpty) 'photo_ids': uploadedPhotoIds,
      };
      debugPrint('Body: ${jsonEncode(body)}');

      final result = await _apiRepository.authenticatedPost(
        'completed-inspection',
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
/// Create with (assetId, questions) tuple.
final inspectionNotifierProvider = StateNotifierProvider.autoDispose
    .family<InspectionNotifier, InspectionState, ({String assetId, List<Question> questions})>(
  (ref, params) {
    final apiRepository = ref.watch(apiRepositoryProvider);
    return InspectionNotifier(apiRepository, params.assetId, params.questions);
  },
);
