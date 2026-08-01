import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/widgets/glassmorphic_container.dart';
import '../../../core/widgets/animated_pressable.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/widgets/notification_bell_box.dart';
import '../../folders/presentation/folder_details_screen.dart' show GroupLinkDialog;
import '../../../core/utils.dart';
import '../../../core/widgets/professional_loader.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String? studentUid;
  final String? studentName;
  const AdminDashboardScreen({super.key, this.studentUid, this.studentName});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _folderNameController = TextEditingController();
  StreamSubscription? _feedbackSub;
  // Cached stream to prevent folder list from blinking on each rebuild
  late final Stream<QuerySnapshot> _folderStream;
  // Local docs for optimistic reorder — avoids snap-back on drag
  List<QueryDocumentSnapshot>? _localDocs;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final GlobalKey _bellKey = GlobalKey();
  OverlayEntry? _notifOverlay;

  @override
  void initState() {
    super.initState();
    _folderStream = FirebaseService.getAllFolders();
    _loadPendingCount();
    _listenNewFeedbacks();
  }

  void _markAllFeedbacksViewed() async {
    final snap = await FirebaseService.firestore
        .collection('feedbacks')
        .where('status', isEqualTo: 'pending')
        .where('viewed', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseService.firestore.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'viewed': true});
    }
    await batch.commit();
  }

  void _loadPendingCount() async {
    await FirebaseService.getPendingFeedbackCount();
  }

  void _listenNewFeedbacks() {
    _feedbackSub = FirebaseService.firestore
        .collection('feedbacks')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      final all = snap.docs.where((d) {
        final data = d.data();
        return data['viewed'] != true;
      }).toList();
      final count = all.length;
      NotificationService.setBadgeCount(count);
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final time = (data['createdAt'] as Timestamp?)?.toDate();
          if (time != null && DateTime.now().difference(time).inSeconds < 10) {
            NotificationService.showFeedbackNotification(
              data['name'] as String? ?? 'Student',
              data['message'] as String? ?? '',
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _feedbackSub?.cancel();
    _folderNameController.dispose();
    _notifOverlay?.remove();
    super.dispose();
  }

  void _showCreateFolderDialog() {
    _folderNameController.text = '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('New Folder', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: TextField(
          controller: _folderNameController, style: TextStyle(color: isDark ? Colors.white : Colors.black87), autofocus: true,
          decoration: InputDecoration(
            hintText: 'Folder name...', hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
            prefixIcon: const Icon(Icons.folder, color: Color(0xFF00B8D4)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (!debounce('folder_create')) return;
              final name = _folderNameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await FirebaseService.createRootFolder(name: name, color: '#4A148C');
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Assistant Management ───────────────────────────────────────────────────────

  void _showCreateAssistantDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController();
    Map<String, String>? creds;
    bool loading = false;
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [const Icon(Icons.person_add_rounded, color: Colors.orange), const SizedBox(width: 8), Text('New Assistant Account', style: TextStyle(color: baseColor, fontSize: 15))]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (creds == null)
              TextField(
                controller: nameCtrl, style: TextStyle(color: baseColor),
                decoration: InputDecoration(
                  hintText: 'Assistant name...', hintStyle: TextStyle(color: dimColor),
                  filled: true, fillColor: fillColor,
                  prefixIcon: const Icon(Icons.person, color: Colors.orange),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            if (creds != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withValues(alpha: 0.4))),
                child: Column(children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(height: 8),
                  Text('Email: ${creds!['email']}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Password: ${creds!['password']}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Share these credentials with the Assistant', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 11)),
                ]),
              ),
            if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: TextStyle(color: baseColor))),
            if (creds == null)
              ElevatedButton(
                onPressed: loading ? null : () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  setLocal(() { loading = true; error = null; });
                  try {
                    final result = await FirebaseService.createAssistantAccount(nameCtrl.text.trim());
                    setLocal(() { creds = result; loading = false; });
                  } catch (e) {
                    setLocal(() { error = e.toString(); loading = false; });
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                child: const Text('Create', style: TextStyle(color: Colors.white)),
              ),
          ],
        );
      }),
    );
  }

  void _showGrantAccessDialog(String folderId, String folderName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0533),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5, minChildSize: 0.3, maxChildSize: 0.7, expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.person_add_rounded, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Grant Access — $folderName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(
                icon: const Icon(Icons.person_add_rounded, color: Colors.orange, size: 28),
                tooltip: 'Add Assistant',
                onPressed: () { Navigator.pop(ctx); _showCreateAssistantDialog(); },
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getAllAssistant(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return Center(child: ProfessionalLoader());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_off_rounded, size: 48, color: Colors.white12),
                        const SizedBox(height: 12),
                        const Text('No Assistant yet', style: TextStyle(color: Colors.white38, fontSize: 14)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text('Create Assistant'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                          onPressed: () { Navigator.pop(ctx); _showCreateAssistantDialog(); },
                        ),
                      ],
                    ),
                  );
                }
                final docs = snapshot.data!.docs;
                return FutureBuilder<Set<String>>(
                  future: FirebaseService.getUidsWithFolderAccess(folderId),
                  builder: (context, accessSnap) {
                    if (accessSnap.connectionState == ConnectionState.waiting) return Center(child: ProfessionalLoader());
                    final grantedUids = accessSnap.data ?? {};
                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final uid = docs[index].id;
                        final name = data['name'] as String? ?? 'Unknown';
                        final email = data['email'] as String? ?? '';
                        final hasAccess = grantedUids.contains(uid);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: hasAccess ? Colors.green.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: hasAccess ? Colors.green.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(children: [
                            CircleAvatar(
                              backgroundColor: hasAccess ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
                              child: Icon(hasAccess ? Icons.check : Icons.person, color: hasAccess ? Colors.green : Colors.white54, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(email, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                            ])),
                            if (hasAccess)
                              ElevatedButton(
                                onPressed: () async {
                                  await FirebaseService.revokeAssistantAccess(uid, folderId);
                                  if (ctx.mounted) setState(() {});
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                                child: const Text('Denied', style: TextStyle(color: Colors.white, fontSize: 12)),
                              )
                            else
                              ElevatedButton(
                                onPressed: () async {
                                  await FirebaseService.grantAssistantAccess(uid, folderId, name);
                                  if (ctx.mounted) setState(() {});
                                },
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                                child: const Text('Grant', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                          ]),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Folder Lock ─────────────────────────────────────────────────────────────

  void _showFolderLockSheet(String folderId, String folderName, bool locked, bool updating, bool invisible) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [const Icon(Icons.lock_outline_rounded, color: Colors.orange, size: 20), const SizedBox(width: 8), Expanded(child: Text(folderName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)))]),
            const SizedBox(height: 20),
            _buildToggleRow('Lock Folder', 'Students cannot see this folder', Icons.lock_rounded, Colors.redAccent, locked, (val) async {
              await FirebaseService.toggleFolderLock(folderId, 'locked', val);
              if (val) {
                await FirebaseService.toggleFolderLock(folderId, 'updating', false);
                await FirebaseService.toggleFolderLock(folderId, 'invisible', false);
                setLocal(() { locked = val; updating = false; invisible = false; });
              } else {
                setLocal(() => locked = val);
              }
            }),
            const SizedBox(height: 12),
            _buildToggleRow('Show "Updating..."', 'Folder visible but shows Updating message', Icons.update_rounded, Colors.orange, updating, (val) async {
              await FirebaseService.toggleFolderLock(folderId, 'updating', val);
              if (val) {
                await FirebaseService.toggleFolderLock(folderId, 'locked', false);
                await FirebaseService.toggleFolderLock(folderId, 'invisible', false);
                setLocal(() { updating = val; locked = false; invisible = false; });
              } else {
                setLocal(() => updating = val);
              }
            }),
            const SizedBox(height: 12),
            _buildToggleRow('Invisible', 'Hide from students & Assistant', Icons.visibility_off_rounded, Colors.purple, invisible, (val) async {
              await FirebaseService.toggleFolderLock(folderId, 'invisible', val);
              if (val) {
                await FirebaseService.toggleFolderLock(folderId, 'locked', false);
                await FirebaseService.toggleFolderLock(folderId, 'updating', false);
                setLocal(() { invisible = val; locked = false; updating = false; });
              } else {
                setLocal(() => invisible = val);
              }
            }),
            const SizedBox(height: 16),
          ]);
        }),
      ),
    );
  }

  void _showAdminNotifications(BuildContext ctx, List<QueryDocumentSnapshot> docs) {
    FirebaseService.markAdminNotificationsRead();
    NotificationService.clearBadge();
    if (_notifOverlay != null) {
      _notifOverlay!.remove();
      _notifOverlay = null;
      return;
    }
    final renderBox = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final pos = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    _notifOverlay = OverlayEntry(
      builder: (overlayCtx) => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () { _notifOverlay?.remove(); _notifOverlay = null; },
            behavior: HitTestBehavior.translucent,
          ),
        ),
        Positioned(
          left: (pos.dx + size.width / 2 - 170).clamp(8.0, MediaQuery.of(ctx).size.width - 348.0),
          top: pos.dy + size.height + 8,
          child: NotificationBellBox(
            docs: docs,
            showDelete: true,
            onClear: () async {
              await FirebaseService.clearAdminNotifications();
              _notifOverlay?.remove();
              _notifOverlay = null;
            },
            onDelete: (doc) async {
              await doc.reference.delete();
            },
          ),
        ),
      ]),
    );
    Overlay.of(ctx).insert(_notifOverlay!);
  }

  Future<List<Map<String, dynamic>>> _fetchContentMatches(String query) async {
    final q = query.toLowerCase();
    final results = <Map<String, dynamic>>[];
    final foldersSnap = await FirebaseService.firestore.collection('folders').get();
    for (final folderDoc in foldersSnap.docs) {
      final data = folderDoc.data();
      if (data['invisible'] == true) continue;
      final folderName = data['name'] as String? ?? '';
      final folderId = folderDoc.id;
      // folderName match check removed — matching folders should NOT be skipped
      final contentsSnap = await FirebaseService.firestore.collection('folders').doc(folderId).collection('contents').get();
      for (final contentDoc in contentsSnap.docs) {
        final cData = contentDoc.data();
        final contentName = cData['name'] as String? ?? cData['title'] as String? ?? '';
        if (contentName.toLowerCase().contains(q)) {
          final type = cData['type'] as String?;
          results.add({'folderId': folderId, 'folderName': folderName, 'contentName': contentName, 'contentId': contentDoc.id, 'type': type ?? ''});
        }
      }
      if (results.length >= 50) break;
    }
    return results;
  }

  Widget _buildAdminSearchResults(List<QueryDocumentSnapshot> filteredFolders, List<QueryDocumentSnapshot> allDocs, List<Color> colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchContentMatches(_searchQuery),
      builder: (context, snap) {
        final contentMatches = snap.data ?? [];
        final totalItems = filteredFolders.length + contentMatches.length;
        if (totalItems == 0) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.search_off_rounded, size: 60, color: Colors.white12),
            const SizedBox(height: 16),
            const Text('No results found', style: TextStyle(color: Colors.white38, fontSize: 16)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index < filteredFolders.length) {
              final d = filteredFolders[index];
              final data = d.data() as Map<String, dynamic>;
              final folderId = d.id;
              final folderName = data['name'] as String? ?? 'Folder';
              final color = colors[index % colors.length];
              return Card(
                color: isDark ? const Color(0xFF1A0533) : Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.folder_rounded, color: color, size: 32),
                  title: Text(folderName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                  subtitle: Text('Folder match', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => context.push('/folders/$folderId', extra: {'canEdit': true, 'canManage': true, 'isAdmin': true, if (widget.studentUid != null) 'targetStudentUid': widget.studentUid}),
                ),
              );
            } else {
              final m = contentMatches[index - filteredFolders.length];
              final isSubfolder = m['type'] == 'subfolder';
              final path = isSubfolder
                  ? '/folders/${m['folderId']}/sub/${m['contentId']}'
                  : '/folders/${m['folderId']}';
              final label = isSubfolder ? 'subfolder' : 'file';
              return Card(
                color: isDark ? const Color(0xFF1A0533) : Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(isSubfolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded, color: isSubfolder ? Colors.amber : Colors.teal, size: 28),
                  title: Text(m['contentName'] as String? ?? '', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${m['folderName']} › $label', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => context.push(path, extra: {'canEdit': true, 'canManage': true, 'isAdmin': true}),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildAdminSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white38 : Colors.black45;
    final fillColor = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search folders...',
          hintStyle: TextStyle(color: hintColor, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: hintColor, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: hintColor, size: 18),
                  onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                )
              : null,
          filled: true, fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.08))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.08))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF00B8D4), width: 1.5)),
        ),
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  Widget _buildToggleRow(String title, String subtitle, IconData icon, Color color, bool value, Function(bool) onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 11)),
        ])),
        Switch(value: value, onChanged: onChanged, activeColor: color),
      ]),
    );
  }

  // ─── Content Methods ─────────────────────────────────────────────────────────

  void _showAddContentSheet(String folderId, String folderName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add to: $folderName', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 20),
            _buildContentOption(ctx, Icons.folder_rounded, Colors.blue, 'Sub-Folder', 'Create a sub-folder', () => _addSubFolder(ctx, folderId)),
            const SizedBox(height: 12),
            _buildContentOption(ctx, Icons.play_circle_fill_rounded, Colors.red, 'Recorded Lecture', 'Add YouTube video link', () => _addYouTubeLecture(ctx, folderId)),
            const SizedBox(height: 12),
            _buildContentOption(ctx, Icons.assignment_rounded, Colors.orange, 'Mock Test', 'Add URL or paste code', () => _addMockTest(ctx, folderId)),
            const SizedBox(height: 12),
            _buildContentOption(ctx, Icons.upload_file_rounded, Colors.teal, 'Upload File', 'Add file name and link', () => _addUploadFile(ctx, folderId)),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _buildContentOption(BuildContext ctx, IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle), child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)), Text(subtitle, style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12))]),
          const Spacer(),
          Icon(Icons.chevron_right, color: color.withValues(alpha: 0.6)),
        ]),
      ),
    );
  }

  void _addMockTest(BuildContext ctx, String folderId) {
    Navigator.pop(ctx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context, backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Add Mock Test', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 20),
          ListTile(leading: const Icon(Icons.link, color: Colors.orange), title: Text('Add URL', style: TextStyle(color: isDark ? Colors.white : Colors.black87)), onTap: () { Navigator.pop(ctx); _addMockTestUrl(folderId); }),
          const Divider(color: Colors.white12),
          ListTile(leading: const Icon(Icons.code, color: Colors.orange), title: Text('Paste a Code', style: TextStyle(color: isDark ? Colors.white : Colors.black87)), onTap: () { Navigator.pop(ctx); _addMockTestCode(folderId); }),
        ])),
      ),
    );
  }

  void _addMockTestUrl(String folderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController(text: 'Mock Test');
    final urlCtrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [const Icon(Icons.link, color: Colors.orange), const SizedBox(width: 8), Text('Mock Test URL', style: TextStyle(color: baseColor))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Test name...', Icons.title, isDark: isDark)),
        const SizedBox(height: 12),
        TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Paste URL...', Icons.link, isDark: isDark)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('save_mock_url')) return;
          if (nameCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.addFolderContent(folderId, {'type': 'mocktest_url', 'name': nameCtrl.text.trim(), 'url': urlCtrl.text.trim()});
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _addMockTestCode(String folderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController(text: 'Mock Test');
    final codeCtrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [const Icon(Icons.code, color: Colors.orange), const SizedBox(width: 8), Text('Mock Test Code', style: TextStyle(color: baseColor))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Test name...', Icons.title, isDark: isDark)),
        const SizedBox(height: 12),
        TextField(controller: codeCtrl, maxLines: 5, style: TextStyle(color: baseColor, fontFamily: 'monospace', fontSize: 13), decoration: InputDecoration(hintText: 'Paste code...', hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('save_mock_code')) return;
          if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.addFolderContent(folderId, {'type': 'mocktest_code', 'name': nameCtrl.text.trim(), 'code': codeCtrl.text.trim()});
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _addUploadFile(BuildContext ctx, String folderId) {
    Navigator.pop(ctx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Upload File', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.phone_android, color: Colors.blue),
              title: Text('Internal Storage', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text('Pick file from device', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
              onTap: () { Navigator.pop(context); _pickFileFromStorage(folderId); },
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            ListTile(
              leading: const Icon(Icons.cloud_upload_rounded, color: Colors.amber),
              title: Text('Google Drive', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text('Import from Google Drive', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
              onTap: () { Navigator.pop(context); _pickFileFromDrive(folderId); },
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.teal),
              title: Text('Paste URL', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text('Enter file link manually', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
              onTap: () { Navigator.pop(context); _addUploadFileUrl(folderId); },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _sendScopedNotification(String message, {String? folderId, String? parentContentId, Map<String, dynamic>? contentData}) async {
    if (widget.studentUid != null) {
      await FirebaseService.addTargetedNotification(widget.studentUid!, message, folderId: folderId, parentContentId: parentContentId, contentData: contentData);
    } else {
      await FirebaseService.addNotification(message, folderId: folderId, parentContentId: parentContentId, contentData: contentData);
    }
  }

  void _pickFileFromStorage(String folderId) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        await FirebaseService.addFolderContent(folderId, {'type': 'file', 'name': file.name, 'url': file.path ?? '', 'source': 'internal_storage'});
        await _sendScopedNotification('Uploaded file: ${file.name}', folderId: folderId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking file: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _pickFileFromDrive(String folderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.cloud_upload_rounded, color: Colors.amber), const SizedBox(width: 8), Text('Google Drive', style: TextStyle(color: baseColor))]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('File name...', Icons.title, isDark: isDark)),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Paste Drive link...', Icons.cloud, isDark: isDark)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (!debounce('save_drive')) return;
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              await FirebaseService.addFolderContent(folderId, {'type': 'file', 'name': nameCtrl.text.trim(), 'url': urlCtrl.text.trim(), 'source': 'google_drive'});
              await _sendScopedNotification('Uploaded from Drive: ${nameCtrl.text.trim()}', folderId: folderId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addUploadFileUrl(String folderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.link, color: Colors.teal), const SizedBox(width: 8), Text('Paste URL', style: TextStyle(color: baseColor))]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('File name...', Icons.title, isDark: isDark)),
          const SizedBox(height: 12),
          TextField(controller: linkCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('File URL or link...', Icons.link, isDark: isDark)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (!debounce('save_url_file')) return;
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              await FirebaseService.addFolderContent(folderId, {'type': 'file', 'name': nameCtrl.text.trim(), 'url': linkCtrl.text.trim(), 'source': 'url'});
              await _sendScopedNotification('Uploaded file: ${nameCtrl.text.trim()}', folderId: folderId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _groupLinkForFolder(BuildContext ctx, String folderId) {
    showDialog(
      context: ctx,
      builder: (d) => GroupLinkDialog(
        folderId: folderId,
        parentContentId: 'root',
      ),
    );
  }

  void _addSubFolder(BuildContext ctx, String parentFolderId) {
    Navigator.pop(ctx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('New Sub-Folder', style: TextStyle(color: baseColor)),
      content: TextField(controller: ctrl, autofocus: true, style: TextStyle(color: baseColor), decoration: _inputDec('Sub-folder name...', Icons.folder, isDark: isDark)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('create_subfolder')) return;
          if (ctrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.addFolderContent(parentFolderId, {'type': 'subfolder', 'name': ctrl.text.trim()});
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Create', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _addYouTubeLecture(BuildContext ctx, String folderId) {
    Navigator.pop(ctx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [const Icon(Icons.play_circle_fill_rounded, color: Colors.red), const SizedBox(width: 8), Text('Add Lecture', style: TextStyle(color: baseColor))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Lecture title...', Icons.title, isDark: isDark)),
        const SizedBox(height: 12),
        TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Paste YouTube link...', Icons.link, isDark: isDark)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('save_lecture')) return;
          if (titleCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.addFolderContent(folderId, {'type': 'lecture', 'name': titleCtrl.text.trim(), 'youtubeUrl': urlCtrl.text.trim()});
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  InputDecoration _inputDec(String hint, IconData icon, {bool isDark = true}) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38), prefixIcon: Icon(icon, color: isDark ? Colors.white54 : Colors.black54),
    filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  void _showRenameDialog(String folderId, String currentName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final ctrl = TextEditingController(text: currentName);
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Rename Folder', style: TextStyle(color: baseColor)),
      content: TextField(controller: ctrl, autofocus: true, style: TextStyle(color: baseColor), decoration: _inputDec('New name...', Icons.edit, isDark: isDark)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          if (ctrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.renameRootFolder(folderId, ctrl.text.trim());
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Rename', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 48, 12, 12),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Row(children: [
            Image.asset('assets/logo.png', height: 36, width: 36),
            const SizedBox(width: 12),
            if (widget.studentUid != null)
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white70 : const Color(0xFF1A0533), size: 20),
                onPressed: () => context.go('/admin'),
              ),
            Expanded(
              child: Text(
                widget.studentUid != null ? '${widget.studentName ?? 'Student'}\'s Panel' : 'Admin Console',
                style: TextStyle(fontSize: widget.studentUid != null ? 16 : 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A0533)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getAdminNotifications(),
              builder: (context, snap) {
                final unread = snap.hasData ? snap.data!.docs.where((d) => (d.data() as Map<String, dynamic>)['read'] == false).length : 0;
                return IconButton(
                  key: _bellKey,
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.notifications_none_rounded, color: isDark ? Colors.white70 : const Color(0xFF1A0533), size: 26),
                      if (unread > 0)
                        Positioned(
                          right: -4, top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () => _showAdminNotifications(this.context, snap.data?.docs ?? []),
                  tooltip: 'Notifications',
                );
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : const Color(0xFF1A0533), size: 28),
              color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onOpened: () { _loadPendingCount(); _markAllFeedbacksViewed(); },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'notices', child: Row(children: [Icon(Icons.campaign_rounded, size: 18, color: Colors.amber), SizedBox(width: 10), Text('Notice Board', style: TextStyle(color: isDark ? Colors.white : Colors.black87))])),
                PopupMenuItem(value: 'control_panel', child: Row(children: [Icon(Icons.admin_panel_settings_rounded, size: 18, color: Colors.cyan), SizedBox(width: 10), Text('Control Panel', style: TextStyle(color: isDark ? Colors.white : Colors.black87))])),
                    PopupMenuItem(value: 'feedbacks', child: Row(children: [Icon(Icons.support_agent_rounded, size: 18, color: Colors.orange), SizedBox(width: 10), Text('Contact Support', style: TextStyle(color: isDark ? Colors.white : Colors.black87))])),
                PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, size: 18, color: isDark ? Colors.white70 : Colors.black87), SizedBox(width: 10), Text('Settings', style: TextStyle(color: isDark ? Colors.white : Colors.black87))])),
              ],
              onSelected: (val) {
                switch (val) {
                  case 'notices': context.push('/admin/notices'); break;
                  case 'control_panel': context.push('/admin/control-panel'); break;
                  case 'feedbacks': context.push('/admin/feedbacks'); break;
                  case 'settings': context.push('/admin/settings'); break;
                }
              },
            ),
          ]),
        ),
        if (widget.studentUid != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF00B8D4).withValues(alpha: 0.15),
            child: Row(
              children: [
                const Icon(Icons.person_pin_rounded, color: Color(0xFF00B8D4), size: 16),
                const SizedBox(width: 8),
                Text(
                  'Controlling: ${widget.studentName ?? 'Student'} — changes are scoped to this student only',
                  style: const TextStyle(color: Color(0xFF00B8D4), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        _buildAdminSearchBar(),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _folderStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return Center(child: ProfessionalLoader());
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.folder_open_rounded, size: 80, color: Colors.white12),
                  const SizedBox(height: 16),
                  const Text('No folders yet', style: TextStyle(color: Colors.white38, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first folder', style: TextStyle(color: Colors.white24, fontSize: 13)),
                ]));
              }
              // Use optimistic local state if available, else sort from snapshot
              final rawDocs = snapshot.data!.docs;
              // Always re-sort from stream data (fixes rename not reflecting)
              _localDocs = List<QueryDocumentSnapshot>.from(rawDocs)
                ..sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aOrder = (aData['sortOrder'] as num?)?.toInt() ?? 9999;
                  final bOrder = (bData['sortOrder'] as num?)?.toInt() ?? 9999;
                  return aOrder.compareTo(bOrder);
                });
              final docs = _localDocs!;
              final colors = [Colors.purple, Colors.teal, Colors.blue, Colors.orange, Colors.pink, Colors.indigo];
              final filtered = _searchQuery.isNotEmpty
                  ? docs.where((d) {
      final data = d.data();
                      final name = (data != null && data is Map<String, dynamic> ? (data['name'] as String? ?? '') : '').toLowerCase();
                      return name.contains(_searchQuery.toLowerCase());
                    }).toList()
                  : docs;
              if (_searchQuery.isNotEmpty) {
                return _buildAdminSearchResults(filtered, snapshot.data!.docs, colors);
              }
              return ReorderableListView.builder(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
                itemCount: filtered.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex--;
                  final reordered = List<QueryDocumentSnapshot>.from(docs);
                  final moved = reordered.removeAt(oldIndex);
                  reordered.insert(newIndex, moved);
                  // Optimistic local update
                  setState(() => _localDocs = reordered);
                  // Save to Firestore
                  for (int i = 0; i < reordered.length; i++) {
                    await FirebaseService.firestore
                        .collection('folders')
                        .doc(reordered[i].id)
                        .update({'sortOrder': i}).catchError((_) {});
                  }
                },
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final data = filtered[index].data() as Map<String, dynamic>;
                  final folderId = filtered[index].id;
                  final folderName = data['name'] as String? ?? 'Folder';
                  final locked = data['locked'] as bool? ?? false;
                  final updating = data['updating'] as bool? ?? false;
                  final invisible = data['invisible'] as bool? ?? false;
                  final color = colors[index % colors.length];
                  return AnimatedPressable(
                    key: ValueKey(folderId),
                    onTap: () => context.push('/folders/$folderId', extra: {'canEdit': true, 'canManage': true, 'isAdmin': true, if (widget.studentUid != null) 'targetStudentUid': widget.studentUid}),
                    child: GestureDetector(
                      onLongPress: () {
                        showModalBottomSheet(
                          context: context, backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                          builder: (_) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(folderName, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            ListTile(leading: const Icon(Icons.drive_file_rename_outline_rounded, color: Colors.blue), title: Text('Rename', style: TextStyle(color: isDark ? Colors.white : Colors.black87)), onTap: () { Navigator.pop(context); _showRenameDialog(folderId, folderName); }),
                            ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), title: const Text('Delete', style: TextStyle(color: Colors.redAccent)), onTap: () { Navigator.pop(context); _confirmDelete(folderId, folderName); }),
                          ])),
                        );
                      },
                      child: GlassmorphicContainer(
                        padding: const EdgeInsets.all(0), margin: const EdgeInsets.only(bottom: 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                            child: Row(children: [
                              // 6-dot drag handle
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Icon(Icons.drag_indicator_rounded, color: isDark ? Colors.white38 : Colors.black38, size: 22),
                                ),
                              ),
                              Icon(Icons.folder_rounded, color: locked ? Colors.grey : color, size: 28),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(folderName, style: TextStyle(color: (locked || invisible) ? (isDark ? Colors.white38 : Colors.black45) : (isDark ? Colors.white : Colors.black87), fontWeight: FontWeight.bold, fontSize: 16)),
                                if (locked || updating || invisible)
                                  Text(locked ? '🔒 Locked' : (updating ? '🔄 Updating...' : '👻 Hidden'),
                                    style: TextStyle(
                                      color: locked ? Colors.redAccent : (updating ? Colors.orange : Colors.purple),
                                      fontSize: 11, fontWeight: FontWeight.bold,
                                    )),
                              ])),
                            ]),
                          ),
                          const Divider(color: Colors.white12, height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(children: [
                              _actionBtn(Icons.add_circle_outline, color, 'Add', () => _showAddContentSheet(folderId, folderName)),
                              _actionBtn(Icons.people_alt_rounded, Colors.orange, 'Assistant', () => _showGrantAccessDialog(folderId, folderName)),
                              _actionBtn(Icons.lock_outline_rounded, Colors.amber, 'Lock', () => _showFolderLockSheet(folderId, folderName, locked, updating, invisible)),
                              _actionBtn(Icons.groups_rounded, Colors.green, 'Group', () => _groupLinkForFolder(context, folderId)),
                              _actionBtn(Icons.open_in_new_rounded, Colors.blue, 'Open', () => context.push('/folders/$folderId', extra: {'canEdit': true, 'canManage': true, 'isAdmin': true, if (widget.studentUid != null) 'targetStudentUid': widget.studentUid})),
                              const Spacer(),
                              IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), onPressed: () => _confirmDelete(folderId, folderName), tooltip: 'Delete'),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton(
          heroTag: 'ai_chat_admin', onPressed: () => context.push('/ai_tutor'),
          backgroundColor: Colors.transparent, elevation: 0,
          child: Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: const Color(0xFF00B8D4).withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 2)]), child: ClipOval(child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover))),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'create_folder', onPressed: _showCreateFolderDialog,
          backgroundColor: const Color(0xFF4A148C),
          child: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
        ),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Column(children: [Icon(icon, color: color, size: 22), Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))])),
    );
  }

  void _confirmDelete(String folderId, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      title: Text('Delete Folder?', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
      content: Text('Delete "$name"? This cannot be undone.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async { Navigator.pop(d); await FirebaseService.deleteRootFolder(folderId); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
}
