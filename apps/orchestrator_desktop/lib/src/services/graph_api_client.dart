import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/graph_editor_models.dart';

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

class GraphApiClient {
  GraphApiClient({required String baseUrl, http.Client? client})
    : _baseUrl = _normalizeBaseUrl(baseUrl),
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$_baseUrl$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> getHealth() async {
    final response = await _client.get(_uri('/health'));
    return _decodeObject(response);
  }

  Future<List<OrchestrationGraphModel>> listGraphs({int limit = 50}) async {
    final response = await _client.get(_uri('/graphs', {'limit': '$limit'}));
    final body = _decodeObject(response);
    final rawItems = body['items'];
    if (rawItems is! List) {
      throw ApiException('Response field "items" is not a list');
    }

    final items = <OrchestrationGraphModel>[];
    for (final item in rawItems) {
      final map = _asMap(item);
      if (map != null) {
        items.add(OrchestrationGraphModel.fromJson(map));
      }
    }
    return items;
  }

  Future<OrchestrationGraphModel> createGraph(
    GraphUpsertRequest request,
  ) async {
    final response = await _client.post(
      _uri('/graphs'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    return OrchestrationGraphModel.fromJson(_decodeObject(response));
  }

  Future<OrchestrationGraphModel> getGraph(
    String graphId, {
    int? revision,
  }) async {
    final query = <String, String>{};
    if (revision != null) {
      query['revision'] = '$revision';
    }

    final response = await _client.get(
      _uri('/graphs/$graphId', query.isEmpty ? null : query),
    );
    return OrchestrationGraphModel.fromJson(_decodeObject(response));
  }

  Future<OrchestrationGraphModel> updateGraph(
    String graphId,
    GraphUpsertRequest request,
  ) async {
    final response = await _client.put(
      _uri('/graphs/$graphId'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    return OrchestrationGraphModel.fromJson(_decodeObject(response));
  }

  Future<GraphValidationResultModel> validateGraph(
    String graphId, {
    int? graphRevision,
  }) async {
    final payload = <String, dynamic>{};
    if (graphRevision != null) {
      payload['graphRevision'] = graphRevision;
    }

    final response = await _client.post(
      _uri('/graphs/$graphId/validate'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(payload),
    );
    return GraphValidationResultModel.fromJson(_decodeObject(response));
  }

  Future<List<GraphRunModel>> listGraphRuns(
    String graphId, {
    int limit = 50,
  }) async {
    final response = await _client.get(
      _uri('/graphs/$graphId/runs', {'limit': '$limit'}),
    );
    final body = _decodeObject(response);
    final rawItems = body['items'];
    if (rawItems is! List) {
      throw ApiException('Response field "items" is not a list');
    }

    final items = <GraphRunModel>[];
    for (final item in rawItems) {
      final map = _asMap(item);
      if (map != null) {
        items.add(GraphRunModel.fromJson(map));
      }
    }
    return items;
  }

  Future<GraphRunModel> createGraphRun(
    String graphId, {
    int? graphRevision,
    String? kickoffMessage,
    String? kickoffManagerNodeId,
  }) async {
    final payload = <String, dynamic>{};
    if (graphRevision != null) {
      payload['graphRevision'] = graphRevision;
    }
    if (kickoffMessage != null && kickoffMessage.trim().isNotEmpty) {
      payload['kickoffMessage'] = kickoffMessage.trim();
    }
    if (kickoffManagerNodeId != null && kickoffManagerNodeId.trim().isNotEmpty) {
      payload['kickoffManagerNodeId'] = kickoffManagerNodeId.trim();
    }

    final response = await _client.post(
      _uri('/graphs/$graphId/runs'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(payload),
    );
    return GraphRunModel.fromJson(_decodeObject(response));
  }

  Future<GraphRunModel> getGraphRun(String runId) async {
    final response = await _client.get(_uri('/graph-runs/$runId'));
    return GraphRunModel.fromJson(_decodeObject(response));
  }

  Future<GraphRunModel> cancelGraphRun(String runId) async {
    final response = await _client.post(_uri('/graph-runs/$runId/cancel'));
    return GraphRunModel.fromJson(_decodeObject(response));
  }

  Future<List<NodeChatMessageModel>> listNodeMessages(
    String nodeId, {
    String? graphId,
    int limit = 200,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (graphId != null && graphId.trim().isNotEmpty) {
      query['graphId'] = graphId.trim();
    }

    final response = await _client.get(_uri('/nodes/$nodeId/messages', query));
    final body = _decodeObject(response);
    final rawItems = body['items'];
    if (rawItems is! List) {
      throw ApiException('Response field "items" is not a list');
    }

    final items = <NodeChatMessageModel>[];
    for (final item in rawItems) {
      final map = _asMap(item);
      if (map != null) {
        items.add(NodeChatMessageModel.fromJson(map));
      }
    }
    return items;
  }

  Future<List<NodeLogEntryModel>> listNodeLogs(
    String nodeId, {
    String? graphId,
    String? runId,
    int limit = 300,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (graphId != null && graphId.trim().isNotEmpty) {
      query['graphId'] = graphId.trim();
    }
    if (runId != null && runId.trim().isNotEmpty) {
      query['runId'] = runId.trim();
    }

    final response = await _client.get(_uri('/nodes/$nodeId/logs', query));
    final body = _decodeObject(response);
    final rawItems = body['items'];
    if (rawItems is! List) {
      throw ApiException('Response field "items" is not a list');
    }

    final items = <NodeLogEntryModel>[];
    for (final item in rawItems) {
      final map = _asMap(item);
      if (map != null) {
        items.add(NodeLogEntryModel.fromJson(map));
      }
    }
    return items;
  }

  Future<NodeChatResponseModel> sendNodeMessage(
    String nodeId,
    NodeChatRequestModel request,
  ) async {
    final response = await _client.post(
      _uri('/nodes/$nodeId/chat'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    return NodeChatResponseModel.fromJson(_decodeObject(response));
  }

  Stream<GraphSseMessage> streamRunEvents(String runId) async* {
    final request = http.Request('GET', _uri('/graph-runs/$runId/events'));
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

    GraphSseMessage? readCurrentEvent() {
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
        final map = _asMap(decoded);
        if (map != null) {
          return GraphSseMessage(eventName: currentEventName, data: map);
        }
      } catch (_) {
        return null;
      }

      return null;
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
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
    final map = _asMap(decoded);
    if (map != null) {
      return map;
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
      final map = _asMap(decoded);
      if (map != null) {
        final error = map['error'];
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

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry('$key', mapValue));
    }
    return null;
  }
}
