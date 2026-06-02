import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ticket.dart';
import 'api_headers.dart';
import 'storage_service.dart';

class TicketService {
  final StorageService _storage;
  final String? Function()? _getApiUrl;
  final String? Function()? _getToken;

  TicketService({
    required StorageService storage,
    String? Function()? getApiUrl,
    String? Function()? getToken,
  })  : _storage = storage,
        _getApiUrl = getApiUrl,
        _getToken = getToken;

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
    final apiUrl = _getApiUrl?.call();
    final token = _getToken?.call();
    if (type == 'password_reset' && apiUrl != null) {
      final response = await http.post(
        Uri.parse('$apiUrl/tickets/password-reset'),
        headers: await ApiHeaders.build(_storage),
        body: json.encode({
          'account_username': _sanitize(subject),
          'contact': _sanitize(contact ?? ''),
          'description': _sanitize(description),
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
    if (apiUrl != null && token != null) {
      try {
        final response = await http.post(
          Uri.parse('$apiUrl/tickets'),
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
          final remoteTicket =
              Ticket.fromJson(data['ticket'] as Map<String, dynamic>);
          await _replaceTicket(ticket.id, remoteTicket);
          await _storage.recordAnalyticsFeature('ticket_submit');
          return remoteTicket;
        }
      } catch (e) {
        debugPrint('Failed to sync ticket: $e');
      }
    }

    return ticket;
  }

  Future<List<Ticket>> getTickets() async {
    final apiUrl = _getApiUrl?.call();
    final token = _getToken?.call();
    if (apiUrl != null && token != null) {
      try {
        final response = await http.get(
          Uri.parse('$apiUrl/tickets'),
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
