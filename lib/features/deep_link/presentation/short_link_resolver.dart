import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/supabase_read_service.dart';

class ShortLinkResolver extends StatefulWidget {
  final String shortId;
  const ShortLinkResolver({super.key, required this.shortId});

  @override
  State<ShortLinkResolver> createState() => _ShortLinkResolverState();
}

class _ShortLinkResolverState extends State<ShortLinkResolver> {
  @override
  void initState() {
    super.initState();
    _resolve();
  }

  String _extractYoutubeId(String url) {
    if (url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    }
    return uri.queryParameters['v'] ?? '';
  }

  Future<List<String>> _resolveParentChain(String folderId, String contentId) async {
    final chain = <String>[];
    try {
      var currentId = contentId;
      final visited = <String>{};
      while (currentId.isNotEmpty && !visited.contains(currentId)) {
        visited.add(currentId);
        final content = await SupabaseReadService.getContent(folderId, currentId)
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
        if (content == null) break;
        final parentId = content['parentContentId'] as String?;
        if (parentId != null && parentId.isNotEmpty) {
          chain.add(parentId);
          currentId = parentId;
        } else {
          break;
        }
      }
    } catch (_) {}
    return chain.reversed.toList();
  }

  Future<void> _resolve() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      context.go('/auth/login');
      return;
    }

    try {
      final link = await SupabaseReadService.getShareLinkByShortId(widget.shortId)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (link == null || !mounted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share link not found or expired'), backgroundColor: Colors.redAccent),
        );
        context.go('/dashboard');
        return;
      }

      final contentId = link['content_id'] as String? ?? '';
      final contentType = link['content_type'] as String? ?? 'folder';
      final folderId = link['folder_id'] as String? ?? '';

      if (!mounted) return;

      final navDelay = const Duration(milliseconds: 150);

      if (contentType == 'folder') {
        context.go('/dashboard');
        await Future.delayed(navDelay);
        if (!mounted) return;
        context.push('/folders/$contentId', extra: {'canEdit': false, 'canManage': false});
      } else if (contentType == 'subfolder') {
        final parentChain = await _resolveParentChain(folderId, contentId);
        if (!mounted) return;
        context.go('/dashboard');
        await Future.delayed(navDelay);
        if (!mounted) return;
        context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
        for (final parentId in parentChain) {
          if (!mounted) return;
          await Future.delayed(navDelay);
          context.push('/folders/$folderId/sub/$parentId', extra: {'canEdit': false, 'canManage': false});
        }
        if (!mounted) return;
        await Future.delayed(navDelay);
        context.push('/folders/$folderId/sub/$contentId', extra: {'canEdit': false, 'canManage': false});
      } else {
        final content = await SupabaseReadService.getContent(folderId, contentId)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (content == null || !mounted) {
          context.go('/dashboard');
          await Future.delayed(navDelay);
          if (!mounted) return;
          context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
          return;
        }

        final type = content['type'] as String? ?? 'file';
        final name = content['name'] as String? ?? '';
        final url = content['url'] as String? ?? '';
        final youtubeUrl = content['youtubeUrl'] as String? ?? '';
        final immediateParentId = content['parentContentId'] as String?;

        context.go('/dashboard');
        await Future.delayed(navDelay);
        if (!mounted) return;

        if (immediateParentId != null && immediateParentId.isNotEmpty) {
          final parentChain = await _resolveParentChain(folderId, immediateParentId);
          if (!mounted) return;
          context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
          for (final parentId in parentChain) {
            if (!mounted) return;
            await Future.delayed(navDelay);
            context.push('/folders/$folderId/sub/$parentId', extra: {'canEdit': false, 'canManage': false});
          }
        } else {
          context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
        }

        if (!mounted) return;
        await Future.delayed(navDelay);

        switch (type) {
          case 'lecture':
            final videoId = _extractYoutubeId(youtubeUrl);
            if (videoId.isNotEmpty) {
              context.push('/lectures/$videoId', extra: {
                'name': name, 'folderId': folderId, 'parentContentId': immediateParentId,
              });
            } else if (immediateParentId != null) {
              context.push('/folders/$folderId/sub/$immediateParentId', extra: {'canEdit': false, 'canManage': false});
            } else {
              context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          case 'mocktest_url':
            if (url.isNotEmpty) {
              context.push('/webview', extra: {
                'url': url, 'title': name, 'folderId': folderId,
                'parentContentId': immediateParentId, 'isMockTest': true,
              });
            } else {
              context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          case 'mocktest_code':
            final code = content['code'] as String? ?? '';
            if (code.isNotEmpty) {
              context.push('/webview', extra: {
                'html': code, 'title': name, 'folderId': folderId,
                'parentContentId': immediateParentId, 'isMockTest': true,
              });
            } else {
              context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          case 'mocktest_file':
            final fileType = content['fileType'] as String? ?? 'pdf';
            if (url.isNotEmpty) {
              if (fileType == 'pdf') {
                context.push('/pdf_reader/view', extra: {
                  'url': url, 'folderId': folderId,
                  'parentContentId': immediateParentId, 'title': name,
                });
              } else {
                context.push('/webview', extra: {
                  'url': url, 'title': name, 'folderId': folderId,
                  'parentContentId': immediateParentId, 'isMockTest': true,
                });
              }
            } else {
              context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          case 'file':
            if (url.isNotEmpty) {
              String ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
              if (ext.isEmpty) {
                final urlName = url.split('/').last.split('?').first.split('#').first;
                ext = urlName.contains('.') ? urlName.split('.').last.toLowerCase() : '';
              }
              if (ext == 'pdf') {
                context.push('/pdf_reader/view', extra: {
                  'url': url, 'folderId': folderId,
                  'parentContentId': immediateParentId, 'title': name,
                });
              } else if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
                context.push('/media_player', extra: {'url': url, 'title': name, 'isAudio': false});
              } else if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(ext)) {
                context.push('/media_player', extra: {'url': url, 'title': name, 'isAudio': true});
              } else {
                context.push('/webview', extra: {
                  'url': url, 'title': name, 'folderId': folderId,
                  'parentContentId': immediateParentId,
                });
              }
            } else {
              context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          default:
            if (immediateParentId != null) {
              context.push('/folders/$folderId/sub/$immediateParentId', extra: {'canEdit': false, 'canManage': false});
            } else {
              context.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
        }
      }
    } catch (e) {
      if (!mounted) return;
      context.go('/auth/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF00B8D4), strokeWidth: 2),
            SizedBox(height: 12),
            Text('Loading...', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
