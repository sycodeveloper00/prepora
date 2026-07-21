import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
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
  bool _isVerified = false;
  bool _isBlocked = true;
  String _email = '';
  String _studentName = '';
  String _gender = '';
  List<Map<String, dynamic>> _feedbacks = [];
  bool _loadingUser = true;

  String get _uid => widget.targetUid ?? FirebaseService.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = _uid;
    if (uid.isEmpty) {
      if (mounted) setState(() => _loadingUser = false);
      return;
    }
    final userData = await FirebaseService.getUserData(uid);
    final feedbacks = await FirebaseService.getStudentFeedbacks(uid);
    if (mounted) {
      setState(() {
        _isVerified = userData?['verified'] == true;
        _isBlocked = userData?['blocked'] == true;
        _email = userData?['email'] as String? ?? '';
        _studentName = userData?['name'] as String? ?? '';
        _gender = userData?['gender'] as String? ?? '';
        _feedbacks = feedbacks;
        _loadingUser = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D0D2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white54 : Colors.black45;
    final isTargetUser = widget.targetUid != null;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isTargetUser ? '${_studentName.isNotEmpty ? _studentName : "Student"}' : 'My Progress',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (isTargetUser && _gender.isNotEmpty) ...[
              const SizedBox(width: 6),
              GenderBadge(gender: _gender, size: 18),
            ],
          ],
        ),
      ),
      body: _uid.isEmpty
          ? Center(child: Text('No student selected', style: TextStyle(color: dimColor)))
          : _loadingUser
              ? const Center(child: ProfessionalLoader())
              : StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getStudentActivities(_uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: ProfessionalLoader());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        _buildStatusBubbles(isDark, textColor, dimColor),
                        const SizedBox(height: 40),
                        Icon(Icons.bar_chart_rounded, size: 64, color: dimColor),
                        const SizedBox(height: 12),
                        Text('No activity yet', style: TextStyle(color: dimColor, fontSize: 16)),
                        const SizedBox(height: 6),
                        Text('Start exploring content to see your progress', style: TextStyle(color: dimColor, fontSize: 13)),
                      ],
                    ),
                  );
                }
                final docs = snapshot.data!.docs.toList()
                  ..sort((a, b) {
                    final aTime = (a.data() as Map<String, dynamic>)['startedAt'] as Timestamp?;
                    final bTime = (b.data() as Map<String, dynamic>)['startedAt'] as Timestamp?;
                    return (bTime?.toDate() ?? DateTime(2000)).compareTo(aTime?.toDate() ?? DateTime(2000));
                  });
                return _buildContent(docs, textColor, dimColor, isDark);
              },
            ),
    );
  }

  Widget _buildContent(List<QueryDocumentSnapshot> docs, Color textColor, Color dimColor, bool isDark) {
    final totalCount = docs.length;
    final now = DateTime.now();
    final last7Days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    final dailyCounts = <int>[];
    for (final day in last7Days) {
      int count = 0;
      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
        if (startedAt != null &&
            startedAt.year == day.year &&
            startedAt.month == day.month &&
            startedAt.day == day.day) {
          count++;
        }
      }
      dailyCounts.add(count);
    }
    final maxCount = dailyCounts.reduce((a, b) => a > b ? a : b).toDouble();

    int totalMinutes = 0;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
      final endedAt = (data['endedAt'] as Timestamp?)?.toDate();
      if (startedAt != null && endedAt != null) {
        totalMinutes += endedAt.difference(startedAt).inMinutes;
      }
    }
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;

    final lectures = docs.where((d) => (d.data() as Map)['type'] == 'lecture').length;
    final files = docs.where((d) => (d.data() as Map)['type'] == 'file').length;
    final mockTests = docs.where((d) {
      final t = (d.data() as Map)['type'] as String? ?? '';
      return t.contains('mocktest');
    }).length;

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
      if (startedAt == null) continue;
      final key = DateFormat('EEE, MMM d, yyyy').format(startedAt);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add({...data, 'docId': doc.id});
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildStatusBubbles(isDark, textColor, dimColor),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF4A148C), const Color(0xFF7B1FA2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: const Color(0xFF4A148C).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _statItem(Icons.access_time_rounded, '${hours}h ${mins}m', 'Total Time', isDark),
                  _statItem(Icons.today_rounded, '$totalCount', 'Total Opens', isDark),
                  _statItem(Icons.calendar_today_rounded, '${grouped.length}', 'Active Days', isDark),
                ]),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _miniStat(Icons.play_circle_outline_rounded, '$lectures', 'Lectures', Colors.redAccent),
                  _miniStat(Icons.insert_drive_file_rounded, '$files', 'Files', Colors.blueAccent),
                  _miniStat(Icons.quiz_rounded, '$mockTests', 'Mock Tests', Colors.amber),
                ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.show_chart_rounded, color: const Color(0xFF00B8D4), size: 20),
              const SizedBox(width: 8),
              Text('Weekly Activity', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 8),
          Container(
            height: 180,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxCount < 1 ? 5 : (maxCount * 1.3).ceilToDouble(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIdx, rod, rodIdx) {
                      return BarTooltipItem(
                        '${rod.toY.toInt()} opens',
                        TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: maxCount < 5 ? 1 : (maxCount / 3).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        if (value == value.roundToDouble()) {
                          return Text('${value.toInt()}', style: TextStyle(color: dimColor, fontSize: 10));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < last7Days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(DateFormat('E').format(last7Days[idx]), style: TextStyle(color: dimColor, fontSize: 10)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxCount < 5 ? 1 : (maxCount / 3).ceilToDouble(),
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withValues(alpha: 0.08), strokeWidth: 1),
                ),
                barGroups: List.generate(7, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: dailyCounts[i].toDouble(),
                        width: 24,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        color: dailyCounts[i] > 0
                            ? const Color(0xFF00B8D4)
                            : (isDark ? Colors.white12 : Colors.black12),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.history_rounded, color: const Color(0xFF00B8D4), size: 20),
              const SizedBox(width: 8),
              Text('Activity History', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
          ),
          const SizedBox(height: 8),
          ...grouped.entries.map((entry) => _buildDateGroup(entry.key, entry.value, textColor, dimColor, isDark)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusBubbles(bool isDark, Color textColor, Color dimColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_isVerified) {
                  _showFeeDetailsDialog();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Your account is not verified yet. Contact support after payment.'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: _isVerified ? Colors.green.withValues(alpha: 0.1) : Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _isVerified ? Colors.green.withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _isVerified ? Colors.green.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_isVerified ? Icons.verified_rounded : Icons.cancel_rounded, color: _isVerified ? Colors.green : Colors.redAccent, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fee Verified', style: TextStyle(color: _isVerified ? Colors.green : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(_isVerified ? 'Verified' : 'Not Verified', style: TextStyle(color: dimColor, fontSize: 11)),
                        ],
                      ),
                    ),
                    if (_isVerified) Icon(Icons.chevron_right_rounded, color: Colors.green.withValues(alpha: 0.6), size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: !_isBlocked ? Colors.teal.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: !_isBlocked ? Colors.teal.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: !_isBlocked ? Colors.teal.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(!_isBlocked ? Icons.check_circle_rounded : Icons.block_rounded, color: !_isBlocked ? Colors.teal : Colors.orange, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Account Status', style: TextStyle(color: !_isBlocked ? Colors.teal : Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(!_isBlocked ? 'Active' : 'Blocked', style: TextStyle(color: dimColor, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFeeDetailsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? paymentMessage;
    for (final fb in _feedbacks) {
      final msg = fb['message'] as String? ?? '';
      if (msg.contains('Account Owner') || msg.contains('AccNo') || msg.contains('Bank Name')) {
        paymentMessage = msg;
        break;
      }
    }
    if (paymentMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('No payment details found'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      );
      return;
    }
    final fields = <String, String>{};
    for (final line in paymentMessage.split('\n')) {
      final idx = line.indexOf(':');
      if (idx != -1) {
        fields[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    }
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.verified_rounded, color: Colors.green, size: 20)),
          const SizedBox(width: 10),
          Text('Fee Details', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _feeDetailRow(Icons.email_rounded, 'Registered Email', _email, isDark),
            const Divider(height: 20),
            ...fields.entries.map((e) => _feeDetailRow(_iconForField(e.key), e.key, e.value, isDark)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text('Close', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)))],
      ),
    );
  }

  Widget _feeDetailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: const Color(0xFF00B8D4)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value.isNotEmpty ? value : '-', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }

  IconData _iconForField(String key) {
    final k = key.toLowerCase();
    if (k.contains('name') && !k.contains('bank') && !k.contains('owner')) return Icons.person_rounded;
    if (k.contains('email')) return Icons.email_rounded;
    if (k.contains('contact')) return Icons.phone_rounded;
    if (k.contains('owner')) return Icons.account_circle_rounded;
    if (k.contains('accno') || k.contains('account')) return Icons.account_balance_rounded;
    if (k.contains('bank')) return Icons.account_balance_wallet_rounded;
    if (k.contains('receipt')) return Icons.receipt_rounded;
    if (k.contains('city')) return Icons.location_city_rounded;
    if (k.contains('province')) return Icons.map_rounded;
    if (k.contains('course')) return Icons.school_rounded;
    if (k.contains('date')) return Icons.calendar_today_rounded;
    if (k.contains('time')) return Icons.access_time_rounded;
    return Icons.info_outline_rounded;
  }

  Widget _statItem(IconData icon, String value, String label, bool isDark) {
    return Column(children: [
      Icon(icon, color: Colors.white, size: 24),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
    ]);
  }

  Widget _miniStat(IconData icon, String value, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 4),
      Text('$value ', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
    ]);
  }

  Widget _buildDateGroup(String date, List<Map<String, dynamic>> items, Color textColor, Color dimColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(color: Color(0xFF00B8D4), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(date, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
          ),
          ...items.map((item) => _buildActivityItem(item, textColor, dimColor, isDark)),
        ],
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> item, Color textColor, Color dimColor, bool isDark) {
    final name = item['name'] as String? ?? 'Unknown';
    final type = item['type'] as String? ?? 'file';
    final folderPath = item['folderPath'] as String? ?? '';
    final startedAt = (item['startedAt'] as Timestamp?)?.toDate();
    final endedAt = (item['endedAt'] as Timestamp?)?.toDate();

    IconData icon;
    Color iconColor;
    switch (type) {
      case 'lecture':
        icon = Icons.play_circle_outline_rounded;
        iconColor = Colors.redAccent;
        break;
      case 'mocktest_url':
      case 'mocktest_code':
        icon = Icons.quiz_rounded;
        iconColor = Colors.amber;
        break;
      default:
        icon = Icons.insert_drive_file_rounded;
        iconColor = Colors.blueAccent;
    }

    String timeRange = '';
    String duration = '';
    if (startedAt != null) {
      final startStr = _formatTime(startedAt);
      if (endedAt != null) {
        final endStr = _formatTime(endedAt);
        timeRange = '$startStr - $endStr';
        final diff = endedAt.difference(startedAt);
        if (diff.inHours > 0) {
          duration = '${diff.inHours}h ${diff.inMinutes % 60}m';
        } else {
          duration = '${diff.inMinutes}m';
        }
      } else {
        timeRange = startStr;
      }
    }

    final typeLabel = type == 'lecture'
        ? 'Recorded Lecture'
        : type.contains('mocktest')
            ? 'Mock Test'
            : 'File';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                if (folderPath.isNotEmpty)
                  Text(folderPath, style: TextStyle(color: dimColor, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(typeLabel, style: TextStyle(color: iconColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (timeRange.isNotEmpty)
                Text(timeRange, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
              if (duration.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(duration, style: TextStyle(color: const Color(0xFF00B8D4), fontSize: 11)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $period';
  }
}
