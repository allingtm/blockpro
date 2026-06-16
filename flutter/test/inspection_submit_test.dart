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
    List<File> inspectionPhotos = const [],
    List<RegisterItem> registerItems = const [],
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
        inspectionPhotos: inspectionPhotos,
        selectedRegisterItems: registerItems,
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
    // No prior remedials on the question → this one was mandatory.
    expect(entry.answers.single.remedialRequired, isTrue);
  });

  // A question that already carries a prior remedial, so raising a new one is
  // optional even on the negative path.
  Question questionWithExistingRemedial(String id) => Question(
        id: id,
        questionText: 'Q-$id',
        chapterId: 'c1',
        answerOption: AnswerOption.satisfactoryUnsatisfactory,
        existingRemedials: [Remedial(name: 'Prior issue')],
      );

  test('POST body sends the remedial object and never a remedial_type',
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

    final body = buildCompletionBody((await outbox.readAll()).single,
        const <({String? questionId, String imageId})>[]);
    final ans = (body['answers'] as List).single as Map;
    // `remedial_type` was dropped from the contract — the backend never used it.
    expect(ans.containsKey('remedial_type'), isFalse);
    // The remedial object uses the snake_case wire keys.
    final sent = ans['remedial'] as Map;
    expect(sent['remedial_name'], 'Glazing cracked');
    expect(sent['remedial_location'], '1st floor landing');
    expect(sent['remedial_desc'], 'Cracked bad.');
    expect(sent['remedial_priority'], 'High');
    expect((sent['register_items'] as List).single,
        {'register_item_ref': 'Wallbox1', 'register_item_floor': '1st'});
  });

  test('POST body omits remedial (and remedial_type) when none was raised',
      () async {
    final n = notifier([answer('q1', 'Yes')]);
    await n.submit();
    final body = buildCompletionBody((await outbox.readAll()).single,
        const <({String? questionId, String imageId})>[]);
    final ans = (body['answers'] as List).single as Map;
    expect(ans.containsKey('remedial'), isFalse);
    expect(ans.containsKey('remedial_type'), isFalse);
  });

  test('OutboxAnswer round-trips remedialRequired; defaults false when absent',
      () {
    final json = const OutboxAnswer(
      question: 'Q',
      answer: 'No',
      remedialRequired: true,
    ).toJson();
    expect(OutboxAnswer.fromJson(json).remedialRequired, isTrue);
    // An entry queued by an older app version has no key → defaults to false.
    expect(
      OutboxAnswer.fromJson({'question': 'Q', 'answer': 'No'}).remedialRequired,
      isFalse,
    );
  });

  test('OutboxAnswer round-trips questionId and chapterId', () {
    final json = const OutboxAnswer(
      question: 'Q',
      answer: 'No',
      questionId: 'q1',
      chapterId: 'asset-1_0',
    ).toJson();
    final restored = OutboxAnswer.fromJson(json);
    expect(restored.questionId, 'q1');
    expect(restored.chapterId, 'asset-1_0');
    // An entry queued by an older app version has no chapterId key → null.
    expect(
      OutboxAnswer.fromJson({'question': 'Q', 'answer': 'No'}).chapterId,
      isNull,
    );
  });

  test('a blank-title remedial is dropped at submit', () async {
    final n = notifier([
      QuestionAnswer(
        // Existing remedial present → blank new remedial is allowed (optional).
        question: questionWithExistingRemedial('q1'),
        chapterName: 'c',
        selectedAnswer: 'Unsatisfactory',
        remedial: const NewRemedial(title: '   ', priority: 'High'),
      ),
    ]);

    await n.submit();

    expect((await outbox.readAll()).single.answers.single.remedial, isNull);
  });

  test('a negative answer with no existing remedials blocks submit', () async {
    final n = notifier([
      QuestionAnswer(
        question: optionQuestion('q1'),
        chapterName: 'c',
        selectedAnswer: 'Unsatisfactory',
      ),
    ]);

    await n.submit();

    expect(n.state.submitError, contains('Remedial required'));
    expect(n.state.isComplete, isFalse);
    expect(await outbox.readAll(), isEmpty);
  });

  test('existing remedials make a new remedial optional', () async {
    final n = notifier([
      QuestionAnswer(
        question: questionWithExistingRemedial('q1'),
        chapterName: 'c',
        selectedAnswer: 'Unsatisfactory',
      ),
    ]);

    await n.submit();

    expect(n.state.isComplete, isTrue);
    expect(n.state.submitError, isNull);
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

  test(
      'inspection-level register items + photos reach the entry and POST body',
      () async {
    final headerPhoto = File(p.join(tmp.path, 'header.jpg'))
      ..writeAsBytesSync([9, 9, 9]);
    final n = notifier(
      [answer('q1', 'Yes')],
      inspectionPhotos: [headerPhoto],
      registerItems: const [
        RegisterItem(ref: 'Wallbox1', floor: '1st', location: 'Landing'),
      ],
    );

    await n.submit();

    // Survives the manifest JSON round-trip (readAll deserializes from disk).
    final entry = (await outbox.readAll()).single;
    expect(entry.registerItems.single.ref, 'Wallbox1');

    // The inspection-level photo carries a null questionId and is durable.
    final headerPhotos =
        entry.photos.where((ph) => ph.questionId == null).toList();
    expect(headerPhotos.length, 1);
    expect(File(headerPhotos.single.localPath).existsSync(), isTrue);

    // The POST body exposes the items under the top-level `register_items` key,
    // mirroring the remedial shape, splits header photos (null questionId) into
    // `inspection_photo_ids`, and surfaces per-question evidence as each
    // answer's own `photo_ids` list.
    final body = buildCompletionBody(entry, const [
      (questionId: null, imageId: 'hdr-1'),
      (questionId: 'q1', imageId: 'q-1'),
    ]);
    final items = body['register_items'] as List;
    expect(items.single, {
      'register_item_ref': 'Wallbox1',
      'register_item_floor': '1st',
      'register_item_location': 'Landing',
    });
    expect(body['inspection_photo_ids'], ['hdr-1']);
    final ans = (body['answers'] as List).single as Map;
    expect(ans['question_id'], 'q1');
    expect(ans['chapter_id'], 'c1');
    expect(ans['photo_ids'], ['q-1']);
    // The old flat top-level photo_ids list is gone (per-answer photo_ids only).
    expect(body.containsKey('photo_ids'), isFalse);
  });

  test('an answer has no photo_ids when only a header photo was uploaded',
      () async {
    final n = notifier([answer('q1', 'Yes')]);
    await n.submit();
    final body = buildCompletionBody(
      (await outbox.readAll()).single,
      const [(questionId: null, imageId: 'hdr-1')],
    );
    expect(body['inspection_photo_ids'], ['hdr-1']);
    final ans = (body['answers'] as List).single as Map;
    expect(ans.containsKey('photo_ids'), isFalse);
    expect(body.containsKey('photo_ids'), isFalse);
  });

  test(
      'inspection_photo_ids omitted when only a per-question photo was uploaded',
      () async {
    final n = notifier([answer('q1', 'Yes')]);
    await n.submit();
    final body = buildCompletionBody(
      (await outbox.readAll()).single,
      const [(questionId: 'q1', imageId: 'q-1')],
    );
    final ans = (body['answers'] as List).single as Map;
    expect(ans['photo_ids'], ['q-1']);
    expect(body.containsKey('inspection_photo_ids'), isFalse);
    expect(body.containsKey('photo_ids'), isFalse);
  });

  test('an answer surfaces every uploaded photo in its photo_ids list',
      () async {
    final n = notifier([answer('q1', 'Yes')]);
    await n.submit();
    // Two photos tagged to the same question must both reach the payload —
    // the old single-id map dropped all but the last.
    final body = buildCompletionBody(
      (await outbox.readAll()).single,
      const [
        (questionId: 'q1', imageId: 'q-a'),
        (questionId: 'q1', imageId: 'q-b'),
      ],
    );
    final ans = (body['answers'] as List).single as Map;
    expect(ans['photo_ids'], ['q-a', 'q-b']);
  });

  test('every answer carries question_id and chapter_id', () async {
    final n = notifier([answer('q1', 'Yes')]);
    await n.submit();
    final body = buildCompletionBody((await outbox.readAll()).single,
        const <({String? questionId, String imageId})>[]);
    final ans = (body['answers'] as List).single as Map;
    expect(ans['question_id'], 'q1');
    expect(ans['chapter_id'], 'c1');
    // No photo uploaded for this answer → no photo_ids key.
    expect(ans.containsKey('photo_ids'), isFalse);
  });

  test('the POST body carries an ISO-8601 UTC completion_date', () async {
    final n = notifier([answer('q1', 'Yes')]);
    await n.submit();
    final body = buildCompletionBody((await outbox.readAll()).single,
        const <({String? questionId, String imageId})>[]);
    // Sibling of asset_id, derived from the entry's createdAt (enqueue time).
    final completionDate = body['completion_date'] as String;
    expect(completionDate, endsWith('Z'));
    expect(DateTime.tryParse(completionDate), isNotNull);
  });

  test('omits register_items from the POST body when none are tagged', () async {
    final n = notifier([answer('q1', 'Yes')]);
    await n.submit();
    final body = buildCompletionBody((await outbox.readAll()).single,
        const <({String? questionId, String imageId})>[]);
    expect(body.containsKey('register_items'), isFalse);
  });

  test('draft round-trips inspection-level photos and register items',
      () async {
    // Drafts FK onto the assets table — seed the asset (and its building).
    await db.buildingsDao
        .upsertBuildings([BuildingsTableCompanion.insert(id: 'b1')]);
    await db.assetsDao.upsertAssets(
        [AssetsTableCompanion.insert(id: 'asset-1', buildingId: 'b1')]);

    final headerPhoto = File(p.join(tmp.path, 'header.jpg'))
      ..writeAsBytesSync([7, 7, 7]);
    final n = notifier(
      [answer('q1', 'Yes')],
      inspectionPhotos: [headerPhoto],
      registerItems: const [RegisterItem(ref: 'Wallbox2', floor: '2nd')],
    );

    await n.saveDraft();

    final row = await db.draftsDao.getDraftInspection('asset-1');
    expect(row, isNotNull);
    // Photo copied to durable per-asset storage.
    final paths = (row!.photoPaths ?? '').split('\n');
    expect(paths.length, 1);
    expect(File(paths.single).existsSync(), isTrue);
    final items = DraftInspection.decodeRegisterItems(row.registerItemsJson);
    expect(items.single.ref, 'Wallbox2');
    expect(items.single.floor, '2nd');
  });
}
