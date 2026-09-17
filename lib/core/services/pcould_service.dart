import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class PCouldService {
  static const String _baseUrl = 'https://api.pcloud.com';

  static Future<Map<String, dynamic>> verifyToken({required String authToken}) async {
    try {
      final uri = Uri.parse('$_baseUrl/userinfo?getauth=1');
      final response = await http.post(uri, body: {
        'auth': authToken,
      }).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['result'] == 0) {
        return {
          'valid': true,
          'email': body['email'] as String? ?? '',
          'quota': body['quota'] as int? ?? 0,
          'usedQuota': body['usedquota'] as int? ?? 0,
          'premium': body['premium'] as bool? ?? false,
        };
      }
      return {'valid': false, 'error': body['error'] as String? ?? 'Authentication failed'};
    } catch (e) {
      return {'valid': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getUserInfo({required String authToken}) async {
    try {
      final uri = Uri.parse('$_baseUrl/userinfo');
      final response = await http.post(uri, body: {
        'auth': authToken,
      }).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['result'] == 0) {
        return {
          'quota': body['quota'] as int? ?? 0,
          'usedQuota': body['usedquota'] as int? ?? 0,
          'email': body['email'] as String? ?? '',
        };
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<String> uploadFile({
    required String authToken,
    required Uint8List bytes,
    required String filename,
    String? folderPath,
  }) async {
    final uri = Uri.parse('$_baseUrl/uploadfile');
    final request = http.MultipartRequest('POST', uri);
    request.fields['auth'] = authToken;
    if (folderPath != null && folderPath.isNotEmpty) {
      request.fields['path'] = folderPath;
    }
    request.fields['renameifexists'] = '1';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(const Duration(minutes: 15));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('pCloud upload failed: ${streamed.statusCode} $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['result'] != 0) {
        final err = decoded['error'] as String? ?? 'Unknown error';
        throw Exception('pCloud upload failed: $err');
      }
      final fileIds = decoded['fileids'] as List<dynamic>?;
      final metadata = decoded['metadata'] as List<dynamic>?;
      if (metadata != null && metadata.isNotEmpty) {
        final file = metadata[0] as Map<String, dynamic>;
        final fileId = file['fileid'] as int? ?? (fileIds?.isNotEmpty == true ? fileIds!.first as int : 0);
        return fileId.toString();
      }
      if (fileIds != null && fileIds.isNotEmpty) {
        return fileIds.first.toString();
      }
      throw Exception('No file ID returned from pCloud');
    } finally {
      client.close();
    }
  }

  static Future<String> getDownloadUrl({
    required String authToken,
    required String fileId,
  }) async {
    final uri = Uri.parse('$_baseUrl/getfilelink');
    final response = await http.post(uri, body: {
      'auth': authToken,
      'fileid': fileId,
    }).timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['result'] == 0) {
      final hosts = body['hosts'] as List<dynamic>?;
      final path = body['path'] as String? ?? '';
      if (hosts != null && hosts.isNotEmpty && path.isNotEmpty) {
        final host = hosts[0] as String;
        return 'https://$host$path';
      }
    }
    throw Exception('Failed to get pCloud download URL');
  }

  static Future<String> getPublicLink({
    required String authToken,
    required String fileId,
  }) async {
    final uri = Uri.parse('$_baseUrl/getfilepublink');
    final response = await http.post(uri, body: {
      'auth': authToken,
      'fileid': fileId,
    }).timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['result'] == 0) {
      final link = body['link'] as String? ?? '';
      if (link.isNotEmpty) return link;
      final code = body['code'] as String? ?? '';
      if (code.isNotEmpty) return 'https://u.pcloud.link/publink/show?code=$code';
    }
    throw Exception('Failed to get pCloud public link');
  }

  static Future<List<Map<String, dynamic>>> listFiles({
    required String authToken,
    String? folderPath,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/listfolder');
      final response = await http.post(uri, body: {
        'auth': authToken,
        if (folderPath != null) 'path': folderPath,
      }).timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['result'] == 0) {
        final contents = body['contents'] as List<dynamic>? ?? [];
        return contents
            .where((f) => f['isfolder'] != true)
            .map((f) => {
              'fileId': f['fileid'],
              'name': f['name'],
              'size': f['size'],
              'modified': f['modified'],
            })
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static bool isPCloudLink(String url) {
    return url.contains('pcloud.com') || url.contains('u.pcloud.link');
  }

  static String? extractFileId(String url) {
    final match = RegExp(r'pcloud\.com/download/(\d+)').firstMatch(url);
    if (match != null) return match.group(1);
    return null;
  }

  static String getProxyDownloadUrl({required String fileId, String? fileName}) {
    final base = 'https://prepora-web.vercel.app/api/pcloud-proxy';
    final params = <String, String>{'fileId': fileId};
    if (fileName != null && fileName.isNotEmpty) params['fileName'] = fileName;
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return '$base?$query';
  }

  static Future<Map<String, dynamic>> resolveShareLink(String url) async {
    try {
      final uri = Uri.parse('https://prepora-web.vercel.app/api/pcloud-resolve');
      final response = await http.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      ).timeout(const Duration(seconds: 30));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
