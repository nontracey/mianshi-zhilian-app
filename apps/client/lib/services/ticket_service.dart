import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/ticket.dart';
import 'api_headers.dart';
import 'app_log_service.dart';
import 'endpoint_fallback_client.dart';
import 'route_resolver.dart';
import 'route_state_store.dart';
import 'storage_service.dart';

class TicketService {
  final StorageService _storage;
  final String? Function()? _getToken;
  final EndpointFallbackClient _routeClient;

  TicketService({
    required StorageService storage,
    String? Function()? getApiUrl,
    String? Function()? getToken,
    EndpointFallbackClient? routeClient,
  }) : _storage = storage,
       _getToken = getToken,
       _routeClient =
           routeClient ??
           EndpointFallbackClient(stateStore: RouteStateStore(storage));

  /// 防注入：清理用户输入
  String _sanitize(String input) {
    return input
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>'), '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'javascript:'), '')
        .trim();
  }

  /// 提交工单
  Future<Ticket> submitTicket({
    required String type,
    required String subject,
    required String description,
    List<String> imageUrls = const [],
    String? contact,
  }) async {
    final token = _getToken?.call();
    if (type == 'password_reset') {
      final response = await _routeClient.request(
        RouteService.appApi,
        'POST',
        '/tickets/password-reset',
        headers: await ApiHeaders.build(_storage),
        body: json.encode({
          'account_username': _sanitize(subject),
          'contact': _sanitize(contact ?? ''),
          'description': _sanitize(description),
          'image_urls': imageUrls,
        }),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final ticket = Ticket.fromJson(data['ticket'] as Map<String, dynamic>);
        await _saveTicketLocally(ticket);
        await _storage.recordAnalyticsFeature('ticket_submit');
        return ticket;
      }
    }

    final ticket = Ticket(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: 'local',
      type: type,
      subject: _sanitize(subject),
      description: _sanitize(description),
      imageUrls: imageUrls,
      createdAt: DateTime.now(),
    );

    // 保存到本地
    await _saveTicketLocally(ticket);

    // 尝试同步到服务器
    if (token != null) {
      try {
        final response = await _routeClient.request(
          RouteService.appApi,
          'POST',
          '/tickets',
          headers: await ApiHeaders.build(_storage, token: token),
          body: json.encode({
            'type': ticket.type,
            'subject': ticket.subject,
            'description': ticket.description,
            'image_urls': ticket.imageUrls,
          }),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final remoteTicket = Ticket.fromJson(
            data['ticket'] as Map<String, dynamic>,
          );
          await _replaceTicket(ticket.id, remoteTicket);
          await _storage.recordAnalyticsFeature('ticket_submit');
          return remoteTicket;
        }
      } catch (e) {
        debugPrint('Failed to sync ticket: $e');
        unawaited(
          AppLog.warning(
            'Ticket sync failed: $type',
            source: 'ticket',
            error: e,
          ),
        );
      }
    }

    return ticket;
  }

  Future<List<Ticket>> getTickets() async {
    final token = _getToken?.call();
    if (token != null) {
      try {
        final response = await _routeClient.request(
          RouteService.appApi,
          'GET',
          '/tickets',
          headers: await ApiHeaders.build(_storage, token: token, json: false),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final tickets = (data['tickets'] as List<dynamic>)
              .map((e) => Ticket.fromJson(e as Map<String, dynamic>))
              .toList();
          await _storage.saveJsonList(
            'tickets',
            tickets.map((t) => t.toJson()).toList(),
          );
          return tickets;
        }
      } catch (e) {
        debugPrint('Failed to fetch tickets: $e');
        unawaited(
          AppLog.warning('Fetch tickets failed', source: 'ticket', error: e),
        );
      }
    }
    return getLocalTickets();
  }

  /// 获取本地工单列表
  Future<List<Ticket>> getLocalTickets() async {
    final data = await _storage.loadJsonList('tickets');
    return data.map((e) => Ticket.fromJson(e)).toList();
  }

  /// 保存工单到本地
  Future<void> _saveTicketLocally(Ticket ticket) async {
    final tickets = await getLocalTickets();
    tickets.add(ticket);
    await _storage.saveJsonList(
      'tickets',
      tickets.map((t) => t.toJson()).toList(),
    );
  }

  Future<void> _replaceTicket(String localId, Ticket remoteTicket) async {
    final tickets = await getLocalTickets();
    final index = tickets.indexWhere((t) => t.id == localId);
    if (index >= 0) {
      tickets[index] = remoteTicket;
    } else {
      tickets.add(remoteTicket);
    }
    await _storage.saveJsonList(
      'tickets',
      tickets.map((t) => t.toJson()).toList(),
    );
  }
}
