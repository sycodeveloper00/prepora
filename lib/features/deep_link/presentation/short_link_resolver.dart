import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/supabase_read_service.dart';
import '../../../core/services/firebase_service.dart';

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

  Future<void> _resolve() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      context.go('/auth/login');
      return;
    }

    try {
      final settings = await SupabaseReadService.getSettings('general')
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      final paidAccess = settings?['paidAccess'] as bool? ?? false;
      final settingsData = settings?['data'] as Map<String, dynamic>?;
      final paidAccessFromData = paidAccess || (settingsData?['paidAccess'] as bool? ?? false);

      bool isPaidBlocked = false;
      if (paidAccessFromData) {
        final userDoc = await SupabaseReadService.getUser(user.uid)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        final isVerified = userDoc?['verified'] as bool? ?? false;
        final freeTrialActive = userDoc?['freeTrialActive'] as bool? ?? (userDoc?['free_trial_active'] as bool? ?? false);
        if (!isVerified && !freeTrialActive) {
          isPaidBlocked = true;
        }
      }

      if (isPaidBlocked) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Paid Access Required'),
            content: const Text('Please verify your account or activate free trial to access content.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        return;
      }
      final link = await SupabaseReadService.getShareLinkByShortId(widget.shortId)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (link == null) {
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

      final router = GoRouter.of(context);

      void showBlockedDialog(String message) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Access Denied'),
            content: Text(message),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }

      if (contentType == 'folder') {
        final folder = await SupabaseReadService.getFolder(contentId)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (folder != null) {
          final locked = folder['locked'] as bool? ?? false;
          final invisible = folder['invisible'] as bool? ?? false;
          final updating = folder['updating'] as bool? ?? false;
          if (locked || invisible || updating) {
            showBlockedDialog('You are not authorized to access this content.');
            return;
          }
        }
        router.go('/dashboard');
        await Future.delayed(const Duration(milliseconds: 200));
        router.push('/folders/$contentId', extra: {'canEdit': false, 'canManage': false});
      } else if (contentType == 'subfolder') {
        final sub = await SupabaseReadService.getContent(folderId, contentId)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (sub != null) {
          final locked = sub['locked'] as bool? ?? false;
          final invisible = sub['invisible'] as bool? ?? false;
          final updating = sub['updating'] as bool? ?? false;
          if (locked || invisible || updating) {
            showBlockedDialog('You are not authorized to access this content.');
            return;
          }
        }
        final subBlocked = await FirebaseService.isAnyAncestorRestricted(folderId, contentId)
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
        if (subBlocked) {
          showBlockedDialog('You are not authorized to access this content.');
          return;
        }
        router.go('/dashboard');
        await Future.delayed(const Duration(milliseconds: 200));
        router.push('/folders/$folderId/sub/$contentId', extra: {'canEdit': false, 'canManage': false});
      } else {
        final content = await SupabaseReadService.getContent(folderId, contentId)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (content == null) {
          router.go('/dashboard');
          await Future.delayed(const Duration(milliseconds: 200));
          router.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
          return;
        }

        final locked = content['locked'] as bool? ?? false;
        final invisible = content['invisible'] as bool? ?? false;
        final updating = content['updating'] as bool? ?? false;
        if (locked || invisible || updating) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Access Denied'),
              content: const Text('You are not authorized to access this content.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
          return;
        }

        final ancestorBlocked = await FirebaseService.isAnyAncestorRestricted(folderId, contentId)
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
        if (ancestorBlocked) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Access Denied'),
              content: const Text('You are not authorized to access this content.'),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
          return;
        }

        final type = content['type'] as String? ?? 'file';
        final name = content['name'] as String? ?? '';
        final url = content['url'] as String? ?? '';
        final youtubeUrl = content['youtubeUrl'] as String? ?? '';
        final immediateParentId = content['parentContentId'] as String?;

        router.go('/dashboard');
        await Future.delayed(const Duration(milliseconds: 200));

        if (immediateParentId != null && immediateParentId.isNotEmpty) {
          router.push('/folders/$folderId/sub/$immediateParentId', extra: {'canEdit': false, 'canManage': false});
          await Future.delayed(const Duration(milliseconds: 200));
        } else {
          router.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
          await Future.delayed(const Duration(milliseconds: 200));
        }

        switch (type) {
          case 'lecture':
            final videoId = _extractYoutubeId(youtubeUrl);
            if (videoId.isNotEmpty) {
              router.push('/lectures/$videoId', extra: {
                'name': name, 'folderId': folderId, 'parentContentId': immediateParentId,
              });
            } else if (immediateParentId != null) {
              router.push('/folders/$folderId/sub/$immediateParentId', extra: {'canEdit': false, 'canManage': false});
            } else {
              router.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          case 'mocktest_url':
            if (url.isNotEmpty) {
              router.push('/webview', extra: {
                'url': url, 'title': name, 'folderId': folderId,
                'parentContentId': immediateParentId, 'isMockTest': true,
              });
            } else {
              router.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          case 'mocktest_code':
            final code = content['code'] as String? ?? '';
            if (code.isNotEmpty) {
              router.push('/webview', extra: {
                'html': code, 'title': name, 'folderId': folderId,
                'parentContentId': immediateParentId, 'isMockTest': true,
              });
            } else {
              router.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          case 'mocktest_file':
            final fileType = content['fileType'] as String? ?? 'pdf';
            if (url.isNotEmpty) {
              if (fileType == 'pdf') {
                router.push('/pdf_reader/view', extra: {
                  'url': url, 'folderId': folderId,
                  'parentContentId': immediateParentId, 'title': name,
                });
              } else {
                router.push('/webview', extra: {
                  'url': url, 'title': name, 'folderId': folderId,
                  'parentContentId': immediateParentId, 'isMockTest': true,
                });
              }
            } else {
              router.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
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
                router.push('/pdf_reader/view', extra: {
                  'url': url, 'folderId': folderId,
                  'parentContentId': immediateParentId, 'title': name,
                });
              } else if (['mp4', 'mkv', 'avi', 'mov', 'webm'].contains(ext)) {
                router.push('/media_player', extra: {'url': url, 'title': name, 'isAudio': false});
              } else if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(ext)) {
                router.push('/media_player', extra: {'url': url, 'title': name, 'isAudio': true});
              } else {
                router.push('/webview', extra: {
                  'url': url, 'title': name, 'folderId': folderId,
                  'parentContentId': immediateParentId,
                });
              }
            } else {
              router.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
            }
            break;
          default:
            if (immediateParentId != null) {
              router.push('/folders/$folderId/sub/$immediateParentId', extra: {'canEdit': false, 'canManage': false});
            } else {
              router.push('/folders/$folderId', extra: {'canEdit': false, 'canManage': false});
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
    return const Scaffold(
      backgroundColor: Color(0xFF0A0E1A),
      body: Center(
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
