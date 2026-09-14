import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Master Supabase client — ALL Firestore-migrated data.
/// Direct Supabase connection with service-key bypass for RLS tables.
class MasterSupabaseService {
  MasterSupabaseService._();

  static const String _masterUrl = 'https://ybiviymuxubvloqjngfu.supabase.co';
  static const String _masterAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InliaXZpeW11eHVidmxvcWpuZ2Z1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzNzI0MzksImV4cCI6MjEwNDk0ODQzOX0.2__dxf4r6cWnG5TLxqTymDLtFbP9fkZJzC8fkOY9VXc';
  static const String masterServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InliaXZpeW11eHVidmxvcWpuZ2Z1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4OTM3MjQzOSwiZXhwIjoyMTA0OTQ4NDM5fQ.kIoWInC-ZDNsPx6xpCACO0ee2Kfer7jMBRCtAQv_8gQ';

  static bool _initialized = false;
  static SupabaseClient? _client;
  static SupabaseClient? _serviceClient;

  static SupabaseClient get client {
    if (_client == null) throw StateError('MasterSupabaseService not initialized');
    return _client!;
  }

  static SupabaseClient get serviceClient {
    if (_serviceClient == null) throw StateError('MasterSupabaseService not initialized');
    return _serviceClient!;
  }

  static const _serviceTables = {'conversations', 'messages', 'notes', 'notices', 'student_activities', 'settings', 'app_updates', 'web_sessions'};

  static SupabaseClient _getClientFor(String table) =>
      _serviceTables.contains(table) ? serviceClient : client;

  static String get url => _masterUrl;
  static String get anonKey => _masterAnonKey;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      _client = SupabaseClient(_masterUrl, _masterAnonKey);
      _serviceClient = SupabaseClient(_masterUrl, masterServiceKey);
      _initialized = true;
      debugPrint('[MasterSupabase] Initialized (direct): $_masterUrl');
    } catch (e) {
      debugPrint('[MasterSupabase] Init failed: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> read(String table, {String? query}) async {
    try {
      final c = _getClientFor(table);
      var builder = c.from(table).select();
      if (query != null) {
        final parts = query.split('&');
        for (final part in parts) {
          final eqIdx = part.indexOf('=');
          if (eqIdx == -1) continue;
          final field = part.substring(0, eqIdx);
          final val = part.substring(eqIdx + 1);
          if (val.startsWith('eq.')) {
            builder = builder.eq(field, val.substring(3));
          } else if (val.startsWith('gt.')) {
            builder = builder.gt(field, val.substring(3));
          } else if (val.startsWith('lt.')) {
            builder = builder.lt(field, val.substring(3));
          } else if (val.startsWith('gte.')) {
            builder = builder.gte(field, val.substring(4));
          } else if (val.startsWith('lte.')) {
            builder = builder.lte(field, val.substring(4));
          } else if (val.startsWith('like.')) {
            builder = builder.like(field, val.substring(5));
          } else if (val.startsWith('in.(')) {
            final list = val.substring(4, val.length - 1).split(',');
            builder = builder.inFilter(field, list);
          } else if (val.startsWith('order=')) {
            final orderPart = val.substring(6);
            if (orderPart.endsWith('.desc')) {
              builder = builder.order(orderPart.substring(0, orderPart.length - 5), ascending: false);
            } else if (orderPart.endsWith('.asc')) {
              builder = builder.order(orderPart.substring(0, orderPart.length - 4), ascending: true);
            } else {
              builder = builder.order(orderPart);
            }
          } else if (val.startsWith('limit=')) {
            builder = builder.limit(int.parse(val.substring(6)));
          } else {
            builder = builder.eq(field, val);
          }
        }
      }
      final data = await builder.timeout(const Duration(seconds: 10));
      return (data as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[MasterSupabase] read($table) failed: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>?> readById(String table, String id) async {
    try {
      final c = _getClientFor(table);
      final data = await c.from(table).select().eq('id', id).maybeSingle();
      return data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[MasterSupabase] readById($table, $id) failed: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> readSingle(String table, {required String field, required String value}) async {
    try {
      final c = _getClientFor(table);
      final data = await c.from(table).select().eq(field, value).maybeSingle();
      return data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[MasterSupabase] readSingle($table) failed: $e');
      return null;
    }
  }

  static Future<bool> upsert(String table, Map<String, dynamic> data) async {
    try {
      final c = _getClientFor(table);
      await c.from(table).upsert(data).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] upsert($table) failed: $e');
      return false;
    }
  }

  static Future<String?> insert(String table, Map<String, dynamic> data) async {
    try {
      final c = _getClientFor(table);
      final result = await c.from(table).insert(data).select('id').single();
      return result['id'] as String?;
    } catch (e) {
      debugPrint('[MasterSupabase] insert($table) failed: $e');
      return null;
    }
  }

  static Future<bool> update(String table, String id, Map<String, dynamic> data) async {
    try {
      final c = _getClientFor(table);
      await c.from(table).update(data).eq('id', id).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] update($table, $id) failed: $e');
      return false;
    }
  }

  static Future<bool> delete(String table, String id) async {
    try {
      final c = _getClientFor(table);
      await c.from(table).delete().eq('id', id).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] delete($table, $id) failed: $e');
      return false;
    }
  }

  static Future<bool> deleteWhere(String table, {required String field, required String value}) async {
    try {
      final c = _getClientFor(table);
      await c.from(table).delete().eq(field, value).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] deleteWhere($table) failed: $e');
      return false;
    }
  }

  static Future<bool> updateWhere(String table, {required String filterField, required String filterValue, required Map<String, dynamic> data}) async {
    try {
      final c = _getClientFor(table);
      await c.from(table).update(data).eq(filterField, filterValue).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] updateWhere($table) failed: $e');
      return false;
    }
  }

  static Stream<List<Map<String, dynamic>>> stream(String table, {String? filterField, String? filterValue}) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    final c = _getClientFor(table);

    Future<void> fetch() async {
      try {
        var builder = c.from(table).select();
        if (filterField != null && filterValue != null) {
          builder = builder.eq(filterField, filterValue);
        }
        builder = builder.order('updated_at', ascending: false).limit(500);
        final data = await builder.timeout(const Duration(seconds: 10));
        controller.add((data as List<dynamic>).cast<Map<String, dynamic>>());
      } catch (e) {
        controller.add([]);
      }
    }

    fetch();

    final channel = c
        .channel('master_${table}_stream')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => fetch(),
        )
        .subscribe();

    controller.onCancel = () {
      c.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }
}
