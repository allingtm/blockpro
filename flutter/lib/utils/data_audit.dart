import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database.dart';

/// Debug-only instrumentation that answers three questions on every sync:
///   1. What does each API call actually return?      → `raw_<endpoint>.json`
///   2. What does each parser read (and therefore save)? vs what is dropped?
///   3. What actually landed in the local SQLite DB?
///
/// Everything is written to a `data_audit/` folder next to the SQLite file
/// (the app documents directory) and a one-line summary is printed to the
/// console with the folder path. All work is a no-op in release builds and
/// every entry point swallows its own errors so auditing can never break sync.
///
/// The "known key" sets below mirror exactly what each `fromJson` factory
/// reads. Any key the API returns that is NOT in these sets is data we drop.
/// Keep them in sync with the models if the parsers change.

const Set<String> _buildingKnownKeys = {
  'id', '_id', 'name', 'Name', 'List of assets',
};

const Set<String> _assetKnownKeys = {
  'assetId', 'buildingId', 'taskname', 'assetnickname', 'assetregisteritems',
  'tooltiptext', 'tooltipurls', 'lastcompleted', 'duedate', 'frequency',
  'colour', 'location', 'floor', 'yellowdate', 'assetlastmodified',
  'checklistlastmodified',
};

const Set<String> _checklistEntryKnownKeys = {'parentassetid', 'chapters'};
const Set<String> _chapterKnownKeys = {'chaptername', 'chapterorder', 'questions'};
const Set<String> _questionKnownKeys = {
  'questionid', 'questiontext', 'questiondesc', 'questionordernumber',
  'answertype', 'photorequirement', 'existingremedials',
};
const Set<String> _remedialKnownKeys = {
  'remedialname', 'remedialdesc', 'remediallocation', 'remedialduedate',
  'remedialpriority',
};

/// Audit a raw API response. [endpoint] is the workflow name (e.g.
/// `app_fetch_all_assets`); [label] disambiguates the raw-dump filename when
/// the same endpoint is hit per-building / per-asset (pass the id).
Future<void> auditApiResponse(String endpoint, dynamic rawData,
    {String? label}) async {
  if (!kDebugMode) return;
  try {
    final payload = _unwrap(rawData);
    final buffer = StringBuffer();
    buffer.writeln('\n## $endpoint'
        '${label != null ? ' [$label]' : ''} @ ${DateTime.now().toIso8601String()}');

    if (endpoint.contains('fetchbuildings')) {
      _auditBuildings(buffer, payload);
    } else if (endpoint.contains('all_assets') || endpoint.contains('asset_single')) {
      _auditAssets(buffer, payload);
    } else if (endpoint.contains('checklist')) {
      _auditChecklist(buffer, payload);
    } else {
      buffer.writeln('- (no audit rules for this endpoint; raw dumped only)');
    }

    final dir = await _auditDir();
    final safe = _safeName(endpoint);
    final rawName = label == null
        ? 'raw_$safe.json'
        : 'raw_${safe}_${_safeName(label)}.json';
    await _serialize(() async {
      // Dump the literal decoded body (pre-unwrap) so the raw file is the
      // complete response, including any Bubble {status, response} envelope.
      await File(p.join(dir.path, rawName))
          .writeAsString(_pretty(rawData));
      await _appendReport(dir, buffer.toString());
    });
    debugPrint('[DATA AUDIT] $endpoint → ${p.join(dir.path, rawName)}');
  } catch (e) {
    debugPrint('[DATA AUDIT] auditApiResponse($endpoint) failed: $e');
  }
}

/// Dump what actually landed in the local DB: row counts, real column names,
/// and a sample row per table. Call once at the end of a full sync.
Future<void> auditDbState(AppDatabase db) async {
  if (!kDebugMode) return;
  try {
    final buffer = StringBuffer();
    buffer.writeln('\n## LOCAL DB STATE @ ${DateTime.now().toIso8601String()}');
    for (final table in db.allTables) {
      final name = table.actualTableName;
      final countRow = await db
          .customSelect('SELECT COUNT(*) AS c FROM "$name"')
          .getSingle();
      final count = countRow.data['c'];
      buffer.writeln('\n### $name — $count rows');
      final sample =
          await db.customSelect('SELECT * FROM "$name" LIMIT 1').get();
      if (sample.isNotEmpty) {
        final cols = sample.first.data.keys.toList()..sort();
        buffer.writeln('- columns: $cols');
        buffer.writeln('- sample row: ${_sample(sample.first.data)}');
      }
    }
    final dir = await _auditDir();
    await _serialize(() => _appendReport(dir, buffer.toString()));
    debugPrint('[DATA AUDIT] DB state → ${p.join(dir.path, 'audit_report.md')}');
  } catch (e) {
    debugPrint('[DATA AUDIT] auditDbState failed: $e');
  }
}

// ── Per-endpoint audits ───────────────────────────────────────────────────

void _auditBuildings(StringBuffer b, dynamic payload) {
  final objs = _objectList(payload);
  b.writeln('Buildings returned: ${objs.length}');
  b.writeln('NOTE: Building.fromJson field names are flagged "best-guess" in '
      'code — check the two lines below against the real keys.');
  _reportLevel(b, 'building', objs, _buildingKnownKeys);
}

void _auditAssets(StringBuffer b, dynamic payload) {
  final objs = _objectList(payload);
  b.writeln('Assets returned: ${objs.length}');
  _reportLevel(b, 'asset', objs, _assetKnownKeys);
  // The two stringified-JSON blob fields you asked about: stored as opaque
  // TEXT, so their inner structure is saved but never broken into columns.
  _reportBlob(b, 'assetregisteritems', objs, innerKnown: null);
  _reportBlob(b, 'tooltipurls', objs, innerKnown: {'tooltipurl'});
}

void _auditChecklist(StringBuffer b, dynamic payload) {
  final entries = _objectList(payload);
  final chapters = entries
      .expand((e) => _asList(e['chapters']))
      .whereType<Map<String, dynamic>>()
      .toList();
  final questions = chapters
      .expand((c) => _asList(c['questions']))
      .whereType<Map<String, dynamic>>()
      .toList();
  final remedials = questions
      .expand((q) => _asList(q['existingremedials']))
      .whereType<Map<String, dynamic>>()
      .toList();

  b.writeln('Checklist: ${entries.length} entries, ${chapters.length} chapters, '
      '${questions.length} questions, ${remedials.length} remedials');
  _reportLevel(b, 'checklist entry', entries, _checklistEntryKnownKeys);
  _reportLevel(b, 'chapter', chapters, _chapterKnownKeys);
  _reportLevel(b, 'question', questions, _questionKnownKeys);
  _reportLevel(b, 'remedial', remedials, _remedialKnownKeys);
}

// ── Reporting helpers ─────────────────────────────────────────────────────

/// Compares the union of keys actually present across [objs] against the keys
/// the parser [known]s, and reports SAVED / LOST / mapping-drift.
void _reportLevel(
    StringBuffer b, String label, List<Map<String, dynamic>> objs, Set<String> known) {
  if (objs.isEmpty) {
    b.writeln('\n### $label — no objects in this response');
    return;
  }
  final union = _unionKeys(objs);
  final present = union.keys.toSet();
  final saved = present.intersection(known).toList()..sort();
  final lost = present.difference(known).toList()..sort();
  final missing = known.difference(present).toList()..sort();

  b.writeln('\n### $label — ${objs.length} objects, ${present.length} distinct keys');
  b.writeln('- SAVED (read by parser): $saved');
  if (lost.isEmpty) {
    b.writeln('- LOST: none — every returned field is read.');
  } else {
    b.writeln('- LOST (returned but dropped — ${lost.length}):');
    for (final k in lost) {
      b.writeln('    - `$k` = ${_sample(union[k])}');
    }
  }
  if (missing.isNotEmpty) {
    b.writeln('- ⚠ parser expects but API did NOT send: $missing '
        '(field-name mismatch?)');
  }
}

/// Decode a stringified-JSON blob field and report its inner shape.
void _reportBlob(StringBuffer b, String field, List<Map<String, dynamic>> objs,
    {Set<String>? innerKnown}) {
  final values = objs
      .map((o) => o[field])
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toList();
  b.writeln('\n### blob `$field` — ${values.length}/${objs.length} populated');
  if (values.isEmpty) {
    b.writeln('- (no populated samples to decode)');
    return;
  }
  final decoded = _tryDecodeBlob(values.first);
  if (decoded == null) {
    b.writeln('- not JSON-decodable; raw sample: ${_sample(values.first)}');
    return;
  }
  final inner = decoded is List
      ? decoded.whereType<Map<String, dynamic>>().toList()
      : decoded is Map<String, dynamic>
          ? [decoded]
          : <Map<String, dynamic>>[];
  if (inner.isEmpty) {
    b.writeln('- decoded to ${decoded.runtimeType}: ${_sample(decoded)}');
  } else {
    final union = _unionKeys(inner);
    b.writeln('- inner keys: ${union.keys.toList()..sort()}');
    if (innerKnown != null) {
      final lost = union.keys.toSet().difference(innerKnown).toList()..sort();
      b.writeln('- inner LOST: ${lost.isEmpty ? 'none' : lost}');
    }
    b.writeln('- decoded sample: ${_sample(inner.first)}');
  }
  b.writeln('- NOTE: stored as opaque TEXT — inner fields are not columns.');
}

// ── Plumbing ──────────────────────────────────────────────────────────────

/// Mirror the Bubble unwrap quirk used by the parsers (map-wrapped /
/// string-encoded responses).
dynamic _unwrap(dynamic data) {
  var payload = data;
  if (payload is Map<String, dynamic>) payload = payload['response'] ?? payload;
  if (payload is String) {
    try {
      payload = jsonDecode(payload);
    } catch (_) {/* leave as string */}
  }
  return payload;
}

List<Map<String, dynamic>> _objectList(dynamic payload) =>
    payload is List ? payload.whereType<Map<String, dynamic>>().toList() : const [];

List<dynamic> _asList(dynamic v) => v is List ? v : const [];

/// Reduce a string to filename-safe chars ([A-Za-z0-9_]) without RegExp.
String _safeName(String s) {
  final sb = StringBuffer();
  for (final ch in s.codeUnits) {
    final ok = (ch >= 48 && ch <= 57) || // 0-9
        (ch >= 65 && ch <= 90) || // A-Z
        (ch >= 97 && ch <= 122) || // a-z
        ch == 95; // _
    sb.writeCharCode(ok ? ch : 95);
  }
  return sb.toString();
}

/// Union of keys across all objects, keeping the first non-empty sample value
/// seen for each key.
Map<String, dynamic> _unionKeys(Iterable<Map<String, dynamic>> objs) {
  final out = <String, dynamic>{};
  for (final o in objs) {
    o.forEach((k, v) {
      final existing = out[k];
      if (!out.containsKey(k) || existing == null || existing == '') {
        out[k] = v;
      }
    });
  }
  return out;
}

dynamic _tryDecodeBlob(String raw) {
  for (final candidate in [raw, '[$raw]']) {
    try {
      return jsonDecode(candidate);
    } catch (_) {/* try next */}
  }
  return null;
}

String _sample(dynamic v) {
  var s = v is String ? v : jsonEncode(v);
  if (s.length > 240) s = '${s.substring(0, 240)}…';
  return s;
}

String _pretty(dynamic v) {
  try {
    return const JsonEncoder.withIndent('  ').convert(v);
  } catch (_) {
    return v.toString();
  }
}

Future<Directory> _auditDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'data_audit'));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

bool _announced = false;
Future<void> _appendReport(Directory dir, String section) async {
  final file = File(p.join(dir.path, 'audit_report.md'));
  await file.writeAsString(section, mode: FileMode.append, flush: true);
  if (!_announced) {
    _announced = true;
    debugPrint('[DATA AUDIT] report → ${file.path}');
  }
}

// Serialize file writes so concurrent per-building / per-asset syncs don't
// interleave appends.
Future<void> _lock = Future.value();
Future<void> _serialize(Future<void> Function() fn) {
  final completer = Completer<void>();
  _lock = _lock.then((_) async {
    try {
      await fn();
      completer.complete();
    } catch (e, st) {
      completer.completeError(e, st);
    }
  });
  return completer.future.catchError((_) {/* never propagate to caller */});
}
