import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';
import '../../../core/widgets/gender_badge.dart';

class StudentProgressScreen extends StatefulWidget {
  final String? targetUid;
  const StudentProgressScreen({super.key, this.targetUid});
  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> {
  bool _loadingUser = true;
  bool _isVerified = false;
  bool _isBlocked = false;
  String _email = '';
  String _studentName = '';
  String _gender = '';
  List<Map<String, dynamic>> _feedbacks = [];
  String get _uid => widget.targetUid ?? FirebaseService.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (_uid.isEmpty) return;
    final userData = await FirebaseService.getUserData(_uid);
    final feedbacks = await FirebaseService.getStudentFeedbacks(_uid);
    if (mounted) setState(() {
      _isVerified = userData?['verified'] == true;
      _isBlocked = userData?['blocked'] == true;
      _email = userData?['email'] as String? ?? '';
      _studentName = userData?['name'] as String? ?? '';
      _gender = userData?['gender'] as String? ?? '';
      _feedbacks = feedbacks;
      _loadingUser = false;
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
      case 'lecture': return 'Recorded Lecture';
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

  String _dateFromTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  Map<String, dynamic> _calculateStats(List<QueryDocumentSnapshot> docs) {
    int totalSeconds = 0;
    int lectureCount = 0, fileCount = 0, mockCount = 0;
    final uniqueFiles = <String>{};
    final activeDays = <String>{};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = data['name'] as String? ?? '';
      final type = data['type'] as String? ?? 'file';
      final startedAt = data['startedAt'] as Timestamp?;
      final endedAt = data['endedAt'] as Timestamp?;

      uniqueFiles.add(name);
      final dateStr = _dateFromTimestamp(startedAt);
      if (dateStr.isNotEmpty) activeDays.add(dateStr);

      if (type == 'lecture') lectureCount++;
      else if (type == 'file') fileCount++;
      else mockCount++;

      if (startedAt != null && endedAt != null) {
        totalSeconds += endedAt.seconds - startedAt.seconds;
      }
    }

    return {
      'totalOpens': docs.length,
      'uniqueFiles': uniqueFiles.length,
      'activeDays': activeDays.length,
      'totalMinutes': totalSeconds ~/ 60,
      'lectureCount': lectureCount,
      'fileCount': fileCount,
      'mockCount': mockCount,
    };
  }

  List<int> _getWeeklyData(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    final counts = List.filled(7, 0);
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final startedAt = data['startedAt'] as Timestamp?;
      if (startedAt == null) continue;
      final d = startedAt.toDate();
      final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
      if (diff >= 0 && diff < 7) counts[6 - diff]++;
    }
    return counts;
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(List<QueryDocumentSnapshot> docs) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final startedAt = data['startedAt'] as Timestamp?;
      final dateStr = _dateFromTimestamp(startedAt);
      map.putIfAbsent(dateStr.isEmpty ? 'Unknown' : dateStr, () => []).add(data);
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
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.targetUid != null ? (_studentName.isNotEmpty ? _studentName : 'Student') : 'My Progress',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (widget.targetUid != null && _gender.isNotEmpty) ...[
              const SizedBox(width: 6),
              GenderBadge(gender: _gender, size: 18),
            ],
          ],
        ),
      ),
      body: _loadingUser
          ? const Center(child: ProfessionalLoader())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getStudentActivities(_uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.redAccent)));
                }
                if (!snapshot.hasData) return const Center(child: ProfessionalLoader());
                final docs = snapshot.data!.docs;
                final stats = _calculateStats(docs);
                final weeklyData = _getWeeklyData(docs);
                final grouped = _groupByDate(docs);

                return RefreshIndicator(
                  onRefresh: () async { await _loadUserData(); },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatusBubbles(isDark, textColor, hintColor, cardColor),
                      const SizedBox(height: 16),
                      _buildStatsCard(isDark, textColor, cardColor, stats),
                      const SizedBox(height: 16),
                      _buildWeeklyChart(isDark, textColor, hintColor, cardColor, weeklyData),
                      const SizedBox(height: 16),
                      _buildActivityList(isDark, textColor, hintColor, cardColor, grouped),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusBubbles(bool isDark, Color textColor, Color hintColor, Color cardColor, {bool? verifiedOverride, bool? blockedOverride}) {
    final isVerified = verifiedOverride ?? _isVerified;
    final isBlocked = blockedOverride ?? _isBlocked;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: isVerified ? () => _showFeeDetailsDialog(context) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isVerified ? Colors.green.withValues(alpha: 0.1) : Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isVerified ? Colors.green.withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3), width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isVerified ? Colors.green : Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(isVerified ? Icons.verified_rounded : Icons.cancel_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fee Verified', style: TextStyle(color: isVerified ? Colors.green : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(isVerified ? 'Tap for details' : 'Not verified', style: TextStyle(color: hintColor, fontSize: 10)),
                      ],
                    ),
                  ),
                  if (isVerified) Icon(Icons.chevron_right_rounded, color: Colors.green, size: 18),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: !isBlocked ? Colors.teal.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: !isBlocked ? Colors.teal.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: !isBlocked ? Colors.teal : Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(!isBlocked ? Icons.check_circle_rounded : Icons.block_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(!isBlocked ? 'Active Account' : 'Blocked', style: TextStyle(color: !isBlocked ? Colors.teal : Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text(!isBlocked ? 'Account active' : 'Account blocked', style: TextStyle(color: hintColor, fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard(bool isDark, Color textColor, Color cardColor, Map<String, dynamic> stats) {
    final totalMinutes = stats['totalMinutes'] as int? ?? 0;
    final totalOpens = stats['totalOpens'] as int? ?? 0;
    final activeDays = stats['activeDays'] as int? ?? 0;
    final lectureCount = stats['lectureCount'] as int? ?? 0;
    final fileCount = stats['fileCount'] as int? ?? 0;
    final mockCount = stats['mockCount'] as int? ?? 0;
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes.remainder(60);
    final timeStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: const Color(0xFF4A148C).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text('Activity Overview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _purpleStatItem('Total Time', timeStr, Icons.access_time_rounded),
              _purpleStatItem('Total Opens', '$totalOpens', Icons.touch_app_rounded),
              _purpleStatItem('Active Days', '$activeDays', Icons.calendar_today_rounded),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _miniStat(lectureCount, 'Lectures', Colors.redAccent),
              _miniStat(fileCount, 'Files', const Color(0xFF00B8D4)),
              _miniStat(mockCount, 'Mock Tests', Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _purpleStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }

  Widget _miniStat(int count, String label, Color color) {
    return Column(
      children: [
        Text('$count', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }

  Widget _buildWeeklyChart(bool isDark, Color textColor, Color hintColor, Color cardColor, List<int> weeklyData) {
    final maxVal = weeklyData.fold<int>(0, (m, v) => v > m ? v : m);
    final now = DateTime.now();
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

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
                Icon(Icons.bar_chart_rounded, color: const Color(0xFF4A148C), size: 20),
                const SizedBox(width: 8),
                Text('Weekly Activity', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final dayIdx = (now.weekday - 6 + i) % 7;
                  final count = weeklyData[i];
                  final barHeight = maxVal > 0 ? (count / maxVal) * 100.0 : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (count > 0)
                            Text('$count', style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Container(
                            height: max(barHeight, 4),
                            decoration: BoxDecoration(
                              color: count > 0 ? const Color(0xFF4A148C) : (isDark ? Colors.white10 : Colors.black12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(days[dayIdx], style: TextStyle(color: hintColor, fontSize: 10)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList(bool isDark, Color textColor, Color hintColor, Color cardColor, Map<String, List<Map<String, dynamic>>> grouped) {
    if (grouped.isEmpty) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded, color: const Color(0xFF4A148C), size: 20),
            const SizedBox(width: 8),
            Text('Activity History', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
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
                  final folderPath = a['folderPath'] as String? ?? '';
                  final startedAt = a['startedAt'] as Timestamp?;
                  final endedAt = a['endedAt'] as Timestamp?;
                  final startHour = startedAt != null ? startedAt.toDate().hour : 0;
                  final endHour = endedAt != null ? endedAt.toDate().hour : startHour;
                  final duration = (startedAt != null && endedAt != null)
                      ? endedAt.toDate().difference(startedAt.toDate())
                      : Duration.zero;
                  final timeRange = '${_formatHour(startHour)} - ${_formatHour(endHour)}';
                  final durationStr = _formatDuration(duration);

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
                      '${_typeLabel(type)}${folderPath.isNotEmpty ? ' · $folderPath' : ''}',
                      style: TextStyle(color: hintColor, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(timeRange, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)),
                        if (duration.inSeconds > 0)
                          Text(durationStr, style: TextStyle(color: hintColor, fontSize: 10)),
                      ],
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

  void _showFeeDetailsDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final dimColor = isDark ? Colors.white54 : Colors.black45;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final fillColor = isDark ? Colors.white10 : Colors.black12;

    final fields = <String, String>{};
    for (final fb in _feedbacks) {
      final message = fb['message'] as String? ?? '';
      if (message.contains('Account Owner') || message.contains('AccNo') || message.contains('Bank Name')) {
        for (final line in message.split('\n')) {
          final idx = line.indexOf(':');
          if (idx > 0) {
            final key = line.substring(0, idx).trim();
            final val = line.substring(idx + 1).trim();
            if (val.isNotEmpty) fields[key] = val;
          }
        }
        break;
      }
    }
    if (_email.isNotEmpty) fields.putIfAbsent('Email', () => _email);

    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Colors.green, size: 22),
            const SizedBox(width: 10),
            Text('Fee Details', style: TextStyle(color: baseColor, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_studentName.isNotEmpty)
                  _feeField('Student Name', _studentName, Icons.person_outline_rounded, baseColor, fillColor),
                ...fields.entries.map((e) =>
                  _feeField(e.key, e.value, _iconForField(e.key), baseColor, fillColor),
                ),
                if (fields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('No payment details found', style: TextStyle(color: dimColor, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(d),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Close', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  IconData _iconForField(String field) {
    final f = field.toLowerCase();
    if (f.contains('name') || f.contains('owner')) return Icons.person_outline_rounded;
    if (f.contains('email')) return Icons.email_outlined;
    if (f.contains('contact') || f.contains('phone')) return Icons.phone_outlined;
    if (f.contains('account') || f.contains('accno')) return Icons.account_balance_rounded;
    if (f.contains('bank')) return Icons.account_balance_wallet_outlined;
    if (f.contains('receipt')) return Icons.receipt_long_rounded;
    if (f.contains('city')) return Icons.location_city_outlined;
    if (f.contains('province')) return Icons.map_outlined;
    if (f.contains('course')) return Icons.school_outlined;
    if (f.contains('date')) return Icons.calendar_today_rounded;
    if (f.contains('time')) return Icons.access_time_rounded;
    return Icons.info_outline_rounded;
  }

  Widget _feeField(String label, String value, IconData icon, Color baseColor, Color fillColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF4A148C), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: baseColor.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(color: baseColor, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
