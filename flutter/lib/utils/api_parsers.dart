import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/building.dart';
import '../models/question.dart';

/// Parses the buildings response from Bubble.
///
/// The `/wf/app_fetchbuildings` endpoint can return:
///   1. A JSON array directly (the actual observed behaviour)
///   2. A `Map` with a `response` key containing a JSON string → double-decode
///   3. A JSON string that needs a second decode
List<Building> parseBuildingsResponse(dynamic data) {
  dynamic payload = data;

  if (payload is Map<String, dynamic>) {
    payload = payload['response'] ?? payload;
  }

  if (payload is String) {
    payload = jsonDecode(payload);
  }

  if (payload is List) {
    return payload
        .whereType<Map<String, dynamic>>()
        .map((e) => Building.fromJson(e))
        .toList();
  }

  debugPrint('Unexpected app_fetchbuildings payload type: ${payload.runtimeType}');
  return [];
}

/// Parses the assets response from Bubble.
///
/// Same defensive strategy as buildings — handle list, map-wrapped, or
/// string-encoded responses.
List<Asset> parseAssetsResponse(dynamic data) {
  dynamic payload = data;

  if (payload is Map<String, dynamic>) {
    payload = payload['response'] ?? payload;
  }

  if (payload is String) {
    payload = jsonDecode(payload);
  }

  if (payload is List) {
    return payload
        .whereType<Map<String, dynamic>>()
        .map((e) => Asset.fromJson(e))
        .toList();
  }

  debugPrint('Unexpected app_fetch_all_assets payload type: ${payload.runtimeType}');
  return [];
}

/// Parses the v2 checklist response from Bubble.
///
/// The `/wf/app_fetch_checklist_single` endpoint returns a JSON array where
/// each entry has the shape:
///   `{ "parentassetid": "...", "chapters": [ { chaptername, chapterorder,
///     questions: [ { questionid, questiontext, ... } ] } ] }`
///
/// Returns a flat list of Chapters (each with its nested questions) across
/// all entries in the response.
List<Chapter> parseChecklistResponse(dynamic data) {
  dynamic payload = data;

  if (payload is Map<String, dynamic>) {
    payload = payload['response'] ?? payload;
  }

  if (payload is String) {
    payload = jsonDecode(payload);
  }

  if (payload is! List) {
    debugPrint(
        'Unexpected app_fetch_checklist_single payload type: ${payload.runtimeType}');
    return [];
  }

  final chapters = <Chapter>[];
  for (final entry in payload.whereType<Map<String, dynamic>>()) {
    final assetId = entry['parentassetid'] as String? ?? '';
    final chaptersRaw = entry['chapters'];
    if (chaptersRaw is! List) continue;
    for (final c in chaptersRaw.whereType<Map<String, dynamic>>()) {
      chapters.add(Chapter.fromJson(c, assetId: assetId));
    }
  }
  return chapters;
}
