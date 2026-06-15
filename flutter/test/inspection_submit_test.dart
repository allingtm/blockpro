import 'dart:io';

import 'package:blockpro/database/database.dart';
import 'package:blockpro/models/new_remedial.dart';
import 'package:blockpro/models/outbox_entry.dart';
import 'package:blockpro/models/question.dart';
import 'package:blockpro/models/register_item.dart';
import 'package:blockpro/providers/drafts_provider.dart';
import 'package:blockpro/providers/inspection_provider.dart';
import 'package:blockpro/services/outbox_drainer.dart';
import 'package:blockpro/utils/completion_photo_store.dart';
import 'package:blockpro/utils/draft_photo_store.dart';
import 'package:blockpro/utils/outbox_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late AppDatabase db;
  late OutboxStore outbox;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('submit_test_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxStore(docsDir: () async => tmp);
  });
  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  // A drainer that never does anything (offline), so submit()'s fire-and-forget
  // drain has no side effects on the assertions.
  OutboxDrainer inertDrainer() => OutboxDrainer(
        store: outbox,
        send: (e) async {},
        isOffline: () => true,
        currentUid: () => 'me',
      );

  InspectionNotifier notifier(
    List<QuestionAnswer> answers, {
    bool offline = true,
  }) =>
      InspectionNotifier(
        db.draftsDao,
        db.assetsDao,
        DraftPhotoStore(docsDir: () async => tmp),
        CompletionPhotoStore(docsDir: () async => tmp),
        outbox,
        inertDrainer(),
        () {}, // onOutboxChanged
        'me', // uid
        () => offline,
        'asset-1',
        '7 Day(s)',
        answers,
      );

  Question question(String id) =>
      Question(id: id, questionText: 'Q-$id', chapterId: 'c1');

  QuestionAnswer answer(String qid, String value, {List<File> photos = const []}) =>
      QuestionAnswer(
        question: question(qid),
        chapterName: 'Chapter',
        selectedAnswer: value,
        photos: photos,
      );

  test('completing offline enqueues a self-contained entry and marks queued',
      () async {
    final photo = File(p.join(tmp.path, 'pic.jpg'))..writeAsBytesSync([1, 2, 3]);
    final n = notifier([answer('q1', 'Yes', photos: [photo])], offline: true);

    await n.submit();

    expect(n.state.isComplete, isTrue);
    expect(n.state.isQueued, isTrue);
    expect(n.state.submitError, isNull);

    final entries = await outbox.readAll();
    expect(entries.length, 1);
    final e = entries.single;
    expect(e.assetId, 'asset-1');
    expect(e.uid, 'me');
    expect(e.frequency, '7 Day(s)');
    expect(e.status, OutboxStatus.pending);
    expect(e.answers.single.question, 'Q-q1');
    expect(e.answers.single.answer, 'Yes');
    expect(e.answers.single.questionId, 'q1');
    // Photo persisted durably under the submission folder, tagged with its
    // question.
    expect(e.photos.single.questionId, 'q1');
    expect(File(e.photos.single.localPath).existsSync(), isTrue);
    expect(p.isWithin(p.join(tmp.path, 'outbox', e.submissionId),
        e.photos.single.localPath), isTrue);
  });

  test('completing online marks NOT queued', () async {
    final n = notifier([answer('q1', 'Yes')], offline: false);
    await n.submit();
    expect(n.state.isComplete, isTrue);
    expect(n.state.isQueued, isFalse);
    expect((await outbox.readAll()).length, 1);
  });

  test('re-completing supersedes the prior queued entry for the asset',
      () async {
    await outbox.enqueue(const OutboxEntry(
        submissionId: 'old', assetId: 'asset-1', createdAt: 1));

    await notifier([answer('q1', 'No')]).submit();

    final entries = await outbox.readAll();
    expect(entries.length, 1);
    expect(entries.single.submissionId, isNot('old'));
    expect(entries.single.answers.single.answer, 'No');
  });

  test('refuses to enqueue while a prior entry is already sending', () async {
    await outbox.enqueue(const OutboxEntry(
      submissionId: 'inflight',
      assetId: 'asset-1',
      createdAt: 1,
      status: OutboxStatus.sending,
    ));

    final n = notifier([answer('q1', 'Yes')]);
    await n.submit();

    expect(n.state.isComplete, isFalse);
    expect(n.state.submitError, isNotNull);
    final entries = await outbox.readAll();
    expect(entries.length, 1);
    expect(entries.single.submissionId, 'inflight');
  });

  test('validation blocks an unanswered multiple-choice question', () async {
    final q = Question(
        id: 'q1',
        questionText: 'Pick',
        chapterId: 'c1',
        answerOption: AnswerOption.yesNo);
    final n = notifier([
      QuestionAnswer(question: q, chapterName: 'c', selectedAnswer: null),
    ]);

    await n.submit();

    expect(n.state.submitError, isNotNull);
    expect(n.state.isComplete, isFalse);
    expect(await outbox.readAll(), isEmpty);
  });

  Question optionQuestion(String id) => Question(
        id: id,
        questionText: 'Q-$id',
        chapterId: 'c1',
        answerOption: AnswerOption.satisfactoryUnsatisfactory,
      );

  const remedial = NewRemedial(
    title: 'Glazing cracked',
    location: '1st floor landing',
    description: 'Cracked bad.',
    priority: 'High',
    registerItems: [RegisterItem(ref: 'Wallbox1', floor: '1st')],
  );

  test('a filled remedial on a negative answer reaches the outbox entry',
      () async {
    final n = notifier([
      QuestionAnswer(
        question: optionQuestion('q1'),
        chapterName: 'c',
        selectedAnswer: 'Unsatisfactory',
        remedial: remedial,
      ),
    ]);

    await n.submit();

    final entry = (await outbox.readAll()).single;
    final sent = entry.answers.single.remedial;
    expect(sent, isNotNull);
    expect(sent!.title, 'Glazing cracked');
    expect(sent.location, '1st floor landing');
    expect(sent.description, 'Cracked bad.');
    expect(sent.priority, 'High');
    expect(sent.registerItems.single.ref, 'Wallbox1');
  });

  test('a blank-title remedial is dropped at submit', () async {
    final n = notifier([
      QuestionAnswer(
        question: optionQuestion('q1'),
        chapterName: 'c',
        selectedAnswer: 'Unsatisfactory',
        remedial: const NewRemedial(title: '   ', priority: 'High'),
      ),
    ]);

    await n.submit();

    expect((await outbox.readAll()).single.answers.single.remedial, isNull);
  });

  test('flipping a negative answer to positive discards the remedial',
      () async {
    final n = notifier([
      QuestionAnswer(
        question: optionQuestion('q1'),
        chapterName: 'c',
        selectedAnswer: 'Unsatisfactory',
        remedial: remedial,
      ),
    ]);

    n.updateAnswer(0, 'Satisfactory');
    expect(n.state.answers.single.remedial, isNull);

    // Returning to negative starts from a blank form.
    n.updateAnswer(0, 'Unsatisfactory');
    expect(n.state.answers.single.remedial, isNull);
  });

  test('updateRemedial marks the inspection dirty; draft round-trips it',
      () async {
    // Drafts FK onto the assets table — seed the asset (and its building).
    await db.buildingsDao.upsertBuildings(
        [BuildingsTableCompanion.insert(id: 'b1')]);
    await db.assetsDao.upsertAssets(
        [AssetsTableCompanion.insert(id: 'asset-1', buildingId: 'b1')]);

    final n = notifier([
      QuestionAnswer(
        question: optionQuestion('q1'),
        chapterName: 'c',
        selectedAnswer: 'Unsatisfactory',
      ),
    ]);
    expect(n.isDirty, isFalse);

    n.updateRemedial(0, remedial);
    expect(n.isDirty, isTrue);

    await n.saveDraft();
    final rows = await db.draftsDao.getDraftAnswers('asset-1');
    final restored = DraftAnswer.decodeRemedial(rows.single.remedialJson);
    expect(restored, isNotNull);
    expect(restored!.title, 'Glazing cracked');
    expect(restored.priority, 'High');
    expect(restored.registerItems.single.ref, 'Wallbox1');
  });
}
