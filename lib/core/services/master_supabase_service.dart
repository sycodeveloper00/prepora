import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Master Supabase client — ALL Firestore-migrated data.
/// Reads/writes go through Vercel proxy (service key hidden server-side).
/// Only realtime subscriptions use direct Supabase (anon key — safe for public).
class MasterSupabaseService {
  MasterSupabaseService._();

  static const String _masterUrl = 'https://ybiviymuxubvloqjngfu.supabase.co';
  static const String _masterAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InliaXZpeW11eHVidmxvcWpuZ2Z1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzNzI0MzksImV4cCI6MjEwNDk0ODQzOX0.2__dxf4r6cWnG5TLxqTymDLtFbP9fkZJzC8fkOY9VXc';

  static bool _initialized = false;
  static SupabaseClient? _client;

  static SupabaseClient get client {
    if (_client == null) throw StateError('MasterSupabaseService not initialized');
    return _client!;
  }

  static String get url => _masterUrl;
  static String get anonKey => _masterAnonKey;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      _client = SupabaseClient(_masterUrl, _masterAnonKey);
      _initialized = true;
      debugPrint('[MasterSupabase] Initialized via proxy: $_masterUrl');
    } catch (e) {
      debugPrint('[MasterSupabase] Init failed: $e');
    }
  }

  // ─── Proxy helpers ────────────────────────────────────────────────────────

  /// Read proxy secret from Hive cache (populated by SupabaseReadService.loadProxySecret)
  static String get _proxySecret {
    try {
      final box = Hive.box('settings');
      return (box.get('proxy_secret') as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<List<Map<String, dynamic>>> _proxyRead(String table, String query) async {
    try {
      final res = await http.post(
        Uri.parse('https://prepora-web.vercel.app/api/proxy-read'),
        headers: {
          'Content-Type': 'application/json',
          'X-Proxy-Secret': _proxySecret,
        },
        body: json.encode({'table': table, 'query': query, 'target': 'master'}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final json_ = json.decode(res.body);
        final rows = json_['data'] as List<dynamic>?;
        if (rows != null) return rows.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[MasterSupabase] proxyRead($table) failed: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> _proxyWrite(String table, {String? id, Map<String, dynamic>? data, bool delete = false}) async {
    try {
      final body = <String, dynamic>{'table': table, 'target': 'master'};
      if (id != null) body['id'] = id;
      if (data != null) body['data'] = data;
      if (delete) body['delete'] = true;
      final res = await http.post(
        Uri.parse('https://prepora-web.vercel.app/api/proxy-write'),
        headers: {
          'Content-Type': 'application/json',
          'X-Proxy-Secret': _proxySecret,
        },
        body: json.encode(body),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final json_ = json.decode(res.body);
        if (json_['success'] == true) {
          final resultData = json_['data'];
          if (resultData is List && resultData.isNotEmpty) return resultData.first as Map<String, dynamic>;
          if (resultData is Map) return resultData as Map<String, dynamic>;
          return {'ok': true};
        }
      }
    } catch (e) {
      debugPrint('[MasterSupabase] proxyWrite($table) failed: $e');
    }
    return null;
  }

  // ─── Generic CRUD via proxy ───────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> read(String table, {String? query}) async {
    return _proxyRead(table, query ?? 'limit=5000');
  }

  static Future<Map<String, dynamic>?> readById(String table, String id) async {
    final rows = await _proxyRead(table, 'id=eq.$id&limit=1');
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> readSingle(String table, {required String field, required String value}) async {
    final rows = await _proxyRead(table, '$field=eq.$value&limit=1');
    return rows.isEmpty ? null : rows.first;
  }

  static Future<String?> insert(String table, Map<String, dynamic> data) async {
    final result = await _proxyWrite(table, data: data);
    return result?['id'] as String?;
  }

  static Future<bool> upsert(String table, Map<String, dynamic> data) async {
    final result = await _proxyWrite(table, id: data['id'] as String?, data: data);
    return result != null;
  }

  static Future<bool> update(String table, String id, Map<String, dynamic> data) async {
    final result = await _proxyWrite(table, id: id, data: data);
    return result != null;
  }

  static Future<bool> delete(String table, String id) async {
    final result = await _proxyWrite(table, id: id, delete: true);
    return result != null;
  }

  static Future<bool> deleteWhere(String table, {required String field, required String value}) async {
    final rows = await _proxyRead(table, '$field=eq.$value&limit=500');
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id != null) await delete(table, id);
    }
    return true;
  }

  static Future<bool> updateWhere(String table, {required String filterField, required String filterValue, required Map<String, dynamic> data}) async {
    final rows = await _proxyRead(table, '$filterField=eq.$filterValue&limit=500');
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id != null) await update(table, id, data);
    }
    return true;
  }

  // ─── Stream: realtime via direct Supabase (anon key — safe) ───────────────

  static Stream<List<Map<String, dynamic>>> stream(String table, {String? filterField, String? filterValue}) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> fetch() async {
      final rows = await _proxyRead(table, filterField != null && filterValue != null
          ? '$filterField=eq.$filterValue&order=updated_at.desc&limit=500'
          : 'order=updated_at.desc&limit=500');
      controller.add(rows);
    }

    fetch();

    final channel = client
        .channel('master_${table}_stream')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => fetch(),
        )
        .subscribe();

    controller.onCancel = () {
      client.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }
}
