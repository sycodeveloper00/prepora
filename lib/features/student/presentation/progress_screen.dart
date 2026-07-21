import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _activities = [];
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      FirebaseService.getStudentActivity(),
      FirebaseService.getStudentActivityStats(),
    ]);
    if (mounted) setState(() {
      _activities = results[0] as List<Map<String, dynamic>>;
      _stats = results[1] as Map<String, dynamic>;
      _loading = false;
    });
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12AM';
    if (hour == 12) return '12PM';
    if (hour < 12) return '${hour}AM';
    return '${hour - 12}PM';
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'lecture': return 'Lecture';
      case 'file': return 'File';
      case 'mocktest_url': return 'Mock Test';
      case 'mocktest_code': return 'Mock Test';
      default: return type;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'lecture': return Icons.play_circle_outline_rounded;
      case 'file': return Icons.insert_drive_file_outlined;
      case 'mocktest_url': return Icons.quiz_rounded;
      case 'mocktest_code': return Icons.quiz_rounded;
      default: return Icons.article_outlined;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'lecture': return Colors.redAccent;
      case 'file': return const Color(0xFF00B8D4);
      case 'mocktest_url': return Colors.orange;
      case 'mocktest_code': return Colors.orange;
      default: return Colors.grey;
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final a in _activities) {
      final date = a['date'] as String? ?? 'Unknown';
      map.putIfAbsent(date, () => []).add(a);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black45;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
    final bgColor = isDark ? const Color(0xFF0D0D2E) : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        title: Text('My Progress', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: ProfessionalLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatsGraph(isDark, textColor, hintColor, cardColor),
                  const SizedBox(height: 16),
                  _buildActivityList(isDark, textColor, hintColor, cardColor),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsGraph(bool isDark, Color textColor, Color hintColor, Color cardColor) {
    final totalOpens = _stats['totalOpens'] as int? ?? 0;
    final uniqueFiles = _stats['uniqueFiles'] as int? ?? 0;
    final activeDays = _stats['activeDays'] as int? ?? 0;
    final typeCounts = _stats['typeCounts'] as Map<String, dynamic>? ?? {};
    final maxCount = typeCounts.values.fold<int>(0, (max, v) => v > max ? v as int : max);

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, color: const Color(0xFF4A148C), size: 22),
                const SizedBox(width: 8),
                Text('Activity Overview', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statItem('Total Opens', '$totalOpens', Icons.touch_app_rounded, const Color(0xFF4A148C), isDark),
                _statItem('Unique Files', '$uniqueFiles', Icons.folder_open_rounded, const Color(0xFF00B8D4), isDark),
                _statItem('Active Days', '$activeDays', Icons.calendar_today_rounded, Colors.teal, isDark),
              ],
            ),
            if (typeCounts.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('By Content Type', style: TextStyle(color: hintColor, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ...typeCounts.entries.map((e) {
                final count = e.value as int;
                final ratio = maxCount > 0 ? count / maxCount : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(_typeIcon(e.key), color: _typeColor(e.key), size: 18),
                      const SizedBox(width: 8),
                      SizedBox(width: 80, child: Text(_typeLabel(e.key), style: TextStyle(color: textColor, fontSize: 12))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: isDark ? Colors.white10 : Colors.black12,
                            valueColor: AlwaysStoppedAnimation(_typeColor(e.key)),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$count', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color, bool isDark) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 11)),
      ],
    );
  }

  Widget _buildActivityList(bool isDark, Color textColor, Color hintColor, Color cardColor) {
    if (_activities.isEmpty) {
      return Card(
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 48, color: hintColor),
                const SizedBox(height: 12),
                Text('No activity yet', style: TextStyle(color: hintColor, fontSize: 14)),
                const SizedBox(height: 4),
                Text('Start exploring content to track your progress', style: TextStyle(color: hintColor, fontSize: 12), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    final grouped = _groupByDate();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded, color: const Color(0xFF4A148C), size: 20),
            const SizedBox(width: 8),
            Text('Recent Activity', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 12),
        ...grouped.entries.map((entry) {
          final date = entry.key;
          final items = entry.value;
          final displayDate = _formatDate(date);
          return Card(
            color: cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A148C).withValues(alpha: 0.08),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 14, color: const Color(0xFF4A148C)),
                      const SizedBox(width: 8),
                      Text(displayDate, style: const TextStyle(color: Color(0xFF4A148C), fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      Text('${items.length} item(s)', style: TextStyle(color: hintColor, fontSize: 11)),
                    ],
                  ),
                ),
                ...items.map((a) {
                  final name = a['name'] as String? ?? '';
                  final type = a['type'] as String? ?? 'file';
                  final hour = a['hour'] as int? ?? 0;
                  final folderName = a['folderName'] as String? ?? '';
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _typeColor(type).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_typeIcon(type), color: _typeColor(type), size: 20),
                    ),
                    title: Text(name, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${_typeLabel(type)}${folderName.isNotEmpty ? ' · $folderName' : ''}',
                      style: TextStyle(color: hintColor, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_formatHour(hour), style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _formatDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length != 3) return dateStr;
      final date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      if (date == today) return 'Today';
      if (date == yesterday) return 'Yesterday';
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}
