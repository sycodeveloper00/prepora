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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Share link not found or expired'), backgroundColor: Colors.redAccent),
          );
          context.go('/dashboard');
        }
        return;
      }

      final contentId = link['content_id'] as String? ?? '';
      final contentType = link['content_type'] as String? ?? 'folder';
      final folderId = link['folder_id'] as String? ?? '';

      if (!mounted) return;

      if (contentType == 'folder' || contentType == 'subfolder') {
        context.pushReplacement('/folders/$contentId', extra: {
          'canEdit': false,
          'canManage': false,
        });
      } else {
        final content = await SupabaseReadService.getContent(folderId, contentId)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (content == null || !mounted) {
          context.pushReplacement('/folders/$folderId', extra: {
            'canEdit': false,
            'canManage': false,
          });
          return;
        }

        final immediateParentId = content['parentContentId'] as String?;
        if (immediateParentId != null && immediateParentId.isNotEmpty) {
          context.pushReplacement('/folders/$folderId/sub/$contentId', extra: {
            'canEdit': false,
            'canManage': false,
          });
        } else {
          context.pushReplacement('/folders/$folderId/sub/$contentId', extra: {
            'canEdit': false,
            'canManage': false,
          });
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
