import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../models/question.dart';
import '../providers/checklist_provider.dart';
import '../providers/inspection_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../utils/error_utils.dart';
import '../widgets/common/widgets.dart';

class InspectionScreen extends ConsumerStatefulWidget {
  final String assetId;
  final String assetName;

  const InspectionScreen({
    super.key,
    required this.assetId,
    required this.assetName,
  });

  @override
  ConsumerState<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends ConsumerState<InspectionScreen> {
  final _imagePicker = ImagePicker();
  late List<TextEditingController> _controllers;
  bool _controllersInitialized = false;

  @override
  void dispose() {
    if (_controllersInitialized) {
      for (final c in _controllers) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _initControllers(int count) {
    if (_controllersInitialized) return;
    _controllers = List.generate(count, (_) => TextEditingController());
    _controllersInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(checklistStreamProvider(widget.assetId));
    final tokens = context.tokens;
    final colors = context.colors;

    return questionsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(widget.assetName)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(widget.assetName)),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: tokens.iconLg, color: colors.error),
                SizedBox(height: tokens.spacingLg),
                Text(getErrorMessage(error),
                    textAlign: TextAlign.center),
                SizedBox(height: tokens.spacingXl),
                AppButton(
                  text: 'Retry',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.outline,
                  fullWidth: false,
                  onPressed: () =>
                      ref.invalidate(checklistStreamProvider(widget.assetId)),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (questions) {
        _initControllers(questions.length);
        return _InspectionForm(
          assetId: widget.assetId,
          assetName: widget.assetName,
          questions: questions,
          controllers: _controllers,
          imagePicker: _imagePicker,
        );
      },
    );
  }
}

class _InspectionForm extends ConsumerWidget {
  final String assetId;
  final String assetName;
  final List<Question> questions;
  final List<TextEditingController> controllers;
  final ImagePicker imagePicker;

  const _InspectionForm({
    required this.assetId,
    required this.assetName,
    required this.questions,
    required this.controllers,
    required this.imagePicker,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (assetId: assetId, questions: questions);
    final inspectionState = ref.watch(inspectionNotifierProvider(params));
    final notifier = ref.read(inspectionNotifierProvider(params).notifier);
    final tokens = context.tokens;
    final colors = context.colors;

    // Handle completion
    ref.listen(inspectionNotifierProvider(params), (prev, next) {
      if (next.isComplete && !(prev?.isComplete ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inspection submitted successfully')),
        );
        context.pop();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(assetName),
        actions: const [OfflineIndicator()],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(tokens.spacingLg),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final answer = inspectionState.answers[index];
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Question number and text
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: colors.primary,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: colors.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.spacingMd),
                          Expanded(
                            child: Text(
                              answer.question.questionText,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: tokens.spacingMd),

                      // Answer text field
                      AppTextField(
                        controller: controllers[index],
                        hint: 'Enter your answer...',
                        maxLines: 3,
                        onChanged: (text) => notifier.updateAnswer(index, text),
                      ),

                      SizedBox(height: tokens.spacingMd),

                      // Photo thumbnails
                      if (answer.photos.isNotEmpty) ...[
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: answer.photos.length,
                            itemBuilder: (context, photoIndex) {
                              return Padding(
                                padding: EdgeInsets.only(
                                    right: tokens.spacingSm),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          tokens.radiusSm),
                                      child: Image.file(
                                        answer.photos[photoIndex],
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 2,
                                      right: 2,
                                      child: GestureDetector(
                                        onTap: () => notifier.removePhoto(
                                            index, photoIndex),
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          padding: const EdgeInsets.all(4),
                                          child: const Icon(Icons.close,
                                              size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(height: tokens.spacingSm),
                      ],

                      // Add photo button
                      OutlinedButton.icon(
                        onPressed: inspectionState.isSubmitting
                            ? null
                            : () => _showPhotoOptions(context, notifier, index),
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('Add Photo'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Submit bar
          Container(
            padding: EdgeInsets.all(tokens.spacingLg),
            decoration: BoxDecoration(
              color: colors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (inspectionState.submitError != null) ...[
                    Text(
                      getErrorMessage(Exception(inspectionState.submitError)),
                      style: TextStyle(color: colors.error),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: tokens.spacingSm),
                  ],
                  AppButton(
                    text: 'Submit Inspection',
                    icon: Icons.check,
                    isLoading: inspectionState.isSubmitting,
                    onPressed:
                        inspectionState.isSubmitting ? null : notifier.submit,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoOptions(
      BuildContext context, InspectionNotifier notifier, int questionIndex) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera, notifier, questionIndex);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery, notifier, questionIndex);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto(
      ImageSource source, InspectionNotifier notifier, int questionIndex) async {
    final picked = await imagePicker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked != null) {
      notifier.addPhoto(questionIndex, File(picked.path));
    }
  }
}
