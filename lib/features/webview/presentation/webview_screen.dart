import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'webview_stub.dart'
    if (dart.library.html) 'webview_web.dart';
import '../../../core/helpers/katex_injector.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AppWebViewScreen extends StatefulWidget {
  final String? url;
  final String? html;
  final String title;
  final String? folderId;
  final String? parentContentId;
  final bool isMockTest;

  const AppWebViewScreen({super.key, this.url, this.html, required this.title, this.folderId, this.parentContentId, this.isMockTest = false});

  @override
  State<AppWebViewScreen> createState() => _AppWebViewScreenState();
}

class _AppWebViewScreenState extends State<AppWebViewScreen> {
  late final WebViewController? _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _isLoading = false;
    } else {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) => setState(() { _isLoading = true; _currentUrl = url; }),
          onProgress: (progress) => setState(() => _loadingProgress = progress / 100),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.contains('accounts.google.com') || url.contains('login.microsoftonline.com') || url.contains('onedrive.live.com') || url.contains('drive.google.com')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.navigate;
          },
        ));

      if (widget.html != null && widget.html!.isNotEmpty) {
        _controller!.loadHtmlString(KaTeXInjector.inject(widget.html!));
      } else if (widget.url != null && widget.url!.isNotEmpty) {
        _currentUrl = widget.url!;
        final urlLower = widget.url!.toLowerCase();
        if (urlLower.endsWith('.html') || urlLower.endsWith('.htm')) {
          _fetchAndInjectHtml(widget.url!);
        } else {
          _controller!.loadRequest(Uri.parse(widget.url!));
        }
      }
    }
  }

  Future<void> _fetchAndInjectHtml(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 && mounted) {
        final injected = KaTeXInjector.inject(response.body);
        _controller!.loadHtmlString(injected);
      } else if (mounted) {
        _controller!.loadRequest(Uri.parse(url));
      }
    } catch (_) {
      if (mounted) {
        _controller!.loadRequest(Uri.parse(url));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.isMockTest) {
          _showCloseTestDialog();
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D2E) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : Colors.black87),
          onPressed: () {
            if (widget.isMockTest) {
              _showCloseTestDialog();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(widget.title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!kIsWeb && _controller != null && !widget.isMockTest) ...[
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () => _controller.reload(),
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: Icon(Icons.open_in_browser_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () async {
                final url = _currentUrl.isNotEmpty ? _currentUrl : (widget.url ?? '');
                if (url.isNotEmpty) {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              tooltip: 'Open in browser',
            ),
            IconButton(
              icon: Icon(Icons.download_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () => _downloadFile(),
              tooltip: 'Download',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_isLoading && !kIsWeb)
            LinearProgressIndicator(
              value: _loadingProgress > 0 ? _loadingProgress : null,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF4A148C)),
              minHeight: 2,
            ),
          Expanded(
            child: kIsWeb ? _buildWebBody() : _buildMobileBody(),
          ),
        ],
      ),
      floatingActionButton: !widget.isMockTest && widget.folderId != null
          ? FutureBuilder<String?>(
              future: FirebaseService.getGroupLinkForLevel(widget.folderId!, parentContentId: widget.parentContentId),
              builder: (context, snap) {
                final link = snap.data;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAiFab(context),
                    if (link != null && link.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildGroupFab(context, link),
                    ],
                  ],
                );
              },
            )
          : null,
    ),
    );
  }

  Widget _buildWebBody() {
    if (widget.html != null && widget.html!.isNotEmpty) {
      return WebViewWebWidget(html: widget.html!);
    }
    if (widget.url != null && widget.url!.isNotEmpty) {
      return WebViewWebWidget(url: widget.url!);
    }
    return const Center(child: Text('No content'));
  }

  Widget _buildMobileBody() {
    if (_controller == null) return const Center(child: ProfessionalLoader());
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(child: ProfessionalLoader()),
      ],
    );
  }

  void _showCloseTestDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60, height: 60,
              decoration: const BoxDecoration(color: Color(0xFFFEF3C7), shape: BoxShape.circle),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 32),
            ),
            const SizedBox(height: 16),
            Text('Close Test?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 8),
            Text(
              'Your progress will be lost if you close the test now. Are you sure?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black54, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Close Test'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFile() async {
    final url = _currentUrl.isNotEmpty ? _currentUrl : (widget.url ?? '');
    if (url.isEmpty) return;

    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission required to download'), backgroundColor: Colors.redAccent),
            );
          }
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Downloading...'), backgroundColor: Colors.blue, duration: Duration(seconds: 2)),
        );
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download failed'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      String fileName = url.split('/').last.split('?').first;
      if (fileName.isEmpty || !fileName.contains('.')) {
        fileName = 'download_${DateTime.now().millisecondsSinceEpoch}';
      }

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access storage'), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      String savePath = '${downloadsDir.path}/$fileName';
      int counter = 1;
      while (await File(savePath).exists()) {
        final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
        final base = fileName.replaceAll(RegExp(r'\.[^.]*$'), '');
        savePath = '${downloadsDir.path}/$base ($counter)$ext';
        counter++;
      }

      final file = File(savePath);
      await file.writeAsBytes(response.bodyBytes);

      if (mounted) {
        final displayPath = savePath.split('/').last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded: $displayPath'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'OPEN',
              textColor: Colors.white,
              onPressed: () async {
                try {
                  await OpenFilex.open(savePath);
                } catch (_) {}
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildAiFab(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'ai_chat_webview_${widget.title}',
        onPressed: () => context.push('/ai_tutor'),
        backgroundColor: Colors.transparent, elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: Color(0xFF00B8D4).withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 2)],
          ),
          child: ClipOval(child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover)),
        ),
      ),
    );
  }

  Widget _buildGroupFab(BuildContext context, String link) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'group_webview_${widget.title}',
        onPressed: () async {
          if (link.isNotEmpty && context.mounted) {
            context.push('/webview', extra: {'url': link, 'title': 'Group'});
          }
        },
        backgroundColor: Colors.transparent, elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.amber.shade700,
            boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)],
          ),
          child: const Icon(Icons.groups_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
