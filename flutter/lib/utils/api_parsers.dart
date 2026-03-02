import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/building.dart';
import '../models/question.dart';

/// Parses the buildings response from Bubble.
///
/// The `/wf/fetchbuildings` endpoint can return:
///   1. A JSON array directly (the actual observed behaviour)
///   2. A `Map` with a `response` key containing a JSON string → double-decode
///   3. A JSON string that needs a second decode
List<Building> parseBuildingsResponse(dynamic data) {
  dynamic payload = data;

  // If wrapped in a map with a "response" key, unwrap it.
  if (payload is Map<String, dynamic>) {
    payload = payload['response'] ?? payload;
  }

  // If the payload is a string, it needs a second JSON decode.
  if (payload is String) {
    payload = jsonDecode(payload);
  }

  if (payload is List) {
    return payload
        .whereType<Map<String, dynamic>>()
        .map((e) => Building.fromJson(e))
        .toList();
  }

  debugPrint('Unexpected fetchbuildings payload type: ${payload.runtimeType}');
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

  debugPrint('Unexpected fetchassets payload type: ${payload.runtimeType}');
  return [];
}

/// Parses the questions response from Bubble.
List<Question> parseQuestionsResponse(dynamic data) {
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
        .map((e) => Question.fromJson(e))
        .toList();
  }

  debugPrint('Unexpected fetchquestions payload type: ${payload.runtimeType}');
  return [];
}

/// Parses the checklist response from Bubble.
///
/// The `/wf/fetchchecklist` endpoint returns:
///   `{ "status": "success", "response": { "checklist": "<concatenated-json>" } }`
///
/// The checklist value is multiple JSON objects concatenated with commas but
/// NOT wrapped in array brackets, e.g.: `{...},{...}`. We wrap in `[...]`
/// before parsing.
List<Question> parseChecklistResponse(dynamic data) {
  dynamic payload = data;

  // Unwrap the Bubble response envelope.
  if (payload is Map<String, dynamic>) {
    final response = payload['response'];
    if (response is Map<String, dynamic>) {
      payload = response['checklist'] ?? response;
    } else {
      payload = response ?? payload;
    }
  }

  // If it's a string, it may be malformed:
  //   - Concatenated objects without array brackets: {…},{…}
  //   - Typographic/smart quotes instead of straight quotes: \u201C \u201D
  if (payload is String) {
    var jsonString = payload.trim();

    // Replace smart/curly quotes with straight quotes.
    jsonString = jsonString
        .replaceAll('\u201C', '"') // left double quotation mark
        .replaceAll('\u201D', '"') // right double quotation mark
        .replaceAll('\u2018', "'") // left single quotation mark
        .replaceAll('\u2019', "'"); // right single quotation mark

    // If it starts with { and not [, wrap it in an array.
    if (jsonString.startsWith('{')) {
      jsonString = '[$jsonString]';
    }
    try {
      payload = jsonDecode(jsonString);
    } catch (e) {
      debugPrint('Failed to parse checklist JSON: $e');
      debugPrint('Attempted to parse: $jsonString');
      return [];
    }
  }

  if (payload is List) {
    return payload
        .whereType<Map<String, dynamic>>()
        .map((e) => Question.fromJson(e))
        .toList();
  }

  debugPrint('Unexpected fetchchecklist payload type: ${payload.runtimeType}');
  return [];
}
