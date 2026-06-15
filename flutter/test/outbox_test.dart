import 'dart:convert';
import 'dart:io';

import 'package:blockpro/models/new_remedial.dart';
import 'package:blockpro/models/outbox_entry.dart';
import 'package:blockpro/models/register_item.dart';
import 'package:blockpro/utils/completion_photo_store.dart';
import 'package:blockpro/utils/outbox_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('generateSubmissionId', () {
    test('produces a v4-format UUID', () {
      final id = generateSubmissionId();
      final re = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(re.hasMatch(id), isTrue, reason: 'got "$id"');
    });

    test('is unique across many calls', () {
      final ids = List.generate(1000, (_) => generateSubmissionId()).toSet();
      expect(ids.length, 1000);
    });
  });

  group('OutboxEntry JSON', () {
    test('round-trips with all fields populated', () {
      const entry = OutboxEntry(
        submissionId: 'sub-1',
        uid: 'user-1',
        assetId: 'asset-1',
        frequency: '7 Day(s)',
        checklistLastModified: '2026-06-01T00:00:00.000Z',
        answers: [OutboxAnswer(question: 'Q1', answer: 'Yes')],
        photos: [OutboxPhoto(localPath: '/x/0.jpg', uploadedImageId: 'img-1')],
        status: OutboxStatus.sending,
        attemptCount: 2,
        createdAt: 1234567890,
        lastAttemptAt: 1234567899,
        lastError: 'boom',
      );
      final restored = OutboxEntry.fromJson(
          jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>);

      expect(restored.submissionId, 'sub-1');
      expect(restored.uid, 'user-1');
      expect(restored.assetId, 'asset-1');
      expect(restored.frequency, '7 Day(s)');
      expect(restored.checklistLastModified, '2026-06-01T00:00:00.000Z');
      expect(restored.answers.single.question, 'Q1');
      expect(restored.answers.single.answer, 'Yes');
      expect(restored.photos.single.localPath, '/x/0.jpg');
      expect(restored.photos.single.uploadedImageId, 'img-1');
      expect(restored.photos.single.isUploaded, isTrue);
      expect(restored.status, OutboxStatus.sending);
      expect(restored.attemptCount, 2);
      expect(restored.createdAt, 1234567890);
      expect(restored.lastAttemptAt, 1234567899);
      expect(restored.lastError, 'boom');
    });

    test('round-trips an answer carrying a remedial', () {
      const entry = OutboxEntry(
        submissionId: 'sub-r',
        assetId: 'asset-1',
        createdAt: 1,
        answers: [
          OutboxAnswer(
            question: 'Q1',
            answer: 'Unsatisfactory',
            questionId: 'q1',
            remedial: NewRemedial(
              title: 'Glazing cracked',
              location: '1st floor landing',
              description: 'Cracked bad.',
              priority: 'High',
              registerItems: [
                RegisterItem(ref: 'Wallbox1', floor: '1st', location: 'Landing'),
              ],
            ),
          ),
          OutboxAnswer(question: 'Q2', answer: 'Satisfactory'),
        ],
      );
      final restored = OutboxEntry.fromJson(
          jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>);

      final r = restored.answers.first.remedial;
      expect(r, isNotNull);
      expect(r!.title, 'Glazing cracked');
      expect(r.location, '1st floor landing');
      expect(r.description, 'Cracked bad.');
      expect(r.priority, 'High');
      expect(r.registerItems.single.ref, 'Wallbox1');
      expect(r.registerItems.single.floor, '1st');
      expect(r.registerItems.single.location, 'Landing');
      // No-remedial answers serialize WITHOUT the key (backend contract).
      expect(restored.answers.last.remedial, isNull);
      expect(entry.answers.last.toJson().containsKey('remedial'), isFalse);
    });

    test('legacy entry JSON without a remedial key still parses', () {
      final restored = OutboxAnswer.fromJson(
          {'question': 'Q1', 'answer': 'Yes', 'questionId': 'q1'});
      expect(restored.question, 'Q1');
      expect(restored.remedial, isNull);
    });

    test('round-trips with nullable fields absent', () {
      const entry =
          OutboxEntry(submissionId: 's', assetId: 'a', createdAt: 1);
      final restored = OutboxEntry.fromJson(
          jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>);

      expect(restored.uid, isNull);
      expect(restored.frequency, isNull);
      expect(restored.answers, isEmpty);
      expect(restored.photos, isEmpty);
      expect(restored.status, OutboxStatus.pending);
      expect(restored.attemptCount, 0);
    });

    test('copyWith preserves submissionId and updates status/attempt', () {
      const entry =
          OutboxEntry(submissionId: 's', assetId: 'a', createdAt: 1);
      final updated =
          entry.copyWith(status: OutboxStatus.failed, attemptCount: 3);
      expect(updated.submissionId, 's');
      expect(updated.assetId, 'a');
      expect(updated.status, OutboxStatus.failed);
      expect(updated.attemptCount, 3);
    });

    test('copyWith clearError nulls the error', () {
      const entry = OutboxEntry(
          submissionId: 's', assetId: 'a', createdAt: 1, lastError: 'x');
      expect(entry.copyWith(clearError: true).lastError, isNull);
    });

    test('unknown / null status decodes to pending', () {
      expect(OutboxStatus.fromJson('bogus'), OutboxStatus.pending);
      expect(OutboxStatus.fromJson(null), OutboxStatus.pending);
    });
  });

  group('CompletionPhotoStore', () {
    late Directory tmp;
    late CompletionPhotoStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('cps_test_');
      store = CompletionPhotoStore(docsDir: () async => tmp);
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    File srcFile(String name) =>
        File(p.join(tmp.path, name))..writeAsBytesSync([1, 2, 3]);

    test('persists under outbox/<submissionId>/ keyed by submissionId',
        () async {
      final path = await store.persistPhoto(srcFile('src.jpg'), 'sub-1', index: 0);
      expect(path, p.join(tmp.path, 'outbox', 'sub-1', '0.jpg'));
      expect(File(path).existsSync(), isTrue);
    });

    test('re-persisting a file already in the folder returns it unchanged',
        () async {
      final path = await store.persistPhoto(srcFile('src.jpg'), 'sub-1', index: 0);
      final again = await store.persistPhoto(File(path), 'sub-1', index: 0);
      expect(again, path);
    });

    test('deleteSubmissionPhotos removes only that submission', () async {
      await store.persistPhoto(srcFile('a.jpg'), 'sub-1', index: 0);
      await store.persistPhoto(srcFile('b.jpg'), 'sub-2', index: 0);
      await store.deleteSubmissionPhotos('sub-1');
      expect(Directory(p.join(tmp.path, 'outbox', 'sub-1')).existsSync(), isFalse);
      expect(Directory(p.join(tmp.path, 'outbox', 'sub-2')).existsSync(), isTrue);
    });

    test('listSubmissionDirs returns folder ids (ignores files)', () async {
      await store.persistPhoto(srcFile('a.jpg'), 'sub-1', index: 0);
      await store.persistPhoto(srcFile('b.jpg'), 'sub-2', index: 0);
      File(p.join(tmp.path, 'outbox', 'outbox.json')).writeAsStringSync('{}');
      expect(await store.listSubmissionDirs(), {'sub-1', 'sub-2'});
    });

    test('deleteAllPhotos clears submissions but leaves the manifest file',
        () async {
      await store.persistPhoto(srcFile('a.jpg'), 'sub-1', index: 0);
      final manifest = File(p.join(tmp.path, 'outbox', 'outbox.json'))
        ..writeAsStringSync('{}');
      await store.deleteAllPhotos();
      expect(Directory(p.join(tmp.path, 'outbox', 'sub-1')).existsSync(), isFalse);
      expect(manifest.existsSync(), isTrue);
    });
  });

  group('OutboxStore', () {
    late Directory tmp;
    late OutboxStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('outbox_test_');
      store = OutboxStore(docsDir: () async => tmp);
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    OutboxEntry entry(String id,
            {int createdAt = 0, OutboxStatus status = OutboxStatus.pending}) =>
        OutboxEntry(
            submissionId: id,
            assetId: 'a-$id',
            createdAt: createdAt,
            status: status);

    test('readAll on an empty store returns []', () async {
      expect(await store.readAll(), isEmpty);
    });

    test('enqueue then readAll round-trips', () async {
      await store.enqueue(entry('s1', createdAt: 1));
      expect((await store.readAll()).single.submissionId, 's1');
    });

    test('readAll returns FIFO by createdAt', () async {
      await store.enqueue(entry('s2', createdAt: 20));
      await store.enqueue(entry('s1', createdAt: 10));
      await store.enqueue(entry('s3', createdAt: 30));
      expect((await store.readAll()).map((e) => e.submissionId).toList(),
          ['s1', 's2', 's3']);
    });

    test('enqueue replaces an entry with the same submissionId (supersede)',
        () async {
      await store.enqueue(entry('s1', createdAt: 1));
      await store.enqueue(entry('s1', createdAt: 1, status: OutboxStatus.failed));
      final all = await store.readAll();
      expect(all.length, 1);
      expect(all.single.status, OutboxStatus.failed);
    });

    test('update replaces in place; no-op when absent', () async {
      await store.enqueue(entry('s1', createdAt: 1));
      await store
          .update(entry('s1', createdAt: 1, status: OutboxStatus.sending));
      expect((await store.readAll()).single.status, OutboxStatus.sending);
      await store.update(entry('missing'));
      expect((await store.readAll()).length, 1);
    });

    test('remove deletes the entry and its photo folder', () async {
      final photos = CompletionPhotoStore(docsDir: () async => tmp);
      final src = File(p.join(tmp.path, 's.jpg'))..writeAsBytesSync([1]);
      await photos.persistPhoto(src, 's1', index: 0);
      await store.enqueue(entry('s1'));
      await store.remove('s1');
      expect(await store.readAll(), isEmpty);
      expect(Directory(p.join(tmp.path, 'outbox', 's1')).existsSync(), isFalse);
    });

    test('clearAll empties the manifest and photos', () async {
      final photos = CompletionPhotoStore(docsDir: () async => tmp);
      final src = File(p.join(tmp.path, 's.jpg'))..writeAsBytesSync([1]);
      await photos.persistPhoto(src, 's1', index: 0);
      await store.enqueue(entry('s1'));
      await store.enqueue(entry('s2'));
      await store.clearAll();
      expect(await store.readAll(), isEmpty);
      expect(Directory(p.join(tmp.path, 'outbox', 's1')).existsSync(), isFalse);
    });

    test('corrupt manifest is treated as empty', () async {
      final f = File(p.join(tmp.path, 'outbox', 'outbox.json'));
      await f.create(recursive: true);
      await f.writeAsString('{ this is not valid json');
      expect(await store.readAll(), isEmpty);
    });

    test('concurrent enqueues all persist (mutex serializes RMW)', () async {
      await Future.wait(
          List.generate(20, (i) => store.enqueue(entry('s$i', createdAt: i))));
      final all = await store.readAll();
      expect(all.length, 20);
      expect(all.map((e) => e.submissionId).toSet(),
          {for (var i = 0; i < 20; i++) 's$i'});
    });

    test('atomic write leaves no .tmp file behind', () async {
      await store.enqueue(entry('s1'));
      final tmpFile = File(p.join(tmp.path, 'outbox', 'outbox.json.tmp'));
      expect(tmpFile.existsSync(), isFalse);
    });

    test('sweepOrphanPhotoDirs deletes folders with no matching entry',
        () async {
      final photos = CompletionPhotoStore(docsDir: () async => tmp);
      final src = File(p.join(tmp.path, 's.jpg'))..writeAsBytesSync([1]);
      await photos.persistPhoto(src, 'orphan', index: 0);
      await photos.persistPhoto(src, 'kept', index: 0);
      await store.enqueue(entry('kept'));
      await store.sweepOrphanPhotoDirs();
      expect(Directory(p.join(tmp.path, 'outbox', 'orphan')).existsSync(),
          isFalse);
      expect(
          Directory(p.join(tmp.path, 'outbox', 'kept')).existsSync(), isTrue);
    });
  });
}
