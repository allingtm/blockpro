import 'dart:io';

import 'package:blockpro/models/outbox_entry.dart';
import 'package:blockpro/services/outbox_drainer.dart';
import 'package:blockpro/utils/outbox_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late OutboxStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('drainer_test_');
    store = OutboxStore(docsDir: () async => tmp);
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  OutboxEntry entry(String id,
          {int createdAt = 0,
          String? uid,
          OutboxStatus status = OutboxStatus.pending}) =>
      OutboxEntry(
          submissionId: id,
          assetId: 'a-$id',
          createdAt: createdAt,
          uid: uid,
          status: status);

  OutboxDrainer drainer({
    required CompletionSender send,
    bool offline = false,
    String? uid = 'me',
  }) =>
      OutboxDrainer(
        store: store,
        send: send,
        isOffline: () => offline,
        currentUid: () => uid,
      );

  /// A sender that records ids and removes the entry on success (as the real
  /// `replayCompletion` does).
  CompletionSender okSender(List<String> sent) =>
      (e) async {
        sent.add(e.submissionId);
        await store.remove(e.submissionId);
      };

  test('drains a pending entry and removes it on success', () async {
    await store.enqueue(entry('p1'));
    final sent = <String>[];
    await drainer(send: okSender(sent)).drain();

    expect(sent, ['p1']);
    expect(await store.readAll(), isEmpty);
  });

  test('sends entries FIFO by createdAt', () async {
    await store.enqueue(entry('s3', createdAt: 30));
    await store.enqueue(entry('s1', createdAt: 10));
    await store.enqueue(entry('s2', createdAt: 20));
    final sent = <String>[];
    await drainer(send: okSender(sent)).drain();

    expect(sent, ['s1', 's2', 's3']);
  });

  test('single-flight: concurrent drain() calls send each entry once',
      () async {
    for (var i = 0; i < 3; i++) {
      await store.enqueue(entry('s$i', createdAt: i));
    }
    final counts = <String, int>{};
    Future<void> countingOk(OutboxEntry e) async {
      counts.update(e.submissionId, (n) => n + 1, ifAbsent: () => 1);
      await store.remove(e.submissionId);
    }

    final d = drainer(send: countingOk);

    final f1 = d.drain();
    final f2 = d.drain(); // re-entrant while the first pass runs
    await Future.wait([f1, f2]);

    expect(counts, {'s0': 1, 's1': 1, 's2': 1});
    expect(await store.readAll(), isEmpty);
  });

  test('network error reverts the entry to pending and stops the pass',
      () async {
    await store.enqueue(entry('p1', createdAt: 1));
    await store.enqueue(entry('p2', createdAt: 2));
    final attempted = <String>[];
    Future<void> netFail(OutboxEntry e) async {
      attempted.add(e.submissionId);
      throw const SocketException('offline');
    }

    await drainer(send: netFail).drain();

    // Stopped after the first failure; p2 never attempted.
    expect(attempted, ['p1']);
    final all = {for (final e in await store.readAll()) e.submissionId: e};
    expect(all['p1']!.status, OutboxStatus.pending);
    expect(all['p2']!.status, OutboxStatus.pending);
    expect(all['p1']!.attemptCount, 1);
  });

  test('ambiguous error routes to needsReview and continues to the next entry',
      () async {
    await store.enqueue(entry('p1', createdAt: 1));
    await store.enqueue(entry('p2', createdAt: 2));
    final sent = <String>[];
    Future<void> mixed(OutboxEntry e) async {
      sent.add(e.submissionId);
      if (e.submissionId == 'p1') {
        throw Exception('API error: 500');
      }
      await store.remove(e.submissionId);
    }

    await drainer(send: mixed).drain();

    expect(sent, ['p1', 'p2']); // continued past the ambiguous p1
    final all = {for (final e in await store.readAll()) e.submissionId: e};
    expect(all['p1']!.status, OutboxStatus.needsReview);
    expect(all.containsKey('p2'), isFalse); // p2 succeeded and was removed
  });

  test('recoverStale: a stuck "sending" entry becomes needsReview, not resent',
      () async {
    await store.enqueue(entry('p1', status: OutboxStatus.sending));
    final sent = <String>[];
    await drainer(send: okSender(sent)).drain();

    expect(sent, isEmpty); // never sent
    expect((await store.getById('p1'))!.status, OutboxStatus.needsReview);
  });

  test('skips entries owned by a different user', () async {
    await store.enqueue(entry('mine', uid: 'me'));
    await store.enqueue(entry('theirs', uid: 'other'));
    final sent = <String>[];
    await drainer(send: okSender(sent), uid: 'me').drain();

    expect(sent, ['mine']);
    expect((await store.getById('theirs'))!.status, OutboxStatus.pending);
  });

  test('does nothing to pending entries while offline', () async {
    await store.enqueue(entry('p1'));
    final sent = <String>[];
    await drainer(send: okSender(sent), offline: true).drain();

    expect(sent, isEmpty);
    expect((await store.getById('p1'))!.status, OutboxStatus.pending);
  });

  test('recovers a stale "sending" entry even while offline', () async {
    await store.enqueue(entry('p1', status: OutboxStatus.sending));
    final sent = <String>[];
    await drainer(send: okSender(sent), offline: true).drain();

    // Stale recovery runs without connectivity; the entry is never resent.
    expect(sent, isEmpty);
    expect((await store.getById('p1'))!.status, OutboxStatus.needsReview);
  });
}
