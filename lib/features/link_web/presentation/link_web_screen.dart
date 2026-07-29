import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../../../core/services/firebase_service.dart';

class LinkWebScreen extends StatefulWidget {
  const LinkWebScreen({super.key});
  @override
  State<LinkWebScreen> createState() => _LinkWebScreenState();
}

class _LinkWebScreenState extends State<LinkWebScreen> {
  MobileScannerController? _scannerController;
  bool _isScanning = true;
  bool _isConnecting = false;
  String? _connectedSessionId;
  Map<String, dynamic>? _activeSession;
  List<Map<String, dynamic>> _connectionHistory = [];
  StreamSubscription? _sessionSub;
  StreamSubscription? _historySub;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    _loadActiveSession();
    _loadConnectionHistory();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _sessionSub?.cancel();
    _historySub?.cancel();
    super.dispose();
  }

  void _loadActiveSession() {
    final user = FirebaseService.currentUser;
    if (user == null) return;
    _historySub?.cancel();
    _historySub = FirebaseService.firestore
        .collection('web_sessions')
        .where('uid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'connected')
        .snapshots()
        .listen((snap) {
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        setState(() {
          _activeSession = doc.data();
          _connectedSessionId = doc.id;
          _isScanning = false;
        });
      } else {
        setState(() {
          _activeSession = null;
          _connectedSessionId = null;
          _isScanning = true;
        });
      }
    });
  }

  void _loadConnectionHistory() {
    final user = FirebaseService.currentUser;
    if (user == null) return;
    _sessionSub?.cancel();
    _sessionSub = FirebaseService.firestore
        .collection('web_sessions')
        .where('uid', isEqualTo: user.uid)
        .orderBy('connectedAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
      setState(() {
        _connectionHistory = snap.docs.map((d) => {
          ...d.data(),
          'sessionId': d.id,
        }).toList();
      });
    });
  }

  void _onQRDetected(BarcodeCapture capture) {
    if (!_isScanning || _isConnecting) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final raw = barcode.rawValue!;

    // QR format: prepora-web-link:{sessionId}
    if (!raw.startsWith('prepora-web-link:')) return;
    final sessionId = raw.replaceFirst('prepora-web-link:', '');
    if (sessionId.isEmpty) return;

    _connectToSession(sessionId);
  }

  Future<void> _connectToSession(String sessionId) async {
    final user = FirebaseService.currentUser;
    if (user == null) return;

    setState(() => _isConnecting = true);
    _scannerController?.stop();

    try {
      final sessionDoc = FirebaseService.firestore.collection('web_sessions').doc(sessionId);
      final sessionSnap = await sessionDoc.get();

      if (!sessionSnap.exists) {
        _showError('Invalid QR code. Please try again.');
        setState(() { _isConnecting = false; _isScanning = true; });
        _scannerController?.start();
        return;
      }

      final sessionData = sessionDoc.data()!;
      if (sessionData['status'] == 'connected' && sessionData['uid'] != user.uid) {
        _showError('This QR code is already linked to another account.');
        setState(() { _isConnecting = false; _isScanning = true; });
        _scannerController?.start();
        return;
      }

      // Disconnect any existing sessions first (one connection at a time)
      final existingSessions = await FirebaseService.firestore
          .collection('web_sessions')
          .where('uid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'connected')
          .get();
      for (final doc in existingSessions.docs) {
        await doc.reference.update({
          'status': 'disconnected',
          'disconnectedAt': Timestamp.fromDate(DateTime.now()),
        });
      }

      // Get user data
      final userDoc = await FirebaseService.firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();

      // Connect
      await sessionDoc.update({
        'uid': user.uid,
        'userName': userData?['name'] ?? user.displayName ?? 'Student',
        'userEmail': userData?['email'] ?? user.email ?? '',
        'userRole': userData?['role'] ?? 'student',
        'status': 'connected',
        'connectedAt': Timestamp.fromDate(DateTime.now()),
        'lastActive': Timestamp.fromDate(DateTime.now()),
        'deviceInfo': 'Mobile App',
      });

      setState(() {
        _isConnecting = false;
        _connectedSessionId = sessionId;
        _activeSession = sessionData;
        _isScanning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected to Web version!'), backgroundColor: Color(0xFF00E676)),
        );
      }
    } catch (e) {
      _showError('Connection failed. Please try again.');
      setState(() { _isConnecting = false; _isScanning = true; });
      _scannerController?.start();
    }
  }

  Future<void> _disconnect() async {
    if (_connectedSessionId == null) return;
    try {
      await FirebaseService.firestore.collection('web_sessions').doc(_connectedSessionId).update({
        'status': 'disconnected',
        'disconnectedAt': Timestamp.fromDate(DateTime.now()),
      });
      setState(() {
        _activeSession = null;
        _connectedSessionId = null;
        _isScanning = true;
      });
      _scannerController?.start();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disconnected from Web version'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      // ignore
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0221) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final cardColor = isDark ? const Color(0xFF1A1040) : const Color(0xFFF5F0FF);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor), onPressed: () => context.pop()),
        title: Text('Link with Web Version', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active Connection Card
          if (_activeSession != null) _buildActiveConnection(cardColor, textColor, isDark),
          if (_activeSession != null) const SizedBox(height: 16),

          // QR Scanner Section
          if (_isScanning) _buildScannerSection(cardColor, textColor, isDark),
          if (_isScanning) const SizedBox(height: 16),

          // Connection History
          _buildHistorySection(cardColor, textColor, isDark),
        ],
      ),
    );
  }

  Widget _buildActiveConnection(Color cardColor, Color textColor, bool isDark) {
    final session = _activeSession!;
    final connectedAt = (session['connectedAt'] as Timestamp?)?.toDate();
    final lastActive = (session['lastActive'] as Timestamp?)?.toDate();

    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Connected to Web', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.computer_rounded, 'Device', session['deviceInfo'] ?? 'Web Browser', textColor),
            if (connectedAt != null)
              _buildInfoRow(Icons.access_time_rounded, 'Connected', DateFormat('MMM d, yyyy • h:mm a').format(connectedAt), textColor),
            if (lastActive != null)
              _buildInfoRow(Icons.update_rounded, 'Last Active', DateFormat('h:mm a').format(lastActive), textColor),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off_rounded, size: 18),
                label: const Text('Disconnect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerSection(Color cardColor, Color textColor, bool isDark) {
    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.qr_code_scanner_rounded, size: 48, color: const Color(0xFF7C4DFF)),
            const SizedBox(height: 12),
            Text('Scan QR Code', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'Open prepora-web.vercel.app on your computer\nand scan the QR code shown there',
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 13),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 250,
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _onQRDetected,
                ),
              ),
            ),
            if (_isConnecting) ...[
              const SizedBox(height: 12),
              const CircularProgressIndicator(color: Color(0xFF7C4DFF)),
              const SizedBox(height: 8),
              Text('Connecting...', style: TextStyle(color: textColor.withValues(alpha: 0.6))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: textColor.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 13)),
          Expanded(child: Text(value, style: TextStyle(color: textColor, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildHistorySection(Color cardColor, Color textColor, bool isDark) {
    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: textColor.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Text('Connection History', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            if (_connectionHistory.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No connections yet',
                    style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 14),
                  ),
                ),
              )
            else
              ..._connectionHistory.map((session) {
                final connectedAt = (session['connectedAt'] as Timestamp?)?.toDate();
                final disconnectedAt = (session['disconnectedAt'] as Timestamp?)?.toDate();
                final status = session['status'] ?? 'disconnected';
                final device = session['deviceInfo'] ?? 'Web Browser';
                final isActive = status == 'connected';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF00E676).withValues(alpha: 0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? const Color(0xFF00E676).withValues(alpha: 0.3) : textColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF00E676) : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(device, style: TextStyle(color: textColor, fontWeight: FontWeight.w500, fontSize: 14)),
                            if (connectedAt != null)
                              Text(
                                DateFormat('MMM d, yyyy • h:mm a').format(connectedAt),
                                style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        isActive ? 'Active' : 'Ended',
                        style: TextStyle(
                          color: isActive ? const Color(0xFF00E676) : textColor.withValues(alpha: 0.4),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
