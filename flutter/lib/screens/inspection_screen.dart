import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../models/asset.dart';
import '../models/question.dart';
import '../providers/building_badges_provider.dart';
import '../providers/buildings_provider.dart';
import '../providers/checklist_provider.dart';
import '../providers/drafts_provider.dart';
import '../providers/inspection_provider.dart';
import '../theme/app_palettes.dart';
import '../theme/app_theme_tokens.dart';
import '../utils/asset_status.dart';
import '../utils/date_format.dart';
import '../utils/error_utils.dart';
import '../widgets/common/widgets.dart';

/// User's choice when backing out of an inspection with unsaved changes.
enum _BackAction { save, discard, cancel }

class InspectionScreen extends ConsumerStatefulWidget {
  final Asset asset;

  const InspectionScreen({super.key, required this.asset});

  @override
  ConsumerState<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends ConsumerState<InspectionScreen> {
  final _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final chaptersAsync =
        ref.watch(checklistChaptersStreamProvider(widget.asset.id));
    final draftAsync = ref.watch(draftAnswersProvider(widget.asset.id));
    final buildings = ref.watch(buildingsNotifierProvider).items;
    final building = buildings
        .where((b) => b.id == widget.asset.buildingId)
        .firstOrNull;
    final badges = ref.watch(buildingBadgesProvider).valueOrNull ?? const {};
    final badge = badges[widget.asset.buildingId];

    return Scaffold(
      appBar: BlockProAppBar(
        title: building?.name ?? 'Inspection',
        badgeCount: badge?.red,
      ),
      body: chaptersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorBody(
          message: getErrorMessage(error),
          onRetry: () => ref.invalidate(
              checklistChaptersStreamProvider(widget.asset.id)),
        ),
        data: (chapters) {
          // Wait for the draft load before building the form so answers and
          // photos are pre-filled in one pass (no flicker / late rebuild).
          final draft = draftAsync.valueOrNull;
          if (draftAsync.isLoading && draft == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final answers = <QuestionAnswer>[];
          for (final chapter in chapters) {
            for (final q in chapter.questions) {
              final saved = draft?[q.id];
              answers.add(QuestionAnswer(
                question: q,
                chapterName: chapter.name,
                selectedAnswer:
                    (saved?.answerText?.isEmpty ?? true) ? null : saved!.answerText,
                photos: saved == null
                    ? const []
                    : saved.photoPaths.map((p) => File(p)).toList(),
              ));
            }
          }
          final restored = (draft?.isNotEmpty ?? false);
          return _InspectionForm(
            asset: widget.asset,
            answers: answers,
            imagePicker: _imagePicker,
            draftRestored: restored,
          );
        },
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            AppButton(
              text: 'Retry',
              icon: Icons.refresh,
              variant: AppButtonVariant.outline,
              fullWidth: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectionForm extends ConsumerStatefulWidget {
  final Asset asset;
  final List<QuestionAnswer> answers;
  final ImagePicker imagePicker;
  final bool draftRestored;

  const _InspectionForm({
    required this.asset,
    required this.answers,
    required this.imagePicker,
    this.draftRestored = false,
  });

  @override
  ConsumerState<_InspectionForm> createState() => _InspectionFormState();
}

class _InspectionFormState extends ConsumerState<_InspectionForm> {
  /// Question indices the user is currently editing (manually expanded).
  /// All other indices auto-expand when unanswered and collapse when answered.
  final Set<int> _explicitlyExpanded = {};
  VoidCallback? _dismissLoader;

  @override
  void initState() {
    super.initState();
    if (widget.draftRestored) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft restored')),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = (
      assetId: widget.asset.id,
      frequency: widget.asset.frequency,
      answers: widget.answers,
    );
    final inspectionState = ref.watch(inspectionNotifierProvider(params));
    final notifier = ref.read(inspectionNotifierProvider(params).notifier);

    ref.listen(inspectionNotifierProvider(params), (prev, next) {
      // Show / hide loading dialog around submit.
      if (next.isSubmitting && !(prev?.isSubmitting ?? false)) {
        _dismissLoader = showLoadingDialog(context);
      } else if (!next.isSubmitting && (prev?.isSubmitting ?? false)) {
        _dismissLoader?.call();
        _dismissLoader = null;
      }
      // Completion → snack + pop.
      if (next.isComplete && !(prev?.isComplete ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inspection submitted successfully')),
        );
        context.pop();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _handleBack(notifier);
        if (shouldPop && context.mounted) context.pop();
      },
      child: Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: inspectionState.answers.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _HeaderCard(asset: widget.asset);
              }
              final qIndex = index - 1;
              final answer = inspectionState.answers[qIndex];
              final answered = _isAnswered(answer);
              final expanded =
                  !answered || _explicitlyExpanded.contains(qIndex);
              return _QuestionCard(
                index: qIndex,
                answer: answer,
                expanded: expanded,
                disabled: inspectionState.isSubmitting,
                onEdit: () =>
                    setState(() => _explicitlyExpanded.add(qIndex)),
                onChange: (value) => notifier.updateAnswer(qIndex, value),
                onSave: () =>
                    setState(() => _explicitlyExpanded.remove(qIndex)),
                onAddPhoto: () => _showPhotoOptions(notifier, qIndex),
                onRemovePhoto: (i) => notifier.removePhoto(qIndex, i),
              );
            },
          ),
        ),
        _SubmitBar(
          submitting: inspectionState.isSubmitting,
          error: inspectionState.submitError,
          onSubmit: () => _handleComplete(inspectionState, notifier),
        ),
      ],
      ),
    );
  }

  static bool _isAnswered(QuestionAnswer a) {
    if (a.question.answerOption != null) return a.selectedAnswer != null;
    return (a.selectedAnswer ?? '').trim().isNotEmpty;
  }

  Future<void> _handleComplete(
      InspectionState state, InspectionNotifier notifier) async {
    final allValid = state.answers.every((a) => a.isValid);
    if (allValid) {
      await notifier.submit();
      return;
    }

    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Inspection not complete'),
        content: const Text(
          'Some questions are unanswered or missing required photos. '
          'Your answers and photos will be saved as a draft on this device '
          'so you can finish later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep filling in'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save draft and exit'),
          ),
        ],
      ),
    );
    if (exit == true) {
      await _saveDraftAndInvalidate(notifier);
      if (mounted) context.pop();
    }
  }

  /// Back-navigation guard. Returns whether the screen should pop.
  ///
  /// If nothing has changed, pops immediately. Otherwise prompts the user to
  /// save a draft, discard, or stay. Returns false (stay) on dismiss/cancel.
  Future<bool> _handleBack(InspectionNotifier notifier) async {
    if (!notifier.isDirty) return true;

    final action = await showDialog<_BackAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save your progress?'),
        content: const Text(
          'You have unsaved changes. Save them as a draft on this device so '
          'you can finish this inspection later?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _BackAction.cancel),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _BackAction.discard),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _BackAction.save),
            child: const Text('Save draft'),
          ),
        ],
      ),
    );

    switch (action) {
      case _BackAction.save:
        await _saveDraftAndInvalidate(notifier);
        return true;
      case _BackAction.discard:
        return true;
      case _BackAction.cancel:
      case null:
        return false;
    }
  }

  /// Persist the current answers as a draft and refresh the loader.
  ///
  /// The draft loader is a one-shot FutureProvider that cached an empty map
  /// when this asset was first opened (before the draft existed). Invalidating
  /// it ensures re-entering the asset re-queries the DB and restores what we
  /// just saved.
  Future<void> _saveDraftAndInvalidate(InspectionNotifier notifier) async {
    await notifier.saveDraft();
    ref.invalidate(draftAnswersProvider(widget.asset.id));
  }

  void _showPhotoOptions(InspectionNotifier notifier, int questionIndex) {
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

  Future<void> _pickPhoto(ImageSource source, InspectionNotifier notifier,
      int questionIndex) async {
    final picked = await widget.imagePicker.pickImage(
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final stripe = colourForStatus(assetStatusFor(asset));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        StripedCard(
          stripeColor: stripe,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                asset.displayName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: tokens.textStrong,
                ),
              ),
              const SizedBox(height: 12),
              if (asset.lastCompleted != null)
                _MetaLine(
                  label: 'Last completed',
                  value: formatOrdinalDate(asset.lastCompleted!),
                ),
              if (asset.frequency != null) ...[
                const SizedBox(height: 4),
                _MetaLine(label: 'Frequency', value: asset.frequency!),
              ],
              if (asset.dueDate != null) ...[
                const SizedBox(height: 4),
                _MetaLine(
                  label: 'Next due by',
                  value: formatOrdinalDate(asset.dueDate!),
                ),
              ],
              const SizedBox(height: 16),
              Divider(height: 1, color: tokens.hairline),
              const SizedBox(height: 14),
              Text(
                'Photo evidence (optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tokens.textStrong,
                ),
              ),
              const SizedBox(height: 10),
              _PhotoPlaceholder(onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Photo evidence coming soon')),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: tokens.fieldFill,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera_outlined,
                size: 32, color: tokens.textFaint),
            const SizedBox(height: 6),
            Text(
              '+ Click to add',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          color: tokens.textStrong,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.answer,
    required this.expanded,
    required this.disabled,
    required this.onEdit,
    required this.onChange,
    required this.onSave,
    required this.onAddPhoto,
    required this.onRemovePhoto,
  });

  final int index;
  final QuestionAnswer answer;
  final bool expanded;
  final bool disabled;
  final VoidCallback onEdit;
  final ValueChanged<String?> onChange;
  final VoidCallback onSave;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;

  bool get _answered {
    if (answer.question.answerOption != null) {
      return answer.selectedAnswer != null;
    }
    return (answer.selectedAnswer ?? '').trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final stripe = expanded
        ? kStatusAmber
        : (_answered ? kStatusGreen : kStatusRed);

    return StripedCard(
      stripeColor: stripe,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: expanded ? _buildExpanded(context) : _buildCollapsed(context),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: kStatusGreen, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${index + 1}. ${answer.question.questionText}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.textStrong,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Answer: ${answer.selectedAnswer ?? ''}',
                style: TextStyle(
                  fontSize: 13,
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.edit_outlined, color: tokens.textFaint),
          onPressed: disabled ? null : onEdit,
          tooltip: 'Edit answer',
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${index + 1}. ${answer.question.questionText}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: tokens.textStrong,
          ),
        ),
        if (answer.question.description != null) ...[
          const SizedBox(height: 6),
          Text(
            answer.question.description!,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: tokens.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (answer.question.answerOption != null)
          _OptionsField(
            answerOption: answer.question.answerOption!,
            selected: answer.selectedAnswer,
            enabled: !disabled,
            onChanged: onChange,
          )
        else
          _TextField(
            initial: answer.selectedAnswer,
            enabled: !disabled,
            onChanged: onChange,
          ),
        if (answer.showPhotoSection) ...[
          const SizedBox(height: 12),
          _PhotoSection(
            answer: answer,
            disabled: disabled,
            onAdd: onAddPhoto,
            onRemove: onRemovePhoto,
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kActionBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            onPressed: disabled || !_answered ? null : onSave,
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

class _OptionsField extends StatelessWidget {
  const _OptionsField({
    required this.answerOption,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final AnswerOption answerOption;
  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      hint: Text(
        'Please select...',
        style: TextStyle(color: tokens.textMuted),
      ),
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: tokens.fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: tokens.fieldBorder),
        ),
      ),
      items: answerOption.labels
          .map((label) =>
              DropdownMenuItem(value: label, child: Text(label)))
          .toList(),
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _TextField extends StatefulWidget {
  const _TextField({
    required this.initial,
    required this.enabled,
    required this.onChanged,
  });

  final String? initial;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
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
      onChanged: widget.enabled ? widget.onChanged : null,
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.answer,
    required this.disabled,
    required this.onAdd,
    required this.onRemove,
  });

  final QuestionAnswer answer;
  final bool disabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (answer.isPhotoRequired && answer.photos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.camera_alt, size: 16, color: colors.error),
                const SizedBox(width: 4),
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
        if (answer.photos.isNotEmpty) ...[
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: answer.photos.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(answer.photos[i],
                          width: 80, height: 80, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: disabled ? null : () => onRemove(i),
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
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: disabled ? null : onAdd,
          icon: const Icon(Icons.camera_alt_outlined, size: 18),
          label: const Text('Add Photo'),
        ),
      ],
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.submitting,
    required this.error,
    required this.onSubmit,
  });

  final bool submitting;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: context.tokens.cardSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                Text(error!,
                    style: TextStyle(color: colors.error),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kActionBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: submitting ? null : onSubmit,
                  child: const Text('Complete'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
