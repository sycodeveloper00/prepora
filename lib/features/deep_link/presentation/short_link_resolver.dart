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
        setState(() {});
        return;
      }

      final contentId = link['content_id'] as String? ?? '';
      final contentType = link['content_type'] as String? ?? 'folder';
      final folderId = link['folder_id'] as String? ?? '';

      if (!mounted) return;

      if (contentType == 'folder') {
        context.pushReplacement('/folders/$contentId', extra: {
          'canEdit': false,
          'canManage': false,
        });
      } else {
        final parentChain = await _resolveParentChain(folderId, contentId);
        if (!mounted) return;

        context.pushReplacement('/folders/$folderId', extra: {
          'canEdit': false,
          'canManage': false,
        });
        for (final parentId in parentChain) {
          if (!mounted) return;
          await Future.delayed(const Duration(milliseconds: 50));
          context.push('/folders/$folderId/sub/$parentId', extra: {
            'canEdit': false,
            'canManage': false,
          });
        }
        if (!mounted) return;
        context.push('/folders/$folderId/sub/$contentId', extra: {
          'canEdit': false,
          'canManage': false,
        });
      }
    } catch (e) {
      if (!mounted) return;
      context.go('/auth/login');
    }
  }

  Future<List<String>> _resolveParentChain(String folderId, String contentId) async {
    final chain = <String>[];
    try {
      final content = await SupabaseReadService.getContent(folderId, contentId);
      if (content == null) return chain;
      var currentId = content['parentContentId'] as String?;
      final visited = <String>{};
      final path = <String>[];
      while (currentId != null && currentId.isNotEmpty && !visited.contains(currentId)) {
        visited.add(currentId);
        path.add(currentId);
        final parent = await SupabaseReadService.getContent(folderId, currentId);
        if (parent == null) break;
        currentId = parent['parentContentId'] as String?;
      }
      chain.addAll(path.reversed);
    } catch (_) {}
    return chain;
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
