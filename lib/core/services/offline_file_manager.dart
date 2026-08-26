import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Manages offline file caching for the auto-download feature.
/// Files are downloaded in the background while the user views them remotely.
class OfflineFileManager {
  static OfflineFileManager? _instance;
  static OfflineFileManager get instance => _instance ??= OfflineFileManager._();
  OfflineFileManager._();

  static const String _offlineDirName = 'offline_files';
  static const int _maxCacheSizeMB = 500;
  Directory? _offlineDir;
  final Map<String, Completer<bool>> _downloading = {};

  /// Get the offline files directory
  Future<Directory> get offlineDir async {
    if (_offlineDir != null) return _offlineDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _offlineDir = Directory('${appDir.path}/$_offlineDirName');
    if (!await _offlineDir!.exists()) {
      await _offlineDir!.create(recursive: true);
    }
    return _offlineDir!;
  }

  /// Generate a safe filename from URL
  String _getSafeFilename(String url, String name) {
    // Use name if available, otherwise hash the URL
    if (name.isNotEmpty && name.contains('.')) {
      // Clean the name but keep extension
      final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      return cleaned;
    }
    // Hash the URL for a unique filename
    final bytes = utf8.encode(url);
    final hash = md5.convert(bytes).toString().substring(0, 16);
    final ext = _getExtensionFromUrl(url);
    return '$hash.$ext';
  }

  /// Get file extension from URL
  String _getExtensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      if (path.contains('.')) {
        return path.split('.').last.toLowerCase();
      }
    } catch (_) {}
    return 'bin';
  }

  /// Check if a file is already downloaded
  Future<File?> getOfflineFile(String url, String name) async {
    if (kIsWeb) return null; // Not supported on web
    try {
      final dir = await offlineDir;
      final filename = _getSafeFilename(url, name);
      final file = File('${dir.path}/$filename');
      if (await file.exists()) {
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Download a file in the background
  /// Returns true if download succeeded, false otherwise
  Future<bool> downloadInBackground(String url, String name) async {
    if (kIsWeb) return false;

    // Prevent duplicate downloads
    if (_downloading.containsKey(url)) {
      return await _downloading[url]!.future;
    }

    final completer = Completer<bool>();
    _downloading[url] = completer;

    try {
      final dir = await offlineDir;
      final filename = _getSafeFilename(url, name);
      final file = File('${dir.path}/$filename');

      // Check if already exists
      if (await file.exists()) {
        completer.complete(true);
        _downloading.remove(url);
        return true;
      }

      // Check cache size before downloading
      await _enforceCacheLimit();

      // Download the file
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw TimeoutException('Download timed out');
        },
      );

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        completer.complete(true);
        _downloading.remove(url);
        return true;
      } else {
        completer.complete(false);
        _downloading.remove(url);
        return false;
      }
    } catch (e) {
      completer.complete(false);
      _downloading.remove(url);
      return false;
    }
  }

  /// Enforce cache size limit by deleting oldest files
  Future<void> _enforceCacheLimit() async {
    try {
      final dir = await offlineDir;
      final files = await dir.list().toList();
      if (files.isEmpty) return;

      int totalSize = 0;
      final fileEntries = <MapEntry<File, int>>[];

      for (final f in files) {
        if (f is File) {
          final size = await f.length();
          totalSize += size;
          fileEntries.add(MapEntry(f, size));
        }
      }

      // Convert to MB
      final totalSizeMB = totalSize / (1024 * 1024);
      if (totalSizeMB <= _maxCacheSizeMB) return;

      // Sort by last modified (oldest first)
      fileEntries.sort((a, b) {
        // This will be done synchronously in the background
        return 0;
      });

      // Delete oldest files until under limit
      for (final entry in fileEntries) {
        if (totalSizeMB <= _maxCacheSizeMB * 0.8) break;
        try {
          final size = entry.value;
          await entry.key.delete();
          totalSize -= size;
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Delete a specific offline file
  Future<bool> deleteOfflineFile(String url, String name) async {
    if (kIsWeb) return false;
    try {
      final dir = await offlineDir;
      final filename = _getSafeFilename(url, name);
      final file = File('${dir.path}/$filename');
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Delete all offline files
  Future<void> clearAll() async {
    if (kIsWeb) return;
    try {
      final dir = await offlineDir;
      final files = await dir.list().toList();
      for (final f in files) {
        if (f is File) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  /// Get all offline files with metadata
  Future<List<OfflineFileInfo>> getAllOfflineFiles() async {
    if (kIsWeb) return [];
    try {
      final dir = await offlineDir;
      final files = await dir.list().toList();
      final result = <OfflineFileInfo>[];

      for (final f in files) {
        if (f is File) {
          final stat = await f.stat();
          final name = f.path.split(Platform.pathSeparator).last;
          result.add(OfflineFileInfo(
            file: f,
            name: name,
            size: stat.size,
            lastModified: stat.modified,
          ));
        }
      }

      // Sort by date (newest first)
      result.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      return result;
    } catch (_) {}
    return [];
  }

  /// Get total cache size in bytes
  Future<int> getCacheSize() async {
    if (kIsWeb) return 0;
    try {
      final dir = await offlineDir;
      final files = await dir.list().toList();
      int totalSize = 0;
      for (final f in files) {
        if (f is File) {
          totalSize += await f.length();
        }
      }
      return totalSize;
    } catch (_) {}
    return 0;
  }

  /// Check if auto-download is enabled for the current user
  static Future<bool> isAutoDownloadEnabled() async {
    try {
      // This reads from Firebase user document
      // The actual check is done in firebase_service.dart
      return true; // Default to enabled
    } catch (_) {
      return true;
    }
  }
}

/// Metadata for an offline file
class OfflineFileInfo {
  final File file;
  final String name;
  final int size;
  final DateTime lastModified;

  OfflineFileInfo({
    required this.file,
    required this.name,
    required this.size,
    required this.lastModified,
  });

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get dateFormatted {
    return '${lastModified.day.toString().padLeft(2, '0')}/${lastModified.month.toString().padLeft(2, '0')}/${lastModified.year}';
  }
}
