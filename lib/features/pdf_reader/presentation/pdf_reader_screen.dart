import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
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
  const PdfReaderScreen({super.key, required this.documentId, this.folderId, this.parentContentId});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  String? _localPath;
  bool _isLoading = true;
  String? _error;
  String? _fileName;

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

  @override
  void initState() {
    super.initState();
    _loadPdf();
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

      if (url.startsWith('http://') || url.startsWith('https://')) {
        final dir = await getTemporaryDirectory();
        final safeName = _fileName!.replaceAll(RegExp(r'[^\w\.\-]'), '_');
        final localFile = File('${dir.path}/$safeName');
        if (!await localFile.exists()) {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            await localFile.writeAsBytes(response.bodyBytes);
          } else {
            setState(() { _error = 'Failed to download PDF'; _isLoading = false; });
            return;
          }
        }
        if (!mounted) return;
        if (await localFile.exists()) {
          setState(() { _localPath = localFile.path; _isLoading = false; });
        } else {
          setState(() { _error = 'Downloaded file not found'; _isLoading = false; });
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
      setState(() { _error = 'No Internet Connection'; _isLoading = false; });
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
    if (_strokes.isEmpty && _textOverlay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to save - add drawings or text first')),
      );
      return;
    }

    await FirebaseService.saveNote(
      widget.documentId,
      'PDF Annotation: ${_fileName ?? "Document"}\n\nStrokes: ${_strokes.length}\nText: ${_textOverlay ?? "-"}',
      lectureName: _fileName ?? 'PDF Note',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Notes!'), backgroundColor: Colors.green),
      );
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoading ? 'Loading...' : (_fileName ?? 'PDF Viewer')),
        actions: [
          if (_isAnnotating) ...[
            IconButton(
              icon: Icon(_isTextMode ? Icons.draw_rounded : Icons.text_fields_rounded, color: Colors.cyan),
              onPressed: () => setState(() => _isTextMode = !_isTextMode),
              tooltip: _isTextMode ? 'Switch to Draw' : 'Switch to Text',
            ),
            PopupMenuButton<Color>(
              icon: const Icon(Icons.color_lens_rounded),
              onSelected: (c) => setState(() => _penColor = c),
              itemBuilder: (_) => [
                PopupMenuItem(value: Colors.red, child: Row(children: [Container(width:20,height:20,color:Colors.red,),const SizedBox(width:8),const Text('Red')])),
                PopupMenuItem(value: Colors.blue, child: Row(children: [Container(width:20,height:20,color:Colors.blue),const SizedBox(width:8),const Text('Blue')])),
                PopupMenuItem(value: Colors.green, child: Row(children: [Container(width:20,height:20,color:Colors.green),const SizedBox(width:8),const Text('Green')])),
                PopupMenuItem(value: Colors.orange, child: Row(children: [Container(width:20,height:20,color:Colors.orange),const SizedBox(width:8),const Text('Orange')])),
                PopupMenuItem(value: Colors.black, child: Row(children: [Container(width:20,height:20,color:Colors.black),const SizedBox(width:8),const Text('Black')])),
              ],
            ),
            PopupMenuButton<double>(
              icon: const Icon(Icons.line_weight_rounded),
              onSelected: (w) => setState(() => _strokeWidth = w),
              itemBuilder: (_) => [
                PopupMenuItem(value: 2.0, child: const Text('Thin')),
                PopupMenuItem(value: 5.0, child: const Text('Medium')),
                PopupMenuItem(value: 10.0, child: const Text('Thick')),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.clear_all_rounded, color: Colors.redAccent),
              onPressed: _clearAnnotations,
              tooltip: 'Clear All',
            ),
            IconButton(
              icon: const Icon(Icons.save_alt_rounded, color: Colors.green),
              onPressed: _saveAnnotation,
              tooltip: 'Save to Notes',
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
              onPressed: () => setState(() { _isAnnotating = false; _isTextMode = false; _clearAnnotations(); }),
              tooltip: 'Exit Annotation',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: Colors.cyan),
              onPressed: () => setState(() => _isAnnotating = true),
              tooltip: 'Annotate PDF',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 64, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () { setState(() { _isLoading = true; _error = null; }); _loadPdf(); },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  key: _pdfAreaKey,
                  children: [
                    SfPdfViewer.file(
                      File(_localPath!),
                      controller: _pdfController,
                      enableTextSelection: true,
                      canShowScrollStatus: true,
                      canShowPaginationDialog: true,
                    ),
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
                              _isTextMode ? 'Tap to add text · Long-press text to delete' : 'Draw with finger',
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
      floatingActionButton: widget.folderId != null
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
