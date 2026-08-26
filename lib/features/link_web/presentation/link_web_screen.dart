import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'dart:io' show Platform;
import '../../../core/services/firebase_service.dart';

class LinkWebScreen extends StatefulWidget {
  const LinkWebScreen({super.key});
  @override
  State<LinkWebScreen> createState() => _LinkWebScreenState();
}

class _LinkWebScreenState extends State<LinkWebScreen> {
  MobileScannerController? _scannerController;
  bool _showScanner = false;
  bool _isConnecting = false;
  List<Map<String, dynamic>> _activeSessions = [];
  List<Map<String, dynamic>> _connectionHistory = [];
  StreamSubscription? _activeSub;
  StreamSubscription? _historySub;
  Timer? _staleCheckTimer;

  static const int _maxWebSessions = 3;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    _loadActiveSessions();
    _loadConnectionHistory();
    _startStaleCheck();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _activeSub?.cancel();
    _historySub?.cancel();
    _staleCheckTimer?.cancel();
    super.dispose();
  }

  void _startStaleCheck() {
    _staleCheckTimer?.cancel();
    _staleCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkStaleSessions();
    });
  }

  Future<void> _checkStaleSessions() async {
    final user = FirebaseService.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    for (final session in _activeSessions) {
      final lastActive = (session['lastActive'] as Timestamp?)?.toDate();
      if (lastActive == null) continue;
      final elapsed = now.difference(lastActive);
      if (elapsed.inMinutes >= 60) {
        final sid = session['sessionId'] as String?;
        if (sid != null) {
          await _disconnectSession(sid);
          try {
            await FirebaseService.addTargetedNotification(
              user.uid,
              'Web app disconnected due to no activity found',
            );
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Web app disconnected due to no activity found'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    }
  }

  void _loadActiveSessions() {
    final user = FirebaseService.currentUser;
    if (user == null) return;
    _activeSub?.cancel();
    _activeSub = FirebaseService.firestore
        .collection('web_sessions')
        .where('uid', isEqualTo: user.uid)
        .where('status', isEqualTo: 'connected')
        .snapshots()
        .listen((snap) {
      final sessions = snap.docs.map((d) => {
        ...d.data(),
        'sessionId': d.id,
      }).toList();
      if (mounted) {
        setState(() {
          _activeSessions = sessions;
          if (sessions.length >= _maxWebSessions && _showScanner) {
            _showScanner = false;
            _scannerController?.stop();
            _scannerController?.dispose();
            _scannerController = null;
          }
        });
      }
    });
  }

  void _loadConnectionHistory() {
    final user = FirebaseService.currentUser;
    if (user == null) return;
    _historySub?.cancel();
    _historySub = FirebaseService.firestore
        .collection('web_sessions')
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        final sessions = snap.docs.map((d) => {
          ...d.data(),
          'sessionId': d.id,
        }).toList();
        sessions.sort((a, b) {
          final aT = (a['connectedAt'] as Timestamp?)?.toDate();
          final bT = (b['connectedAt'] as Timestamp?)?.toDate();
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return bT.compareTo(aT);
        });
        setState(() {
          _connectionHistory = sessions.take(20).toList();
        });
      }
    });
  }

  void _toggleScanner() {
    if (_activeSessions.length >= _maxWebSessions) {
      _showMaxLimitDialog();
      return;
    }
    setState(() => _showScanner = !_showScanner);
    if (_showScanner) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scannerController?.start();
      });
    } else {
      _scannerController?.stop();
      _scannerController?.dispose();
      _scannerController = null;
    }
  }

  void _showMaxLimitDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;

    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.devices_other_rounded, color: Colors.orange, size: 36),
            ),
            const SizedBox(height: 16),
            Text('Maximum Limit Reached', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'You can connect up to $_maxWebSessions web apps at a time.\nDisconnect an existing session first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: dimColor, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('OK', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _onQRDetected(BarcodeCapture capture) {
    if (!_showScanner || _isConnecting) return;
    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!).inSeconds < 2) return;
    _lastScanTime = now;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final raw = barcode.rawValue!;

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
        setState(() { _isConnecting = false; _showScanner = true; });
        _scannerController?.start();
        return;
      }

      final sessionData = sessionSnap.data()!;
      if (sessionData['status'] == 'connected' && sessionData['uid'] != user.uid) {
        _showError('This QR code is already linked to another account.');
        setState(() { _isConnecting = false; _showScanner = true; });
        _scannerController?.start();
        return;
      }

      if (sessionData['status'] == 'connected' && sessionData['uid'] == user.uid) {
        _showError('Already connected to this session.');
        setState(() { _isConnecting = false; _showScanner = false; });
        _scannerController?.stop();
        _scannerController?.dispose();
        _scannerController = null;
        return;
      }

      final userDoc = await FirebaseService.firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();

      final deviceModel = _getDeviceModel();
      final deviceId = await FirebaseService.getDeviceId();

      await sessionDoc.set({
        'uid': user.uid,
        'userName': userData?['name'] ?? user.displayName ?? 'Student',
        'userEmail': userData?['email'] ?? user.email ?? '',
        'userRole': userData?['role'] ?? 'student',
        'status': 'connected',
        'connectedAt': Timestamp.fromDate(DateTime.now()),
        'lastActive': Timestamp.fromDate(DateTime.now()),
        'deviceInfo': 'Mobile App',
        'androidDeviceModel': deviceModel,
        'androidDeviceId': deviceId,
      }, SetOptions(merge: true));

      // Mirror to Supabase so web side detects the connection
      try {
        await FirebaseService.mirrorWebSession(sessionId, {
          'uid': user.uid,
          'userName': userData?['name'] ?? user.displayName ?? 'Student',
          'userEmail': userData?['email'] ?? user.email ?? '',
          'userRole': userData?['role'] ?? 'student',
          'status': 'connected',
          'connectedAt': DateTime.now().toIso8601String(),
          'lastActive': DateTime.now().toIso8601String(),
          'deviceInfo': 'Mobile App',
          'androidDeviceModel': deviceModel,
          'androidDeviceId': deviceId,
        });
      } catch (_) {}

      setState(() {
        _isConnecting = false;
        _showScanner = false;
      });
      _scannerController?.stop();
      _scannerController?.dispose();
      _scannerController = null;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected to Web version!'), backgroundColor: Color(0xFF00E676)),
        );
      }
    } catch (e) {
      final msg = e.toString().contains('permission-denied')
          ? 'Permission denied. Check Firestore rules for web_sessions.'
          : 'Connection failed: ${e.toString().length > 80 ? e.toString().substring(0, 80) : e}';
      _showError(msg);
      setState(() { _isConnecting = false; _showScanner = true; });
      _scannerController?.start();
    }
  }

  Future<void> _disconnectSession(String sessionId) async {
    try {
      await FirebaseService.firestore.collection('web_sessions').doc(sessionId).update({
        'status': 'disconnected',
        'disconnectedAt': Timestamp.fromDate(DateTime.now()),
      });
      try {
        await FirebaseService.mirrorWebSession(sessionId, {
          'status': 'disconnected',
          'disconnectedAt': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disconnected from Web version'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      // ignore
    }
  }

  /// Professional confirmation popup before disconnecting a single web session.
  Future<void> _confirmDisconnectSession(String sessionId, String webBrowser) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (d) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xFFC62828), Color(0xFFFF7043)]),
                  boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 2)],
                ),
                child: const Icon(Icons.link_off_rounded, size: 34, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                'Disconnect Web App?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1A0533),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You are about to disconnect from $webBrowser.\n\n'
                'Your connected web app will stop working immediately and you will need to scan the QR code again to reconnect.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(d, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: (isDark ? Colors.white : Colors.black54).withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Cancel', style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(d, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Yes, Disconnect', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) _disconnectSession(sessionId);
  }

  Future<void> _disconnectAll() async {
    for (final session in _activeSessions) {
      final sid = session['sessionId'] as String?;
      if (sid != null) {
        await FirebaseService.firestore.collection('web_sessions').doc(sid).update({
          'status': 'disconnected',
          'disconnectedAt': Timestamp.fromDate(DateTime.now()),
        });
        try {
          await FirebaseService.mirrorWebSession(sid, {
            'status': 'disconnected',
            'disconnectedAt': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All sessions disconnected'), backgroundColor: Colors.orange),
      );
    }
  }

  String _getDeviceModel() {
    try {
      final model = Platform.environment['PRODUCT'] ?? 'Android';
      final brand = Platform.environment['BRAND'] ?? '';
      return brand.isNotEmpty ? '$brand $model' : model;
    } catch (_) {
      return 'Android Device';
    }
  }

  String _getDeviceId() {
    try {
      final id = Platform.environment['ANDROID_SERIAL'] ?? '';
      if (id.isNotEmpty) return id;
    } catch (_) {}
    return 'unknown';
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor),
          onPressed: () {
            if (_showScanner) {
              setState(() => _showScanner = false);
              _scannerController?.stop();
              _scannerController?.dispose();
              _scannerController = null;
            } else {
              context.pop();
            }
          },
        ),
        title: Text('Link with Web Version', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        actions: [
          if (_activeSessions.isNotEmpty && _activeSessions.length < _maxWebSessions)
            IconButton(
              onPressed: _toggleScanner,
              icon: Icon(
                _showScanner ? Icons.close_rounded : Icons.qr_code_scanner_rounded,
                color: _showScanner ? Colors.orange : const Color(0xFF7C4DFF),
              ),
              tooltip: _showScanner ? 'Close Scanner' : 'Scan QR Code',
            ),
          if (_activeSessions.isNotEmpty && _activeSessions.length >= _maxWebSessions)
            IconButton(
              onPressed: _showMaxLimitDialog,
              icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white24),
              tooltip: 'Max 3 web apps connected',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Scanner overlay
          if (_showScanner) ...[
            _buildScannerSection(cardColor, textColor, isDark),
            const SizedBox(height: 16),
          ],

          // Active connection cards
          if (_activeSessions.isNotEmpty) ...[
            _buildActiveSessionsHeader(textColor),
            const SizedBox(height: 12),
            ..._activeSessions.map((session) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildActiveConnectionCard(session, cardColor, textColor, isDark),
            )),
            const SizedBox(height: 8),
          ],

          // Empty state + scanner prompt
          if (_activeSessions.isEmpty && !_showScanner) ...[
            _buildEmptyState(cardColor, textColor, isDark),
            const SizedBox(height: 16),
          ],

          // Connection History
          _buildHistorySection(cardColor, textColor, isDark),
        ],
      ),
    );
  }

  Widget _buildActiveSessionsHeader(Color textColor) {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          'Connected (${_activeSessions.length}/$_maxWebSessions)',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const Spacer(),
        if (_activeSessions.length > 1)
          TextButton.icon(
            onPressed: () async {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final confirm = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (d) => Dialog(
                  backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(colors: [Color(0xFFC62828), Color(0xFFFF7043)]),
                            boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 2)],
                          ),
                          child: const Icon(Icons.link_off_rounded, size: 34, color: Colors.white),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Disconnect All?',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A0533)),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'You are about to disconnect ${_activeSessions.length} connected web app${_activeSessions.length > 1 ? 's' : ''}.\n\n'
                          'All connected web apps will stop working immediately and you will need to scan the QR code again to reconnect.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, height: 1.5, color: isDark ? Colors.white70 : Colors.black54),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(d, false),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: (isDark ? Colors.white : Colors.black54).withValues(alpha: 0.4)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text('Cancel', style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(d, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Yes, Disconnect All', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
              if (confirm == true) _disconnectAll();
            },
            icon: const Icon(Icons.link_off_rounded, size: 16, color: Colors.redAccent),
            label: const Text('Disconnect All', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildActiveConnectionCard(Map<String, dynamic> session, Color cardColor, Color textColor, bool isDark) {
    final connectedAt = (session['connectedAt'] as Timestamp?)?.toDate();
    final lastActive = (session['lastActive'] as Timestamp?)?.toDate();
    final sessionId = session['sessionId'] as String? ?? '';
    final webBrowser = session['webBrowser'] as String? ?? 'Chrome';

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.3)),
      ),
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
                const Spacer(),
                Icon(Icons.language_rounded, color: textColor.withValues(alpha: 0.3), size: 20),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.computer_rounded, 'Device', webBrowser, textColor),
            _buildInfoRow(Icons.access_time_rounded, 'Last Active',
                lastActive != null ? DateFormat('h:mm a').format(lastActive) : 'N/A', textColor),
            if (connectedAt != null)
              _buildInfoRow(Icons.link_rounded, 'Connected', DateFormat('MMM d, yyyy • h:mm a').format(connectedAt), textColor),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmDisconnectSession(sessionId, webBrowser),
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

  Widget _buildEmptyState(Color cardColor, Color textColor, bool isDark) {
    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.qr_code_scanner_rounded, size: 56, color: const Color(0xFF7C4DFF).withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text('No Web Connections', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Connect to PrePora Web by scanning a QR code.\nTap the scan button above to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _toggleScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: const Text('Scan QR Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF7C4DFF), size: 20),
                const SizedBox(width: 8),
                Text('Scan QR Code', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Text(
                  '${_activeSessions.length}/$_maxWebSessions',
                  style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 250,
                child: Stack(
                  children: [
                    MobileScanner(
                      key: ValueKey(_scannerController),
                      controller: _scannerController,
                      onDetect: _onQRDetected,
                      fit: BoxFit.cover,
                    ),
                    // Scanner overlay frame
                    Center(
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.6), width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    // Bottom text
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Point camera at QR code on PrePora Web',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                        ),
                      ),
                    ),
                  ],
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                final status = session['status'] ?? 'disconnected';
                final webBrowser = session['webBrowser'] as String? ?? 'Web Browser';
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
                            Text(webBrowser, style: TextStyle(color: textColor, fontWeight: FontWeight.w500, fontSize: 14)),
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
