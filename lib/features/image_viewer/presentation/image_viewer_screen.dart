import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ImageViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const ImageViewerScreen({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => context.pop()),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
            errorWidget: (_, url, error) {
              final isNetworkError = error.toString().toLowerCase().contains('socket') ||
                  error.toString().toLowerCase().contains('host lookup') ||
                  error.toString().toLowerCase().contains('connection') ||
                  error.toString().toLowerCase().contains('network');
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isNetworkError ? Icons.wifi_off_rounded : Icons.broken_image_rounded, size: 60, color: Colors.white24),
                  const SizedBox(height: 8),
                  Text(isNetworkError ? 'No Internet Connection' : 'Failed to load image',
                      style: const TextStyle(color: Colors.white54)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
