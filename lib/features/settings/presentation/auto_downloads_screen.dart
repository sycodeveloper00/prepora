import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

class AutoDownloadsScreen extends StatefulWidget {
  const AutoDownloadsScreen({super.key});
  @override
  State<AutoDownloadsScreen> createState() => _AutoDownloadsScreenState();
}

class _FileEntry {
  final File file;
  final String name;
  final String size;
  final DateTime date;
  _FileEntry(this.file, this.name, this.size, this.date);
}

class _AutoDownloadsScreenState extends State<AutoDownloadsScreen> {
  List<_FileEntry> _files = [];
  bool _isLoading = true;
  String _totalSize = '';

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/offline_files');
      if (!await cacheDir.exists()) {
        setState(() { _files = []; _isLoading = false; _totalSize = '0 KB'; });
        return;
      }
      final rawFiles = (await cacheDir.list().toList()).whereType<File>().toList();
      final entries = <_FileEntry>[];
      int totalBytes = 0;
      for (final f in rawFiles) {
        final name = f.path.split(Platform.pathSeparator).last;
        final sizeBytes = await f.length();
        final date = await f.lastModified();
        totalBytes += sizeBytes;
        entries.add(_FileEntry(f, name, _formatSize(sizeBytes), date));
      }
      entries.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _files = entries;
        _isLoading = false;
        _totalSize = _formatSize(totalBytes);
      });
    } catch (e) {
      setState(() { _files = []; _isLoading = false; _totalSize = '0 KB'; });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  Future<void> _deleteFile(File file) async {
    try {
      await file.delete();
      _loadFiles();
    } catch (_) {}
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0533),
        title: const Text('Delete All Files?', style: TextStyle(color: Colors.white)),
        content: const Text('This will remove all cached offline files.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete All', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/offline_files');
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      _loadFiles();
    } catch (_) {}
  }

  String _getFileType(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['pdf'].contains(ext)) return 'PDF';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return 'Image';
    if (['mp4', 'avi', 'mkv', 'mov'].contains(ext)) return 'Video';
    if (['mp3', 'wav', 'aac', 'ogg'].contains(ext)) return 'Audio';
    if (['doc', 'docx'].contains(ext)) return 'Document';
    return 'File';
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf_rounded;
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Icons.image_rounded;
    if (['mp4', 'avi', 'mkv', 'mov'].contains(ext)) return Icons.video_file_rounded;
    if (['mp3', 'wav', 'aac', 'ogg'].contains(ext)) return Icons.audio_file_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['pdf'].contains(ext)) return Colors.redAccent;
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Colors.blueAccent;
    if (['mp4', 'avi', 'mkv', 'mov'].contains(ext)) return Colors.purpleAccent;
    if (['mp3', 'wav', 'aac', 'ogg'].contains(ext)) return Colors.orangeAccent;
    return Colors.tealAccent;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white54 : Colors.black45;
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text('Downloaded Files', style: TextStyle(color: textColor)),
        backgroundColor: isDark ? const Color(0xFF0D0221) : const Color(0xFFF5F5F5),
        iconTheme: IconThemeData(color: textColor),
        actions: [
          if (_files.isNotEmpty)
            IconButton(
              onPressed: _deleteAll,
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              tooltip: 'Delete All',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C4DFF)))
          : _files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_download_rounded, size: 64, color: hintColor.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('No downloaded files', style: TextStyle(color: hintColor, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Files will appear here after opening', style: TextStyle(color: hintColor.withValues(alpha: 0.6), fontSize: 13)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.storage_rounded, size: 18, color: hintColor),
                          const SizedBox(width: 8),
                          Text('${_files.length} files  •  $_totalSize', style: TextStyle(color: hintColor, fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _files.length,
                        itemBuilder: (context, index) {
                          final entry = _files[index];
                          final name = entry.name;
                          final size = entry.size;
                          final date = entry.date;
                          final type = _getFileType(name);
                          final icon = _getFileIcon(name);
                          final color = _getFileColor(name);

                          return Card(
                            color: cardColor,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              leading: Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(icon, color: color, size: 22),
                              ),
                              title: Text(
                                name,
                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$type  •  $size  •  ${date.day}/${date.month}/${date.year}',
                                style: TextStyle(color: hintColor, fontSize: 11),
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(Icons.more_vert, color: hintColor, size: 18),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'open', child: Row(children: [Icon(Icons.open_in_new, size: 16), SizedBox(width: 8), Text('Open')])),
                                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.redAccent), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.redAccent))])),
                                ],
                                onSelected: (val) async {
                                  if (val == 'open') {
                                    final path = entry.file.path;
                                    final ext = path.split('.').last.toLowerCase();
                                    if (['pdf'].contains(ext)) {
                                      if (mounted) context.push('/pdf_reader/view', extra: {'url': path});
                                    } else if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
                                      if (mounted) context.push('/image_viewer', extra: {'url': path, 'title': entry.name});
                                    } else if (['mp4', 'avi', 'mkv', 'mov'].contains(ext)) {
                                      if (mounted) context.push('/media_player', extra: {'url': path, 'title': entry.name, 'isAudio': false});
                                    } else if (['mp3', 'wav', 'aac', 'ogg'].contains(ext)) {
                                      if (mounted) context.push('/media_player', extra: {'url': path, 'title': entry.name, 'isAudio': true});
                                    }
                                  } else if (val == 'delete') {
                                    _deleteFile(entry.file);
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
