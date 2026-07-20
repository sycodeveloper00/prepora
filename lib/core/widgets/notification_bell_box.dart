import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class NotificationBellBox extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  final VoidCallback? onClear;
  final bool showDelete;
  final ValueChanged<QueryDocumentSnapshot>? onDelete;

  const NotificationBellBox({
    super.key,
    required this.docs,
    this.onClear,
    this.showDelete = false,
    this.onDelete,
  });

  @override
  State<NotificationBellBox> createState() => _NotificationBellBoxState();
}

class _NotificationBellBoxState extends State<NotificationBellBox> {
  late List<QueryDocumentSnapshot> _docs;

  @override
  void initState() {
    super.initState();
    _docs = List.from(widget.docs)
      ..sort((a, b) {
        final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
        final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
        return (bTime?.toDate() ?? DateTime(0)).compareTo(aTime?.toDate() ?? DateTime(0));
      });
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1040) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.white54 : Colors.black45;
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 340,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(children: [
                Icon(Icons.notifications_none_rounded, color: mutedColor, size: 20),
                const SizedBox(width: 8),
                Text('Notifications', style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_docs.isNotEmpty && widget.showDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                    tooltip: 'Delete all',
                    onPressed: widget.onClear,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (_docs.isNotEmpty)
                  TextButton(
                    onPressed: widget.onClear,
                    child: Text('Clear all', style: TextStyle(color: mutedColor, fontSize: 12)),
                  ),
              ]),
            ),
            const Divider(height: 1),
            if (_docs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(children: [
                  Icon(Icons.notifications_off_rounded, size: 40, color: mutedColor.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text('No notifications yet', style: TextStyle(color: mutedColor, fontSize: 13)),
                ]),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _docs.length,
                  itemBuilder: (context, index) {
                    final data = _docs[index].data() as Map<String, dynamic>;
                    final message = data['message'] as String? ?? '';
                    final time = (data['createdAt'] as Timestamp?)?.toDate();
                    final isRead = data['read'] == true;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: !isRead ? (isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF5F0FF)) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: !isRead ? const Color(0xFF7C4DFF) : Colors.transparent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(message, style: TextStyle(color: textColor, fontSize: 13, fontWeight: !isRead ? FontWeight.w500 : FontWeight.normal)),
                                if (time != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(_timeAgo(time), style: TextStyle(color: mutedColor, fontSize: 11)),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.showDelete && widget.onDelete != null)
                            GestureDetector(
                              onTap: () => widget.onDelete!(_docs[index]),
                              child: Icon(Icons.close_rounded, color: mutedColor.withValues(alpha: 0.5), size: 16),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
