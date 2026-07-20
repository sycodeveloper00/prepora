import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../core/widgets/professional_loader.dart';

class MediaPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final bool isAudio;

  const MediaPlayerScreen({super.key, required this.url, required this.title, this.isAudio = false});

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _controller!.initialize();
      _controller!.addListener(_listener);
      if (!mounted) return;
      setState(() {
        _duration = _controller!.value.duration;
        _isInitialized = true;
      });
      _controller!.play();
      setState(() => _isPlaying = true);
    } on SocketException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Internet Connection'), backgroundColor: Colors.redAccent));
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Internet Connection'), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final displayMsg = (msg.contains('socket') || msg.contains('host lookup') || msg.contains('connection refused') || msg.contains('network'))
          ? 'No Internet Connection'
          : 'Error: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(displayMsg), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _listener() {
    if (!mounted || _controller == null) return;
    setState(() {
      _isPlaying = _controller!.value.isPlaying;
      _position = _controller!.value.position;
      _duration = _controller!.value.duration;
    });
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  void _seekTo(double value) {
    _controller!.seekTo(Duration(seconds: value.toInt()));
    setState(() => _position = Duration(seconds: value.toInt()));
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller?.removeListener(_listener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isInitialized
          ? GestureDetector(
              onTap: _togglePlayPause,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxHeight = constraints.maxHeight;
                    final videoHeight = widget.isAudio ? 120.0
                        : (_controller != null && _controller!.value.size.height > 0)
                            ? (constraints.maxWidth / _controller!.value.aspectRatio)
                            : 200.0;
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.isAudio)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Icon(Icons.audiotrack_rounded, size: 120, color: Colors.white24),
                              )
                            else if (_controller != null)
                              AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    VideoPlayer(_controller!),
                                    if (!_isPlaying)
                                      Container(
                                        width: 56, height: 56,
                                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.5)),
                                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                                      ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 20),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: _togglePlayPause,
                                    child: Container(
                                      width: 36, height: 36,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.15)),
                                      child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Slider(
                                      value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1),
                                      max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1,
                                      activeColor: Colors.amber,
                                      inactiveColor: Colors.white24,
                                      onChanged: _seekTo,
                                    ),
                                  ),
                                  Text(_formatDuration(_position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ProfessionalLoader(),
                  const SizedBox(height: 16),
                  Text(widget.isAudio ? 'Loading audio...' : 'Loading video...', style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
    );
  }
}
