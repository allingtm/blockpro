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

  @override
  Widget build(BuildContext context) {
    final chaptersAsync =
        ref.watch(checklistChaptersStreamProvider(widget.assetId));
    final tokens = context.tokens;
    final colors = context.colors;

    return chaptersAsync.when(
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
                  onPressed: () => ref.invalidate(
                      checklistChaptersStreamProvider(widget.assetId)),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (chapters) {
        // Flatten chapters → questions into QuestionAnswers, carrying chapter
        // name onto each so the UI can group them visually.
        final answers = <QuestionAnswer>[];
        for (final chapter in chapters) {
          for (final q in chapter.questions) {
            answers.add(QuestionAnswer(
                question: q, chapterName: chapter.name));
          }
        }
        return _InspectionForm(
          assetId: widget.assetId,
          assetName: widget.assetName,
          answers: answers,
          imagePicker: _imagePicker,
        );
      },
    );
  }
}

class _InspectionForm extends ConsumerWidget {
  final String assetId;
  final String assetName;
  final List<QuestionAnswer> answers;
  final ImagePicker imagePicker;

  const _InspectionForm({
    required this.assetId,
    required this.assetName,
    required this.answers,
    required this.imagePicker,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = (assetId: assetId, answers: answers);
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
              itemCount: inspectionState.answers.length,
              itemBuilder: (context, index) {
                final answer = inspectionState.answers[index];
                final prevChapter = index > 0
                    ? inspectionState.answers[index - 1].chapterName
                    : null;
                final showChapterHeader = answer.chapterName != null &&
                    answer.chapterName != prevChapter;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showChapterHeader) ...[
                      if (index > 0) SizedBox(height: tokens.spacingLg),
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: tokens.spacingSm,
                            vertical: tokens.spacingSm),
                        child: Text(
                          answer.chapterName!,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    AppCard(
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
                                  style:
                                      Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),

                          // Question description (helper text)
                          if (answer.question.description != null) ...[
                            SizedBox(height: tokens.spacingSm),
                            Padding(
                              padding: EdgeInsets.only(left: 36),
                              child: Text(
                                answer.question.description!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],

                          // Existing remedials (read-only from prior inspections)
                          if (answer.question.existingRemedials.isNotEmpty) ...[
                            SizedBox(height: tokens.spacingSm),
                            _RemedialsList(
                                remedials: answer.question.existingRemedials),
                          ],

                          SizedBox(height: tokens.spacingMd),

                          // Answer section
                          if (answer.question.answerOption != null)
                            _AnswerOptionsWidget(
                              answerOption: answer.question.answerOption!,
                              selectedAnswer: answer.selectedAnswer,
                              enabled: !inspectionState.isSubmitting,
                              onChanged: (value) =>
                                  notifier.updateAnswer(index, value),
                            )
                          else
                            _TextAnswerWidget(
                              initialValue: answer.selectedAnswer,
                              onChanged: (text) =>
                                  notifier.updateAnswer(index, text),
                            ),

                          SizedBox(height: tokens.spacingMd),

                          // Photo section — conditional visibility
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.topCenter,
                            child: answer.showPhotoSection
                                ? _PhotoSection(
                                    answer: answer,
                                    isSubmitting: inspectionState.isSubmitting,
                                    onAddPhoto: () => _showPhotoOptions(
                                        context, notifier, index),
                                    onRemovePhoto: (photoIndex) =>
                                        notifier.removePhoto(
                                            index, photoIndex),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                      inspectionState.submitError!,
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

/// Segmented button widget for structured answer options.
class _AnswerOptionsWidget extends StatelessWidget {
  final AnswerOption answerOption;
  final String? selectedAnswer;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _AnswerOptionsWidget({
    required this.answerOption,
    required this.selectedAnswer,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: answerOption.labels
          .map((label) => ChoiceChip(
                label: Text(label),
                selected: selectedAnswer == label,
                onSelected: enabled
                    ? (isSelected) => onChanged(isSelected ? label : null)
                    : null,
              ))
          .toList(),
    );
  }
}

/// Fallback text input for questions without structured answer options.
class _TextAnswerWidget extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String> onChanged;

  const _TextAnswerWidget({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_TextAnswerWidget> createState() => _TextAnswerWidgetState();
}

class _TextAnswerWidgetState extends State<_TextAnswerWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      hint: 'Enter your answer...',
      maxLines: 3,
      onChanged: widget.onChanged,
    );
  }
}

/// Photo section with conditional "Photo required" indicator.
class _PhotoSection extends StatelessWidget {
  final QuestionAnswer answer;
  final bool isSubmitting;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  const _PhotoSection({
    required this.answer,
    required this.isSubmitting,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo required indicator
        if (answer.isPhotoRequired && answer.photos.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.spacingSm),
            child: Row(
              children: [
                Icon(Icons.camera_alt, size: 16, color: colors.error),
                SizedBox(width: tokens.spacingXs),
                Text(
                  'Photo required',
                  style: TextStyle(
                    color: colors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

        // Photo thumbnails
        if (answer.photos.isNotEmpty) ...[
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: answer.photos.length,
              itemBuilder: (context, photoIndex) {
                return Padding(
                  padding: EdgeInsets.only(right: tokens.spacingSm),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(tokens.radiusSm),
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
                          onTap: () => onRemovePhoto(photoIndex),
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
          onPressed: isSubmitting ? null : onAddPhoto,
          icon: const Icon(Icons.camera_alt_outlined, size: 18),
          label: const Text('Add Photo'),
        ),
      ],
    );
  }
}

/// Read-only display of remedials raised against this question in prior
/// inspections. Helps the inspector see existing issues before re-answering.
class _RemedialsList extends StatelessWidget {
  final List<Remedial> remedials;
  const _RemedialsList({required this.remedials});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    return Container(
      margin: EdgeInsets.only(left: 36),
      padding: EdgeInsets.all(tokens.spacingSm),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 14, color: colors.error),
              SizedBox(width: tokens.spacingXs),
              Text(
                'Existing remedials',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          ...remedials.map((r) => Padding(
                padding: EdgeInsets.only(top: tokens.spacingXs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ',
                            style: Theme.of(context).textTheme.bodySmall),
                        Expanded(
                          child: Text(
                            r.name,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (r.priority != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: r.priority!.toLowerCase() == 'high'
                                  ? colors.error
                                  : colors.onSurfaceVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              r.priority!,
                              style: TextStyle(
                                color: colors.surface,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (r.description != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10, top: 2),
                        child: Text(
                          r.description!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (r.location != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10, top: 2),
                        child: Text(
                          'Location: ${r.location}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
