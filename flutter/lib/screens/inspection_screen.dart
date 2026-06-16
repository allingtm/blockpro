import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../models/asset.dart';
import '../models/new_remedial.dart';
import '../models/outbox_entry.dart';
import '../models/question.dart';
import '../models/register_item.dart';
import '../providers/building_badges_provider.dart';
import '../providers/buildings_provider.dart';
import '../providers/checklist_provider.dart';
import '../providers/drafts_provider.dart';
import '../providers/inspection_provider.dart';
import '../providers/outbox_provider.dart';
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

          // A queued (offline-completed) entry takes precedence over the draft
          // (the draft was deleted at enqueue): re-opening the asset restores
          // the completion's answers/photos so the user can review or amend.
          final queued =
              ref.watch(assetQueuedEntryProvider(widget.asset.id));
          final queuedAnswers = <String, String>{};
          final queuedPhotos = <String, List<String>>{};
          final queuedRemedials = <String, NewRemedial>{};
          final queuedInspectionPhotos = <String>[];
          if (queued != null) {
            for (final a in queued.answers) {
              if (a.questionId != null) {
                queuedAnswers[a.questionId!] = a.answer;
                if (a.remedial != null) {
                  queuedRemedials[a.questionId!] = a.remedial!;
                }
              }
            }
            for (final ph in queued.photos) {
              if (ph.questionId != null) {
                (queuedPhotos[ph.questionId!] ??= []).add(ph.localPath);
              } else {
                // Null questionId == inspection-level (header) photo evidence.
                queuedInspectionPhotos.add(ph.localPath);
              }
            }
          }

          final answers = <QuestionAnswer>[];
          for (final chapter in chapters) {
            for (final q in chapter.questions) {
              String? selected;
              List<File> photos;
              NewRemedial? remedial;
              if (queued != null) {
                final a = queuedAnswers[q.id];
                selected = (a == null || a.isEmpty) ? null : a;
                photos = (queuedPhotos[q.id] ?? const [])
                    .map((p) => File(p))
                    .toList();
                remedial = queuedRemedials[q.id];
              } else {
                final saved = draft?.answers[q.id];
                selected = (saved?.answerText?.isEmpty ?? true)
                    ? null
                    : saved!.answerText;
                photos = saved == null
                    ? const []
                    : saved.photoPaths.map((p) => File(p)).toList();
                remedial = saved?.remedial;
              }
              answers.add(QuestionAnswer(
                question: q,
                chapterName: chapter.name,
                selectedAnswer: selected,
                photos: photos,
                remedial: remedial,
              ));
            }
          }

          // Inspection-level (header) photo evidence + tagged register items —
          // from the queued completion if present, else the saved draft.
          final inspectionPhotos = queued != null
              ? queuedInspectionPhotos.map((p) => File(p)).toList()
              : (draft?.photoPaths ?? const [])
                  .map((p) => File(p))
                  .toList();
          final selectedRegisterItems = queued != null
              ? queued.registerItems
              : (draft?.registerItems ?? const <RegisterItem>[]);

          final restored = queued == null && !(draft?.isEmpty ?? true);
          return _InspectionForm(
            asset: widget.asset,
            answers: answers,
            inspectionPhotos: inspectionPhotos,
            selectedRegisterItems: selectedRegisterItems,
            imagePicker: _imagePicker,
            draftRestored: restored,
            queuedStatus: queued?.status,
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

  /// Inspection-level (header) photo evidence restored from a draft / queued
  /// completion.
  final List<File> inspectionPhotos;

  /// Register items the inspection is tagged with, restored from a draft /
  /// queued completion.
  final List<RegisterItem> selectedRegisterItems;

  final ImagePicker imagePicker;
  final bool draftRestored;

  /// Non-null when this asset has a queued offline completion — drives the
  /// "not yet submitted" banner.
  final OutboxStatus? queuedStatus;

  const _InspectionForm({
    required this.asset,
    required this.answers,
    required this.inspectionPhotos,
    required this.selectedRegisterItems,
    required this.imagePicker,
    this.draftRestored = false,
    this.queuedStatus,
  });

  @override
  ConsumerState<_InspectionForm> createState() => _InspectionFormState();
}

class _InspectionFormState extends ConsumerState<_InspectionForm> {
  /// Question indices the user is currently editing (manually expanded).
  /// All other indices auto-expand when unanswered and collapse when answered.
  final Set<int> _explicitlyExpanded = {};
  VoidCallback? _dismissLoader;

  /// Parsed once — the asset's register items, offered as "related items"
  /// choices on any remedial the inspector raises.
  late final List<RegisterItem> _registerItems = widget.asset.registerItems;

  /// Frozen at first build so the inspection notifier keeps a STABLE identity.
  ///
  /// The provider is a `family` keyed by this record (which includes the answers
  /// list). If we recomputed it on every build, a rebuild triggered mid-submit —
  /// e.g. `submit()` updating the outbox or `markCompleted` nudging the building
  /// badges stream — would mint a brand-new notifier, and the `ref.listen` that
  /// dismisses the loader and pops the screen would rebind to it, stranding the
  /// in-flight submit's completion (the "Please wait" dialog would hang).
  late final ({
    String assetId,
    String? frequency,
    List<QuestionAnswer> answers,
    List<File> inspectionPhotos,
    List<RegisterItem> registerItems,
  }) _params;

  @override
  void initState() {
    super.initState();
    _params = (
      assetId: widget.asset.id,
      frequency: widget.asset.frequency,
      answers: widget.answers,
      inspectionPhotos: widget.inspectionPhotos,
      registerItems: widget.selectedRegisterItems,
    );
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
    final params = _params;
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
      // Completion → snack + pop. Offline completions are queued, not sent, so
      // never claim they were "submitted".
      if (next.isComplete && !(prev?.isComplete ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.isQueued
                ? "Saved — it will be submitted automatically when you're back online"
                : 'Inspection submitted successfully'),
          ),
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
        if (widget.queuedStatus != null)
          _QueuedBanner(status: widget.queuedStatus!),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: inspectionState.answers.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _HeaderCard(
                  asset: widget.asset,
                  photos: inspectionState.inspectionPhotos,
                  registerItems: _registerItems,
                  selectedItems: inspectionState.selectedRegisterItems,
                  disabled: inspectionState.isSubmitting,
                  onAddPhoto: () => _pickInspectionPhoto(notifier),
                  onRemovePhoto: (i) => notifier.removeInspectionPhoto(i),
                  onToggleItem: (item) => notifier.toggleRegisterItem(item),
                );
              }
              final qIndex = index - 1;
              final answer = inspectionState.answers[qIndex];
              final complete = _isComplete(answer);
              final expanded =
                  !complete || _explicitlyExpanded.contains(qIndex);
              return _QuestionCard(
                index: qIndex,
                answer: answer,
                expanded: expanded,
                disabled: inspectionState.isSubmitting,
                registerItems: _registerItems,
                onEdit: () =>
                    setState(() => _explicitlyExpanded.add(qIndex)),
                onChange: (value) {
                  notifier.updateAnswer(qIndex, value);
                  // Keep the card in edit mode (instead of auto-collapsing)
                  // while the new answer still needs follow-up input: a negative
                  // answer (remedial form) or a required photo not yet added.
                  // The Save button collapses it.
                  final q = answer.question;
                  final negative = value != null &&
                      (q.answerOption?.negativeLabels.contains(value) ?? false);
                  final photoStillNeeded = (q.photoRequirement
                              ?.isPhotoRequired(q.answerOption, value) ??
                          false) &&
                      answer.photos.isEmpty;
                  if (negative || photoStillNeeded) {
                    setState(() => _explicitlyExpanded.add(qIndex));
                  }
                },
                onSave: () =>
                    setState(() => _explicitlyExpanded.remove(qIndex)),
                onAddPhoto: () =>
                    _pickPhoto(ImageSource.camera, notifier, qIndex),
                onRemovePhoto: (i) => notifier.removePhoto(qIndex, i),
                onRemedialChanged: (r) => notifier.updateRemedial(qIndex, r),
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

  /// Whether a card is fully done (answer + any required photo + any required
  /// remedial) and so may auto-collapse. Mirrors `_QuestionCard._canSave`, so a
  /// card answered but still missing a required photo/remedial stays expanded
  /// (on live selection and on a restored draft) until the user can Save it.
  static bool _isComplete(QuestionAnswer a) {
    if (!_isAnswered(a)) return false;
    if (a.isPhotoRequired && a.photos.isEmpty) return false;
    if (a.isRemedialRequired && a.effectiveRemedial == null) return false;
    return true;
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
          'Some questions are unanswered, missing a required photo, or '
          'missing a required remedial. Your answers and photos will be saved '
          'as a draft on this device so you can finish later.',
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

  Future<void> _pickPhoto(ImageSource source, InspectionNotifier notifier,
      int questionIndex) async {
    // TEMPORARY: dev machines have no camera, so generate a placeholder image
    // instead of opening the picker. Restore the image_picker call below for
    // device builds.
    //
    // final picked = await widget.imagePicker.pickImage(
    //   source: source,
    //   maxWidth: 1920,
    //   maxHeight: 1920,
    //   imageQuality: 85,
    // );
    // if (picked != null) {
    //   notifier.addPhoto(questionIndex, File(picked.path));
    // }
    final file = await _generateDummyPhoto();
    notifier.addPhoto(questionIndex, file);
  }

  /// Capture an inspection-level (header) photo. Same dev dummy-photo / device
  /// `image_picker` flow as [_pickPhoto], but attached to the inspection rather
  /// than a single question.
  Future<void> _pickInspectionPhoto(InspectionNotifier notifier) async {
    // TEMPORARY: dev machines have no camera — generate a placeholder instead
    // of opening the picker. Restore the image_picker call below for device
    // builds.
    //
    // final picked = await widget.imagePicker.pickImage(
    //   source: ImageSource.camera,
    //   maxWidth: 1920,
    //   maxHeight: 1920,
    //   imageQuality: 85,
    // );
    // if (picked != null) {
    //   notifier.addInspectionPhoto(File(picked.path));
    // }
    final file = await _generateDummyPhoto();
    notifier.addInspectionPhoto(file);
  }

  /// Renders a flat-colour placeholder with a timestamp and writes it to a
  /// temp file, so the photo flow can be exercised without camera hardware.
  Future<File> _generateDummyPhoto() async {
    const width = 640, height = 480;
    final rng = Random();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final background = Color.fromARGB(255, 60 + rng.nextInt(140),
        60 + rng.nextInt(140), 60 + rng.nextInt(140));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = background,
    );
    final label = TextPainter(
      text: TextSpan(
        text: 'Dummy photo\n${DateTime.now()}',
        style: const TextStyle(color: Colors.white, fontSize: 28),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width.toDouble());
    label.paint(
        canvas, Offset((width - label.width) / 2, (height - label.height) / 2));
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/dummy_photo_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file;
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.asset,
    required this.photos,
    required this.registerItems,
    required this.selectedItems,
    required this.disabled,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.onToggleItem,
  });

  final Asset asset;

  /// Inspection-level photo evidence.
  final List<File> photos;

  /// The asset's register items, offered as inspection-level tags.
  final List<RegisterItem> registerItems;

  /// Currently-selected register items.
  final List<RegisterItem> selectedItems;

  final bool disabled;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;
  final ValueChanged<RegisterItem> onToggleItem;

  bool _isSelected(RegisterItem item) =>
      selectedItems.any((s) => s.ref == item.ref);

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
              _PhotoGallery(
                photos: photos,
                disabled: disabled,
                onAdd: onAddPhoto,
                onRemove: onRemovePhoto,
                prominentWhenEmpty: true,
              ),
              if (registerItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Asset register items (optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.textStrong,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final item in registerItems)
                      FilterChip(
                        label: Text(item.displayLabel),
                        selected: _isSelected(item),
                        onSelected:
                            disabled ? null : (_) => onToggleItem(item),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.onTap});
  final VoidCallback? onTap;

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
    required this.registerItems,
    required this.onEdit,
    required this.onChange,
    required this.onSave,
    required this.onAddPhoto,
    required this.onRemovePhoto,
    required this.onRemedialChanged,
  });

  final int index;
  final QuestionAnswer answer;
  final bool expanded;
  final bool disabled;
  final List<RegisterItem> registerItems;
  final VoidCallback onEdit;
  final ValueChanged<String?> onChange;
  final VoidCallback onSave;
  final VoidCallback onAddPhoto;
  final ValueChanged<int> onRemovePhoto;
  final ValueChanged<NewRemedial> onRemedialChanged;

  bool get _answered {
    if (answer.question.answerOption != null) {
      return answer.selectedAnswer != null;
    }
    return (answer.selectedAnswer ?? '').trim().isNotEmpty;
  }

  /// Whether the card may be saved (collapsed). An answer is required; when a
  /// photo is required at least one must be attached; and on the negative path a
  /// mandatory remedial (no prior remedials) must be raised.
  bool get _canSave {
    if (!_answered) return false;
    if (answer.isPhotoRequired && answer.photos.isEmpty) return false;
    if (answer.isRemedialRequired && answer.effectiveRemedial == null) {
      return false;
    }
    return true;
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
              if (answer.question.existingRemedials.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.build_circle_outlined,
                        size: 14, color: kStatusAmber),
                    const SizedBox(width: 4),
                    Text(
                      '${answer.question.existingRemedials.length} existing '
                      'remedial${answer.question.existingRemedials.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
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
        if (answer.question.existingRemedials.isNotEmpty) ...[
          const SizedBox(height: 12),
          _RemedialsSection(remedials: answer.question.existingRemedials),
        ],
        // Auto-expands when the answer turns negative; unmounts (and the
        // notifier clears the state) when it turns positive again.
        if (answer.isNegative) ...[
          const SizedBox(height: 12),
          _AddRemedialSection(
            // Remount when the in-state remedial is cleared externally so the
            // text controllers reset along with it.
            key: ValueKey(answer.question.id),
            value: answer.remedial,
            required: answer.isRemedialRequired,
            registerItems: registerItems,
            enabled: !disabled,
            onChanged: onRemedialChanged,
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
            onPressed: disabled || !_canSave ? null : onSave,
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

/// Inline form to raise a remedial against a question, shown only while the
/// selected answer is negative (No / Unsatisfactory). Optional — leaving the
/// title blank means no remedial is raised. At most one per question.
class _AddRemedialSection extends StatefulWidget {
  const _AddRemedialSection({
    super.key,
    required this.value,
    required this.required,
    required this.registerItems,
    required this.enabled,
    required this.onChanged,
  });

  final NewRemedial? value;

  /// Whether raising a remedial is mandatory (negative answer with no existing
  /// remedials). Drives the "(required)" label and the inline error indicator.
  final bool required;
  final List<RegisterItem> registerItems;
  final bool enabled;
  final ValueChanged<NewRemedial> onChanged;

  @override
  State<_AddRemedialSection> createState() => _AddRemedialSectionState();
}

class _AddRemedialSectionState extends State<_AddRemedialSection> {
  static const _priorities = ['Low', 'High'];

  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _descriptionController;
  late String _priority;
  late List<RegisterItem> _selectedItems;

  @override
  void initState() {
    super.initState();
    final v = widget.value;
    _titleController = TextEditingController(text: v?.title ?? '');
    _locationController = TextEditingController(text: v?.location ?? '');
    _descriptionController = TextEditingController(text: v?.description ?? '');
    _priority = v?.priority ?? 'Low';
    _selectedItems = List.of(v?.registerItems ?? const []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(NewRemedial(
      title: _titleController.text,
      location: _locationController.text,
      description: _descriptionController.text,
      priority: _priority,
      registerItems: List.of(_selectedItems),
    ));
  }

  bool _isSelected(RegisterItem item) =>
      _selectedItems.any((s) => s.ref == item.ref);

  void _toggleItem(RegisterItem item) {
    setState(() {
      if (_isSelected(item)) {
        _selectedItems.removeWhere((s) => s.ref == item.ref);
      } else {
        _selectedItems.add(item);
      }
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final missingRequired = widget.required && (widget.value?.isBlank ?? true);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: kActionBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kActionBlue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build_circle_outlined,
                  size: 16, color: kActionBlue),
              const SizedBox(width: 6),
              Text(
                widget.required
                    ? 'Add a remedial (required)'
                    : 'Add a remedial (optional)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.textStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (missingRequired)
            Row(
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 4),
                Text(
                  'Remedial required',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          else if (!widget.required)
            Text(
              'Leave the title blank to skip.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: tokens.textFaint,
              ),
            ),
          const SizedBox(height: 10),
          AppTextField(
            controller: _titleController,
            label: 'Title',
            hint: 'Enter title',
            onChanged: widget.enabled ? (_) => _emit() : null,
          ),
          const SizedBox(height: 10),
          AppTextField(
            controller: _locationController,
            label: 'Location',
            hint: 'i.e. Electrical cupboard',
            onChanged: widget.enabled ? (_) => _emit() : null,
          ),
          const SizedBox(height: 10),
          AppTextField(
            controller: _descriptionController,
            label: 'Description',
            hint: 'Enter description',
            maxLines: 3,
            onChanged: widget.enabled ? (_) => _emit() : null,
          ),
          const SizedBox(height: 10),
          Text(
            'Priority',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.textStrong,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _priority,
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
            items: _priorities
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: widget.enabled
                ? (value) {
                    if (value == null) return;
                    setState(() => _priority = value);
                    _emit();
                  }
                : null,
          ),
          if (widget.registerItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Related register items (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textStrong,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final item in widget.registerItems)
                  FilterChip(
                    label: Text(item.displayLabel),
                    selected: _isSelected(item),
                    onSelected:
                        widget.enabled ? (_) => _toggleItem(item) : null,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Remedials raised against this question in prior inspections, shown so the
/// inspector has context on known outstanding issues before answering.
class _RemedialsSection extends StatelessWidget {
  const _RemedialsSection({required this.remedials});

  final List<Remedial> remedials;

  static Color _priorityColor(String? priority) =>
      switch (priority?.toLowerCase().trim()) {
        'high' => kStatusRed,
        'medium' => kStatusAmber,
        'low' => kStatusGreen,
        _ => kStatusAmber,
      };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: kStatusAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kStatusAmber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build_circle_outlined,
                  size: 16, color: kStatusAmber),
              const SizedBox(width: 6),
              Text(
                'Existing remedial${remedials.length == 1 ? '' : 's'} '
                '(${remedials.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.textStrong,
                ),
              ),
            ],
          ),
          for (final r in remedials) ...[
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        r.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.textStrong,
                        ),
                      ),
                    ),
                    if (r.priority != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _priorityColor(r.priority)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          r.priority!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _priorityColor(r.priority),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (r.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    r.description!,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.textMuted,
                    ),
                  ),
                ],
                if (r.location != null || r.dueDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (r.location != null) r.location!,
                      if (r.dueDate != null)
                        'due ${formatOrdinalDate(r.dueDate!)}',
                    ].join(' — '),
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: tokens.textFaint,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
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
        _PhotoGallery(
          photos: answer.photos,
          disabled: disabled,
          onAdd: onAdd,
          onRemove: onRemove,
        ),
      ],
    );
  }
}

/// Reusable photo strip: horizontal thumbnails (each with a delete affordance)
/// plus an "add" control. Shared by the per-question photo section and the
/// inspection-level (header) photo evidence.
class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({
    required this.photos,
    required this.disabled,
    required this.onAdd,
    required this.onRemove,
    this.prominentWhenEmpty = false,
  });

  final List<File> photos;
  final bool disabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  /// When true and there are no photos yet, render the large tappable
  /// "+ Click to add" box (header style) instead of the compact button.
  final bool prominentWhenEmpty;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty && prominentWhenEmpty) {
      return _PhotoPlaceholder(onTap: disabled ? null : onAdd);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photos.isNotEmpty) ...[
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(photos[i],
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

/// Banner shown when re-opening an asset that has a queued offline completion,
/// so it's clear the inspection is saved but not yet sent to the server.
class _QueuedBanner extends StatelessWidget {
  const _QueuedBanner({required this.status});

  final OutboxStatus status;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String text, Color color) = switch (status) {
      OutboxStatus.pending => (
          Icons.cloud_upload_outlined,
          "Saved — will be submitted automatically when you're back online",
          kStatusAmber,
        ),
      OutboxStatus.sending => (
          Icons.cloud_sync_outlined,
          'Submitting…',
          kActionBlue,
        ),
      OutboxStatus.needsReview => (
          Icons.error_outline,
          'Not yet submitted — review answers and tap Complete to re-submit',
          kStatusRed,
        ),
      OutboxStatus.failed => (
          Icons.error_outline,
          'Upload failed — tap Complete to retry',
          kStatusRed,
        ),
    };
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: context.tokens.textStrong,
              ),
            ),
          ),
        ],
      ),
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
