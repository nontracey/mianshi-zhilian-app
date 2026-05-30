import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ticket.dart';
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
  }) async {
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
    final apiUrl = _getApiUrl?.call();
    final token = _getToken?.call();
    if (apiUrl != null && token != null) {
      try {
        final response = await http.post(
          Uri.parse('$apiUrl/tickets'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(ticket.toJson()),
        );
        if (response.statusCode == 200) {
          debugPrint('Ticket synced to server');
        }
      } catch (e) {
        debugPrint('Failed to sync ticket: $e');
      }
    }

    return ticket;
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
}
