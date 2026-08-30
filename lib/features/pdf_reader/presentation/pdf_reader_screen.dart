import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';

class DrawPoint {
  final Offset position;
  final Color color;
  final double width;
  DrawPoint(this.position, this.color, this.width);
}

class PdfReaderScreen extends StatefulWidget {
  final String documentId;
  final String? folderId;
  final String? parentContentId;
  final String? title;
  const PdfReaderScreen({super.key, required this.documentId, this.folderId, this.parentContentId, this.title});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  String? _localPath;
  bool _isLoading = true;
  String? _error;
  String? _fileName;
  bool _accessGranted = false;
  bool _isBlocked = false;
  double _downloadProgress = 0;
  String _loadingMessage = 'Loading PDF...';
  static const _pdfChannel = MethodChannel('com.prepora.academy.prepora/pdf_intent');

  // Annotation state
  bool _isAnnotating = false;
  bool _isTextMode = false;
  final List<List<DrawPoint>> _strokes = [];
  List<DrawPoint> _currentStroke = [];
  Color _penColor = Colors.red;
  double _strokeWidth = 3;
  final GlobalKey _pdfAreaKey = GlobalKey();
  String? _textOverlay;
  Offset? _textPosition;

  // Page tracking
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isFitWidth = false;

  @override
  void initState() {
    super.initState();
    _pdfController.addListener(() {
      if (_pdfController.pageNumber != _currentPage) {
        setState(() => _currentPage = _pdfController.pageNumber);
      }
    });
    final isLocal = widget.documentId.startsWith('content://') ||
        widget.documentId.startsWith('file://') ||
        (!widget.documentId.startsWith('http://') && !widget.documentId.startsWith('https://'));
    if (isLocal) {
      _accessGranted = true;
      _loadPdf();
    } else {
      _checkAccess();
    }
  }

  Future<void> _checkAccess() async {
    final user = FirebaseService.currentUser;
    if (user == null) {
      if (mounted) setState(() { _accessGranted = false; _isLoading = false; });
      return;
    }
    try {
      // Firestore query AND cache lookup in parallel for instant open
      final docFuture = FirebaseService.getUser(user.uid);
      final cachedPath = await _findCachedPdf();

      // Show cached PDF instantly without waiting for Firestore
      if (cachedPath != null && mounted) {
        setState(() { _localPath = cachedPath; });
      }

      final doc = await docFuture;
      final data = doc?.data() as Map<String, dynamic>?;
      final isVerified = data?['verified'] == true;
      final isBlocked = data?['blocked'] == true;
      final trialActive = data?['freeTrialActive'] == true;
      final endsAt = data?['freeTrialEndsAt'];
      final trialEnd = endsAt is Timestamp ? endsAt.toDate() : null;
      final hasActiveTrial = trialActive && (trialEnd?.isAfter(DateTime.now()) ?? false);
      if (isBlocked) {
        if (mounted) setState(() { _accessGranted = false; _isBlocked = true; _isLoading = false; _localPath = null; });
        return;
      }
      final settings = await FirebaseService.getSettings();
      final paidAccess = settings['paidAccess'] as bool? ?? false;
      if (!paidAccess || isVerified || hasActiveTrial) {
        if (mounted) setState(() { _accessGranted = true; _isLoading = false; });
        if (_localPath == null) _loadPdf();
      } else {
        if (mounted) setState(() { _accessGranted = false; _isLoading = false; _localPath = null; });
      }
    } catch (_) {
      if (mounted) setState(() { _accessGranted = false; _isLoading = false; });
    }
  }

  Future<String?> _findCachedPdf() async {
    final url = widget.documentId;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/pdf_cache');
      if (!await cacheDir.exists()) return null;
      final rawName = url.split('/').last.split('?').first.split('#').first;
      final safeName = rawName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final localFile = File('${cacheDir.path}/$safeName');
      if (await localFile.exists() && await localFile.length() > 0) {
        return localFile.path;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadPdf() async {
    try {
      final url = widget.documentId;
      if (url.isEmpty) {
        setState(() { _error = 'No file path provided'; _isLoading = false; });
        return;
      }

      final rawName = url.split('/').last.split('?').first.split('#').first;
      _fileName = rawName.replaceAll(RegExp(r'[%&+:?/#\\]'), '_');
      if (widget.title != null && widget.title!.isNotEmpty) {
        _fileName = widget.title;
      } else {
        _fileName = _fileName!.replaceFirst(RegExp(r'^v\d+_'), '');
        _fileName = _fileName!.replaceFirst(RegExp(r'^\d+_'), '');
      }

      if (url.startsWith('http://') || url.startsWith('https://')) {
        final dir = await getApplicationDocumentsDirectory();
        final cacheDir = Directory('${dir.path}/pdf_cache');
        if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
        final safeName = _fileName!.replaceAll(RegExp(r'[^\w\.\-]'), '_');
        final localFile = File('${cacheDir.path}/$safeName');

        if (await localFile.exists() && await localFile.length() > 0) {
          if (mounted) setState(() { _localPath = localFile.path; _isLoading = false; });
          return;
        }

        if (mounted) setState(() { _loadingMessage = 'Connecting...'; _downloadProgress = 0; });

        final client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse(url));
          request.headers['Connection'] = 'keep-alive';
          final response = await client.send(request).timeout(const Duration(seconds: 30));

          if (response.statusCode == 200) {
            final contentType = response.headers['content-type'] ?? '';
            if (contentType.contains('text/html') || contentType.contains('text/plain')) {
              if (mounted) setState(() { _error = 'Failed to load PDF — server returned an error page'; _isLoading = false; });
              client.close();
              return;
            }
            final contentLength = response.contentLength;
            final sink = localFile.openWrite();
            int received = 0;

            await for (final chunk in response.stream) {
              sink.add(chunk);
              received += chunk.length;
              if (mounted) {
                final progress = contentLength != null && contentLength > 0
                    ? (received / contentLength).clamp(0.0, 1.0)
                    : 0.0;
                final kb = (received / 1024).toStringAsFixed(0);
                final totalKb = contentLength != null ? (contentLength / 1024).toStringAsFixed(0) : '?';
                setState(() {
                  _downloadProgress = progress;
                  _loadingMessage = 'Downloading... ${kb}KB / ${totalKb}KB';
                });
              }
            }
            await sink.close();

            if (mounted) setState(() { _loadingMessage = 'Opening PDF...'; _downloadProgress = 1.0; });
            if (mounted) setState(() { _localPath = localFile.path; _isLoading = false; });
          } else {
            if (mounted) setState(() { _error = 'Failed to download PDF (${response.statusCode})'; _isLoading = false; });
          }
        } finally {
          client.close();
        }
      } else if (url.startsWith('content://')) {
        try {
          final filePath = await _pdfChannel.invokeMethod<String>('copyContentUriToTemp', url);
          if (filePath != null) {
            final tempFile = File(filePath);
            if (await tempFile.exists() && await tempFile.length() > 0) {
              if (mounted) setState(() { _localPath = filePath; _isLoading = false; });
              return;
            }
          }
          if (mounted) setState(() { _error = 'Failed to read PDF from device'; _isLoading = false; });
        } catch (_) {
          if (mounted) setState(() { _error = 'Failed to open PDF from device'; _isLoading = false; });
        }
      } else {
        final file = File(url);
        if (await file.exists()) {
          setState(() { _localPath = url; _isLoading = false; });
        } else {
          setState(() { _error = 'File not found on device'; _isLoading = false; });
        }
      }
    } on SocketException catch (_) {
      setState(() { _error = 'No Internet Connection'; _isLoading = false; });
    } on TimeoutException catch (_) {
      setState(() { _error = 'Connection timed out'; _isLoading = false; });
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('socket') || msg.contains('host lookup') || msg.contains('connection refused') || msg.contains('network')) {
        setState(() { _error = 'No Internet Connection'; _isLoading = false; });
      } else {
        setState(() { _error = 'Error: $e'; _isLoading = false; });
      }
    }
  }

  Future<void> _saveAnnotation() async {
    final hasStrokes = _strokes.isNotEmpty;
    final hasText = _textOverlay != null;
    if (!hasStrokes && !hasText) {
      // Saving an empty annotation = bookmarking the PDF in Notes.
      final ok = await FirebaseService.saveNote(
        widget.documentId,
        'PDF: ${_fileName ?? "Document"}',
        lectureName: _fileName ?? 'PDF Note',
      );
      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF added to Notes!'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save — please check your connection and try again.'), backgroundColor: Colors.redAccent),
          );
        }
      }
      return;
    }

    final ok = await FirebaseService.saveNote(
      widget.documentId,
      'PDF Annotation: ${_fileName ?? "Document"}\n\nStrokes: ${_strokes.length}\nText: ${_textOverlay ?? "-"}',
      lectureName: _fileName ?? 'PDF Note',
    );

    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Notes!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — please check your connection and try again.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _clearAnnotations() {
    setState(() {
      _strokes.clear();
      _currentStroke.clear();
      _textOverlay = null;
      _textPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseService.currentUser;

    if (!_accessGranted && !_isLoading) {
      if (_isBlocked) {
        return Scaffold(
          backgroundColor: const Color(0xFF0D001A),
          appBar: AppBar(
            title: const Text('Access Required'),
            backgroundColor: const Color(0xFF0D001A),
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 64),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Our system detected unusual activity from your device. Your account is blocked.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.redAccent, fontSize: 15, height: 1.5),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'If you believe this is a mistake, please contact the admin to restore access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await FirebaseService.signOut();
                      if (mounted) context.go('/auth/login');
                    },
                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                    label: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A0533),
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.parentContentId == null && widget.folderId == null) {
          context.go('/dashboard');
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Access Required')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  user == null ? Icons.login_rounded : Icons.lock_rounded,
                  size: 80,
                  color: const Color(0xFFB388FF),
                ),
                const SizedBox(height: 24),
                Text(
                  user == null ? 'Login Required' : 'Paid Access Required',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A0533),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user == null
                      ? 'Please login to your PrePora account to view this PDF.'
                      : 'Your account is not verified yet. Please complete verification to access PDF content.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white70 : Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => context.go('/auth/login'),
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: const Text('Login to PrePora'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A148C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                if (user != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/dashboard'),
                    child: const Text('Go to Dashboard', style: TextStyle(color: Color(0xFF00B8D4))),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D2E) : Colors.white,
      body: Column(
        children: [
          Container(
            color: isDark ? const Color(0xFF1A0533) : Colors.white,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top row: Back + Title + Annotate/Save
                  SizedBox(
                    height: 44,
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            widget.parentContentId == null && widget.folderId == null
                                ? Icons.close_rounded
                                : Icons.arrow_back_ios_new_rounded,
                            size: 20,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          onPressed: () {
                            if (widget.parentContentId == null && widget.folderId == null) {
                              context.go('/dashboard');
                            } else {
                              Navigator.pop(context);
                            }
                          },
                        ),
                        Expanded(
                          child: Text(
                            _isLoading ? 'Loading...' : (_fileName ?? 'PDF Viewer'),
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_isAnnotating) ...[
                          IconButton(
                            icon: Icon(_isTextMode ? Icons.draw_rounded : Icons.text_fields_rounded, size: 18, color: Colors.cyan),
                            onPressed: () => setState(() => _isTextMode = !_isTextMode),
                            tooltip: _isTextMode ? 'Draw' : 'Text',
                          ),
                          PopupMenuButton<Color>(
                            icon: Icon(Icons.color_lens_rounded, size: 18, color: _penColor),
                            onSelected: (c) => setState(() => _penColor = c),
                            itemBuilder: (_) => [
                              PopupMenuItem(value: Colors.red, child: Row(children: [Container(width:18,height:18,color:Colors.red),const SizedBox(width:8),const Text('Red')])),
                              PopupMenuItem(value: Colors.blue, child: Row(children: [Container(width:18,height:18,color:Colors.blue),const SizedBox(width:8),const Text('Blue')])),
                              PopupMenuItem(value: Colors.green, child: Row(children: [Container(width:18,height:18,color:Colors.green),const SizedBox(width:8),const Text('Green')])),
                              PopupMenuItem(value: Colors.orange, child: Row(children: [Container(width:18,height:18,color:Colors.orange),const SizedBox(width:8),const Text('Orange')])),
                              PopupMenuItem(value: Colors.black, child: Row(children: [Container(width:18,height:18,color:Colors.black),const SizedBox(width:8),const Text('Black')])),
                            ],
                          ),
                          PopupMenuButton<double>(
                            icon: Icon(Icons.line_weight_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
                            onSelected: (w) => setState(() => _strokeWidth = w),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 2.0, child: Text('Thin')),
                              const PopupMenuItem(value: 5.0, child: Text('Medium')),
                              const PopupMenuItem(value: 10.0, child: Text('Thick')),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear_all_rounded, size: 18, color: Colors.redAccent),
                            onPressed: _clearAnnotations,
                            tooltip: 'Clear',
                          ),
                          IconButton(
                            icon: const Icon(Icons.note_add_rounded, size: 18, color: Colors.green),
                            onPressed: _saveAnnotation,
                            tooltip: 'Save to Notes',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                            onPressed: () => setState(() { _isAnnotating = false; _isTextMode = false; _clearAnnotations(); }),
                            tooltip: 'Exit',
                          ),
                        ] else ...[
                          IconButton(
                            icon: const Icon(Icons.note_add_rounded, size: 18, color: Colors.green),
                            onPressed: _saveAnnotation,
                            tooltip: 'Save to Notes',
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.cyan),
                            onPressed: () => setState(() => _isAnnotating = true),
                            tooltip: 'Annotate',
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Controls row: Page nav | Zoom | Fit Width
                  if (_totalPages > 0 && !_isAnnotating)
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF12082A) : const Color(0xFFF5F5F5),
                        border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 0.5)),
                      ),
                      child: Row(
                        children: [
                          // Page navigation
                          _buildCircleBtn(Icons.remove, _currentPage > 1 ? () => _pdfController.jumpToPage(_currentPage - 1) : null, isDark),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () async {
                              final ctrl = TextEditingController(text: '$_currentPage');
                              final page = await showDialog<int>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Go to Page', style: TextStyle(fontSize: 15)),
                                  content: TextField(
                                    controller: ctrl,
                                    keyboardType: TextInputType.number,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: '1-$_totalPages',
                                      border: const OutlineInputBorder(),
                                      suffixText: '/ $_totalPages',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                    ElevatedButton(
                                      onPressed: () {
                                        final p = int.tryParse(ctrl.text);
                                        if (p != null && p >= 1 && p <= _totalPages) Navigator.pop(ctx, p);
                                      },
                                      child: const Text('Go'),
                                    ),
                                  ],
                                ),
                              );
                              if (page != null) _pdfController.jumpToPage(page);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('$_currentPage', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w700, fontSize: 13)),
                                  const SizedBox(width: 4),
                                  Text('of', style: TextStyle(color: isDark ? Colors.white54 : Colors.black38, fontSize: 11)),
                                  Text('$_totalPages', style: TextStyle(color: isDark ? Colors.white54 : Colors.black38, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                          _buildCircleBtn(Icons.add, _currentPage < _totalPages ? () => _pdfController.jumpToPage(_currentPage + 1) : null, isDark),
                          const SizedBox(width: 8),
                          // Divider
                          Container(width: 1, height: 20, color: isDark ? Colors.white12 : Colors.black12),
                          const SizedBox(width: 8),
                          // Zoom controls
                          _buildCircleBtn(Icons.remove, () {
                            final z = _pdfController.zoomLevel;
                            if (z > 0.5) _pdfController.zoomLevel = z - 0.25;
                          }, isDark),
                          const SizedBox(width: 2),
                          GestureDetector(
                            onTap: () => _pdfController.zoomLevel = 1.0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${(_pdfController.zoomLevel * 100).round()}%',
                                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                            ),
                          ),
                          _buildCircleBtn(Icons.add, () {
                            final z = _pdfController.zoomLevel;
                            if (z < 5.0) _pdfController.zoomLevel = z + 0.25;
                          }, isDark),
                          const SizedBox(width: 8),
                          // Divider
                          Container(width: 1, height: 20, color: isDark ? Colors.white12 : Colors.black12),
                          const SizedBox(width: 8),
                          // Fit Width button
                          GestureDetector(
            onTap: () {
              setState(() => _isFitWidth = !_isFitWidth);
              _pdfController.zoomLevel = 1.0;
            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _isFitWidth
                                    ? const Color(0xFF00B8D4).withValues(alpha: 0.15)
                                    : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06)),
                                borderRadius: BorderRadius.circular(6),
                                border: _isFitWidth ? Border.all(color: const Color(0xFF00B8D4).withValues(alpha: 0.3)) : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isFitWidth ? Icons.fit_screen_rounded : Icons.aspect_ratio_rounded,
                                    size: 14,
                                    color: _isFitWidth ? const Color(0xFF00B8D4) : (isDark ? Colors.white54 : Colors.black38),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Fit Width',
                                    style: TextStyle(
                                      color: _isFitWidth ? const Color(0xFF00B8D4) : (isDark ? Colors.white54 : Colors.black38),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          // PDF Viewer — opens instantly, loading overlay on top
          Expanded(
            child: Stack(
              key: _pdfAreaKey,
              children: [
                // Background
                Container(color: isDark ? const Color(0xFF0D0D2E) : Colors.white),

                // PDF viewer — fills entire area, scrolls smoothly
                if (_localPath != null)
                  Positioned.fill(
                    child: SfPdfViewer.file(
                      File(_localPath!),
                      controller: _pdfController,
                      enableTextSelection: true,
                      canShowScrollStatus: false,
                      canShowPaginationDialog: false,
                      initialZoomLevel: 1.0,
                      onDocumentLoaded: (details) {
                        if (mounted) setState(() => _totalPages = details.document.pages.count);
                      },
                      onDocumentLoadFailed: (details) {
                        if (mounted) {
                          setState(() {
                          _error = 'Failed to load PDF: ${details.description}';
                          _isLoading = false;
                        });
                        }
                      },
                    ),
                  ),

                // Loading overlay — compact, on top of PDF area
                if (_isLoading)
                  IgnorePointer(
                    child: Center(
                      child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.black87 : Colors.white).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12)],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28, height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: const Color(0xFF4A148C),
                              backgroundColor: isDark ? Colors.white24 : Colors.black12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (_downloadProgress > 0 && _downloadProgress < 1.0) ...[
                            SizedBox(
                              width: 180,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: _downloadProgress,
                                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4A148C)),
                                  minHeight: 5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            _loadingMessage,
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Error overlay
                if (_error != null && !_isLoading)
                  IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 56, color: Colors.redAccent),
                            const SizedBox(height: 14),
                            Text(_error!, textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () { setState(() { _isLoading = true; _error = null; }); _loadPdf(); },
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A148C),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Annotation overlays
                if (_isAnnotating)
                  GestureDetector(
                    onPanStart: _isTextMode ? null : (d) {
                      setState(() {
                        _currentStroke = [DrawPoint(d.localPosition, _penColor, _strokeWidth)];
                      });
                    },
                    onPanUpdate: _isTextMode ? null : (d) {
                      setState(() {
                        _currentStroke.add(DrawPoint(d.localPosition, _penColor, _strokeWidth));
                      });
                    },
                    onPanEnd: _isTextMode ? null : (_) {
                      setState(() {
                        _strokes.add(List.from(_currentStroke));
                        _currentStroke = [];
                      });
                    },
                    onTapUp: _isTextMode ? (d) {
                      _showTextInput(d.localPosition);
                    } : null,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _PdfAnnotPainter(
                          strokes: _strokes,
                          currentStroke: _currentStroke,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                if (_textOverlay != null && _textPosition != null)
                  Positioned(
                    left: _textPosition!.dx,
                    top: _textPosition!.dy,
                    child: GestureDetector(
                      onLongPress: () => setState(() { _textOverlay = null; _textPosition = null; }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        color: Colors.yellow.withValues(alpha: 0.3),
                        child: Text(_textOverlay!, style: TextStyle(color: _penColor, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                if (_isAnnotating)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.black87 : Colors.white).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isTextMode ? 'Tap to add text · Long-press to delete' : 'Draw with finger',
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: widget.folderId != null && !_isAnnotating
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
    );
  }

  void _showTextInput(Offset pos) async {
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Add Text'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Type your text...'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
          ],
        );
      },
    );
    if (text != null && text.isNotEmpty) {
      setState(() {
        _textOverlay = text;
        _textPosition = pos;
      });
    }
  }

  Widget _buildCircleBtn(IconData icon, VoidCallback? onPressed, bool isDark) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: onPressed != null
              ? (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06))
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onPressed != null
              ? (isDark ? Colors.white70 : Colors.black54)
              : (isDark ? Colors.white24 : Colors.black12),
        ),
      ),
    );
  }

  Widget _buildAiFab(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'ai_chat_pdf_${widget.documentId}',
        onPressed: () => context.push('/ai_tutor'),
        backgroundColor: Colors.transparent, elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: const Color(0xFF00B8D4).withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 2)],
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
        heroTag: 'group_pdf_${widget.documentId}',
        onPressed: () async {
          final uri = Uri.tryParse(link);
          if (uri != null) {
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

class _PdfAnnotPainter extends CustomPainter {
  final List<List<DrawPoint>> strokes;
  final List<DrawPoint> currentStroke;

  _PdfAnnotPainter({required this.strokes, required this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in [...strokes, currentStroke]) {
      if (stroke.isEmpty) continue;
      for (int i = 0; i < stroke.length - 1; i++) {
        final paint = Paint()
          ..color = stroke[i].color
          ..strokeWidth = stroke[i].width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawLine(stroke[i].position, stroke[i + 1].position, paint);
      }
      if (stroke.length == 1) {
        final paint = Paint()
          ..color = stroke[0].color
          ..strokeWidth = stroke[0].width
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(stroke[0].position, stroke[0].width / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PdfAnnotPainter old) => true;
}
