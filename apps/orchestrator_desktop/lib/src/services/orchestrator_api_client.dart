import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/orchestrator_models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    if (statusCode == null) {
      return message;
    }
    return 'HTTP $statusCode: $message';
  }
}

class OrchestratorApiClient {
  OrchestratorApiClient({required String baseUrl, http.Client? client})
    : _baseUrl = _normalizeBaseUrl(baseUrl),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '';
    }
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$_baseUrl$path').replace(queryParameters: query);
  }

  Future<OrchestratorHealth> getHealth() async {
    final response = await _client.get(_uri('/health'));
    final body = _decodeObject(response);
    return OrchestratorHealth.fromJson(body);
  }

  Future<List<OrchestratorTask>> listTasks({int limit = 50}) async {
    final response = await _client.get(_uri('/tasks', {'limit': '$limit'}));
    final body = _decodeObject(response);
    final rawItems = body['items'];
    if (rawItems is! List) {
      throw ApiException('Response field "items" is not a list');
    }

    final items = <OrchestratorTask>[];
    for (final item in rawItems) {
      if (item is Map<String, dynamic>) {
        items.add(OrchestratorTask.fromJson(item));
      } else if (item is Map) {
        items.add(
          OrchestratorTask.fromJson(
            item.map((key, value) => MapEntry('$key', value)),
          ),
        );
      }
    }
    return items;
  }

  Future<OrchestratorTask> getTask(String taskId) async {
    final response = await _client.get(_uri('/tasks/$taskId'));
    final body = _decodeObject(response);
    return OrchestratorTask.fromJson(body);
  }

  Future<OrchestratorTask> createMinimalTask(CreateTaskRequest request) async {
    final response = await _client.post(
      _uri('/tasks/minimal'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    final body = _decodeObject(response);
    return OrchestratorTask.fromJson(body);
  }

  Future<OrchestratorTask> cancelTask(String taskId) async {
    final response = await _client.post(_uri('/tasks/$taskId/cancel'));
    final body = _decodeObject(response);
    return OrchestratorTask.fromJson(body);
  }

  Stream<TaskSseMessage> streamTaskEvents(String taskId) async* {
    final request = http.Request('GET', _uri('/tasks/$taskId/events'));
    request.headers['accept'] = 'text/event-stream';
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final payload = await response.stream.bytesToString();
      throw ApiException(
        _extractErrorMessage(payload),
        statusCode: response.statusCode,
      );
    }

    var eventName = 'message';
    final dataLines = <String>[];

    TaskSseMessage? readCurrentEvent() {
      if (dataLines.isEmpty) {
        eventName = 'message';
        return null;
      }

      final dataPayload = dataLines.join('\n');
      final currentEventName = eventName;
      eventName = 'message';
      dataLines.clear();

      try {
        final decoded = jsonDecode(dataPayload);
        if (decoded is Map<String, dynamic>) {
          return TaskSseMessage(eventName: currentEventName, data: decoded);
        }
        if (decoded is Map) {
          return TaskSseMessage(
            eventName: currentEventName,
            data: decoded.map((key, value) => MapEntry('$key', value)),
          );
        }
      } catch (_) {
        return null;
      }

      return null;
    }

    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in stream) {
      if (line.isEmpty) {
        final event = readCurrentEvent();
        if (event != null) {
          yield event;
        }
        continue;
      }
      if (line.startsWith(':')) {
        continue;
      }
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    final event = readCurrentEvent();
    if (event != null) {
      yield event;
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _extractErrorMessage(response.body),
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    throw ApiException('Response is not a JSON object');
  }

  String _extractErrorMessage(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      return 'Empty response';
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
      }
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return error.trim();
        }
      }
    } catch (_) {
      return trimmed;
    }
    return trimmed;
  }

  void close() {
    _client.close();
  }
}
