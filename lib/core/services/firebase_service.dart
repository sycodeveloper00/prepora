import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart' as fb_storage;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthenticatedClient;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../firebase_options.dart';
import 'supabase_read_service.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  FirebaseService._();

  static bool _initialized = false;
  static String? _cachedDeviceId;
  static String? cachedRole;

  static String supabaseUrl = '';
  static String serviceRoleKey = '';
  static String _supabaseAnonKey = '';

  static String cleanTitle(String name) {
    var cleaned = name.replaceFirst(RegExp(r'^\d+_'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^\d{10,13}_'), '');
    cleaned = cleaned.trim();
    if (cleaned.isEmpty) cleaned = name;
    return cleaned;
  }

  /// Downloads a file from Supabase Storage using the REST API with service role auth.
  /// [bucketPath] format: "bucket_name/path/to/file"
  static Future<Uint8List> downloadSupabaseFile(String bucketPath) async {
    final uri = Uri.parse('$supabaseUrl/storage/v1/object/$bucketPath');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $serviceRoleKey'},
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Supabase download failed ($bucketPath): ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  static fb_auth.User? get currentUser => fb_auth.FirebaseAuth.instance.currentUser;

  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

  static SupabaseClient get supabase => Supabase.instance.client;

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    String? id;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      id = info.id;
    } catch (_) {}
    if (id == null || id.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      const key = 'device_uuid';
      id = prefs.getString(key);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await prefs.setString(key, id);
      }
    }
    _cachedDeviceId = id;
    return id;
  }

  static FirebaseService get instance => _instance;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).timeout(const Duration(seconds: 10));
    } catch (_) {}
    try {
      await _loadActiveSupabaseAccount().timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
      try {
        await Supabase.initialize(url: supabaseUrl, anonKey: _supabaseAnonKey).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _initialized = true;
  }

  static Future<void> _loadActiveSupabaseAccount() async {
    try {
      final snap = await firestore.collection('supabase_accounts').where('isActive', isEqualTo: true).limit(1).get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        supabaseUrl = data['projectUrl'] as String? ?? '';
        serviceRoleKey = data['serviceRoleKey'] as String? ?? '';
        _supabaseAnonKey = data['anonKey'] as String? ?? '';
      }
    } catch (_) {}
  }

  static Future<void> reinitializeSupabase() async {
    await _loadActiveSupabaseAccount();
    if (supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
      try {
        await Supabase.initialize(url: supabaseUrl, anonKey: _supabaseAnonKey);
      } catch (e) {
        debugPrint('[reinitializeSupabase] Failed: $e');
      }
    }
  }

  // ─── Auth ──────────────────────────────────────────────────────────────────────

  static Future<fb_auth.UserCredential?> signIn(String email, String password) async {
    try {
      final cred = await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (cred.user != null) {
        final userDoc = await firestore.collection('users').doc(cred.user!.uid).get();
        final userData = userDoc.data();
        final userRole = userData?['role'] as String?;
        if (userData?['blocked'] == true) {
          if (userRole == 'admin' || userRole == 'Assistant' || userRole == 'assistant') {
            await firestore.collection('users').doc(cred.user!.uid).update({'blocked': false});
          }
          // Students stay logged in; the dashboard shows a blocked banner
        }
        await storeSession(cred.user!.uid);
        final deviceId = await getDeviceId();
        await firestore.collection('users').doc(cred.user!.uid).update({
          'currentDeviceId': deviceId,
          'lastLoginAt': FieldValue.serverTimestamp(),
        });
        await _trackLogin(cred.user!.uid, deviceId);
        if (userRole != 'admin' && userRole != 'Assistant' && userRole != 'assistant') {
          final violation = await isMultiDeviceViolation(cred.user!.uid, deviceId);
          if (violation) {
            await firestore.collection('users').doc(cred.user!.uid).update({
              'blocked': true,
              'blockedReason': 'Multi-device violation: 3+ unique devices detected within 24 hours.',
              'blockedAt': FieldValue.serverTimestamp(),
            });
            await addAdminNotification('warning', 'AUTO-BLOCK: ${cred.user!.email} blocked for multi-device violation (3+ devices in 24h).', relatedUid: cred.user!.uid);
          }
        }
        await updateStreak(cred.user!.uid);
        final label = userRole == 'admin' ? 'Admin' : (userRole == 'Assistant' || userRole == 'assistant' ? 'Assistant' : 'Student');
        await addAdminNotification('login', '$label logged in: ${cred.user!.email}', relatedUid: cred.user!.uid);
      }
      return cred;
    } on fb_auth.FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Sign in failed');
    }
  }

  static Future<fb_auth.UserCredential?> signUp(
    String name,
    String email,
    String password, {
    String role = 'student',
    String gender = '',
  }) async {
    try {
      final cred = await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      final uid = cred.user!.uid;
      await storeSession(uid);
      await firestore.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email.trim(),
        'password': password,
        'role': role,
        'gender': gender,
        'blocked': false,
        'verified': role == 'admin',
        'createdAt': FieldValue.serverTimestamp(),
        'termsAccepted': false,
      });
      await _mirrorWrite('users', uid, {
        'uid': uid,
        'name': name,
        'email': email.trim(),
        'role': role,
        'gender': gender,
        'blocked': false,
        'verified': role == 'admin',
        'createdAt': DateTime.now().toIso8601String(),
      });
      await addAdminNotification('registration', 'New student registered: $name ($email)', relatedUid: uid);
      return cred;
    } on fb_auth.FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Sign up failed');
    }
  }

  static Future<void> signOut() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      final role = (userDoc.data())?['role'] as String?;
      final label = role == 'admin' ? 'Admin' : (role == 'Assistant' || role == 'assistant' ? 'Assistant' : 'Student');
      await addAdminNotification('logout', '$label logged out: ${user.email}', relatedUid: user.uid);
    }
    await fb_auth.FirebaseAuth.instance.signOut();
    cachedRole = null;
    SessionManager.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uid');
  }

  static Future<bool> checkSingleDeviceLogin() async {
    try {
      final user = fb_auth.FirebaseAuth.instance.currentUser;
      if (user == null) return true;
      final deviceId = await getDeviceId();
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return true;
      final data = doc.data();
      final currentDeviceId = data?['currentDeviceId'] as String? ?? '';
      if (currentDeviceId.isEmpty) return true;
      return currentDeviceId == deviceId;
    } catch (_) {
      return true;
    }
  }

  static Future<void> storeSession(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid', uid);
  }

  static Future<bool> verifySession(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('uid') == uid;
  }

  static Future<void> sendPasswordReset(String email) async {
    await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  // ─── User Data ─────────────────────────────────────────────────────────────────

  static Future<String?> getUserRole(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror['role'] as String?;
    } catch (_) {}
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      return doc.data()?['role'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getCachedUserRole(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role_$uid');
  }

  static Future<void> cacheUserRole(String uid, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role_$uid', role);
  }

  static Future<DocumentSnapshot?> getUser(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return _MirrorDocumentSnapshot(mirror);
    } catch (_) {}
    try {
      return await firestore.collection('users').doc(uid).get();
    } catch (_) {
      return null;
    }
  }

  static Future<String> getUserDisplayName(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror['name'] as String? ?? 'User';
    } catch (_) {}
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      return (doc.data())?['name'] as String? ?? 'User';
    } catch (_) {
      return 'User';
    }
  }

  static Future<bool> isStudentBlocked(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror['blocked'] == true;
    } catch (_) {}
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      return (doc.data())?['blocked'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isStudentVerified(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror['verified'] == true;
    } catch (_) {}
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      return (doc.data())?['verified'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> toggleStudentBlocked(String uid, bool blocked) async {
    await firestore.collection('users').doc(uid).update({'blocked': blocked});
    await _mirrorWrite('users', uid, {'blocked': blocked});
    if (blocked) {
      final snap = await firestore.collection('users').doc(uid).get();
      final email = (snap.data())?['email'] as String? ?? uid;
      await addAdminNotification('blocked', 'Student account blocked: $email', relatedUid: uid);
    }
  }

  static Future<void> toggleStudentVerified(String uid, bool verified, {double? paidAmount}) async {
    final data = <String, dynamic>{'verified': verified};
    if (paidAmount != null && paidAmount > 0) data['paidAmount'] = paidAmount;
    await firestore.collection('users').doc(uid).update(data);
    await _mirrorWrite('users', uid, data);
  }

  static Future<Map<String, dynamic>> getFreeTrial(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) {
        final active = (mirror['freeTrialActive'] == true) || (mirror['free_trial_active'] == true);
        final endsAt = mirror['freeTrialEndsAt'] ?? mirror['free_trial_ends_at'];
        final endDate = endsAt is String ? DateTime.tryParse(endsAt) : (endsAt is Timestamp ? endsAt.toDate() : (endsAt is DateTime ? endsAt : null));
        return {'active': active, 'endsAt': endDate};
      }
    } catch (_) {}
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final active = (data['freeTrialActive'] == true) || (data['free_trial_active'] == true);
      final endsAt = data['freeTrialEndsAt'] ?? data['free_trial_ends_at'];
      final endDate = endsAt is Timestamp ? endsAt.toDate() : (endsAt is String ? DateTime.tryParse(endsAt) : null);
      return {'active': active, 'endsAt': endDate};
    } catch (_) {
      return {'active': false, 'endsAt': null};
    }
  }

  static Future<DateTime?> getActiveTrialEndTime() async {
    try {
      final mirror = await SupabaseReadService.getUsersWhere('free_trial_active=eq.true');
      if (mirror != null) {
        DateTime? latest;
        for (final data in mirror) {
          final endsAt = data['freeTrialEndsAt'];
          final d = endsAt is Timestamp
              ? endsAt.toDate()
              : (endsAt is DateTime ? endsAt : _mirrorToDate(endsAt));
          if (d != null && (latest == null || d.isAfter(latest))) latest = d;
        }
        if (latest != null) return latest;
      }
    } catch (_) {}
    try {
      final snap = await firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('freeTrialActive', isEqualTo: true)
          .get();
      DateTime? latest;
      for (final doc in snap.docs) {
        final endsAt = doc.data()['freeTrialEndsAt'];
        final d = endsAt is Timestamp ? endsAt.toDate() : null;
        if (d != null && (latest == null || d.isAfter(latest))) latest = d;
      }
      return latest;
    } catch (_) {
      return null;
    }
  }

  static Future<int> startFreeTrialForAll({required DateTime end}) async {
    final snap = await firestore.collection('users').where('role', isEqualTo: 'student').get();
    final endTimestamp = Timestamp.fromDate(end);
    final endIso = end.toIso8601String();
    final batch = firestore.batch();
    int count = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['verified'] == true) continue;
      batch.update(doc.reference, {
        'freeTrialActive': true,
        'freeTrialEndsAt': endTimestamp,
        'free_trial_active': true,
        'free_trial_ends_at': endIso,
      });
      count++;
    }
    if (count > 0) await batch.commit();
    return count;
  }

  static Future<bool> expireFreeTrial(String uid) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return false;
      final res = await http.post(
        Uri.parse('https://prepora-web.vercel.app/api/expire-trial'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['flipped'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateUserPassword(String uid, String newPassword) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return false;
      final res = await http.post(
        Uri.parse('https://prepora-web.vercel.app/api/update-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken, 'uid': uid, 'newPassword': newPassword}),
      );
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the stored plaintext password for a user (set at account creation).
  /// Used by admins to show the current password in the change-password dialog.
  static Future<String> getUserStoredPassword(String uid) async {
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      if (!doc.exists) return '';
      return (doc.data()?['password'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Notification settings stored in Firestore so admins can tweak titles/bodies
  /// and enable/disable notifications WITHOUT changing app code.
  /// Doc: settings/notification_config
  static Future<Map<String, dynamic>> getNotificationConfig() async {
    const defaults = <String, dynamic>{
      'streakEnabled': true,
      'streakTitle': 'Time to study!',
      'streakBody': 'Your learning journey is waiting. Open PrePora and continue where you left off.',
      'appStreakEnabled': true,
      'appStreak1Title': 'Keep your streak alive!',
      'appStreak1Body': 'Don\'t let your progress slip away. Open PrePora today!',
      'appStreak2Title': 'Your streak was reset!',
      'appStreak2Body': 'You missed a day. Start a new streak today — open PrePora now!',
    };
    try {
      final mirror = await SupabaseReadService.getSettings('notification_config');
      if (mirror != null) return {...defaults, ...mirror};
    } catch (_) {}
    try {
      final doc = await firestore.collection('settings').doc('notification_config').get();
      if (!doc.exists) return defaults;
      final data = doc.data() ?? {};
      return {...defaults, ...data};
    } catch (_) {
      return defaults;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllStudents() async {
    try {
      final mirror = await SupabaseReadService.getUsersByRole('student');
      if (mirror != null) return mirror;
    } catch (_) {}
    final snap = await firestore.collection('users').where('role', isEqualTo: 'student').get();
    return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
  }

  static Stream<QuerySnapshot> getAllAssistant() {
    return SupabaseReadService.streamUsersByRole('Assistant').map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<void> deleteAssistantAccount(String uid) async {
    await firestore.collection('users').doc(uid).delete();
  }

  static Future<void> deleteUserFromAuth(String uid) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return;
      await http.post(
        Uri.parse('https://prepora-web.vercel.app/api/delete-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken, 'uid': uid}),
      );
    } catch (e) {
      await firestore.collection('users').doc(uid).delete();
    }
  }

  static Future<void> deleteStudentCompletely(String uid) async {
    final feedbacks = await firestore.collection('feedbacks').where('uid', isEqualTo: uid).get();
    final batch = firestore.batch();
    for (final d in feedbacks.docs) { batch.delete(d.reference); }
    batch.delete(firestore.collection('users').doc(uid));
    await batch.commit();
    await deleteUserFromAuth(uid);
  }

  static Future<Map<String, String>?> createAssistantAccount(String name) async {
    final sanitizedName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').replaceAll(RegExp(r'\s+'), '');
    final emailPrefix = sanitizedName.isNotEmpty ? sanitizedName : 'assistant';
    final displayEmail = '$emailPrefix@assistant.prepora';
    final passwordName = name.replaceAll(RegExp(r'\s+'), '');
    final password = '${passwordName[0].toUpperCase()}${passwordName.substring(1).toLowerCase()}123';
    try {
      final cred = await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: displayEmail,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      await firestore.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': displayEmail,
        'password': password,
        'role': 'Assistant',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _mirrorWrite('users', cred.user!.uid, {
        'uid': cred.user!.uid,
        'name': name,
        'email': displayEmail,
        'role': 'Assistant',
        'createdAt': DateTime.now().toIso8601String(),
      });
      await firestore.collection('Assistant_access').add({
        'uid': cred.user!.uid,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return {'email': displayEmail, 'password': password, 'name': name};
    } catch (e) {
      throw Exception('Failed to create Assistant account: ${e.toString()}');
    }
  }

  // ─── Supabase Storage Helpers ──────────────────────────────────────────────────

  static Future<String> uploadFileToSupabase(String bucket, String path, dynamic file) async {
    if (kIsWeb) {
      throw UnsupportedError('File upload not supported on web via this method');
    }
    await supabase.storage.from(bucket).upload(path, file as File);
    final url = supabase.storage.from(bucket).getPublicUrl(path);
    return url;
  }

  static Future<String> uploadBytesToSupabase(String bucket, String path, Uint8List bytes) async {
    await supabase.storage.from(bucket).uploadBinary(path, bytes);
    final url = supabase.storage.from(bucket).getPublicUrl(path);
    return url;
  }

  static Future<void> deleteFromSupabase(String bucket, String path) async {
    await supabase.storage.from(bucket).remove([path]);
  }

  // ─── FAKE Supabase Storage compat for notices ─────────────────────────────────
  static _SupabaseStorageService get storage => _SupabaseStorageService();

  // ─── Storage Provider Setting ──────────────────────────────────────────────────
  static const String _storageProviderKey = 'storage_provider';
  static String _cachedStorageProvider = 'supabase';

  static Future<String> getStorageProvider() async {
    try {
      final settings = await getSettings();
      final provider = settings[_storageProviderKey] as String?;
      if (provider == 'supabase' || provider == 'cloudinary' || provider == 'both') {
        _cachedStorageProvider = provider!;
      }
    } catch (_) {}
    return _cachedStorageProvider;
  }

  static Future<void> setStorageProvider(String provider) async {
    _cachedStorageProvider = provider;
    await updateSetting(_storageProviderKey, provider);
  }

  // ─── Cloudinary Multi-Account Upload ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCloudinaryAccounts() async {
    final snap = await firestore.collection('cloudinary_accounts').orderBy('createdAt', descending: false).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<String> addCloudinaryAccount(String cloudName, String uploadPreset, {bool isActive = true}) async {
    final doc = await firestore.collection('cloudinary_accounts').add({
      'cloudName': cloudName.trim(),
      'uploadPreset': uploadPreset.trim(),
      'isActive': isActive,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (isActive) {
      final snap = await firestore.collection('cloudinary_accounts').get();
      final batch = firestore.batch();
      for (final d in snap.docs) {
        if (d.id != doc.id) {
          batch.update(d.reference, {'isActive': false});
        }
      }
      await batch.commit();
    }
    return doc.id;
  }

  static Future<void> updateCloudinaryAccount(String id, {String? cloudName, String? uploadPreset, bool? isActive}) async {
    if (isActive == true) {
      final snap = await firestore.collection('cloudinary_accounts').get();
      final batch = firestore.batch();
      for (final doc in snap.docs) {
        if (doc.id != id) {
          batch.update(doc.reference, {'isActive': false});
        } else {
          batch.update(doc.reference, {'isActive': true});
        }
      }
      await batch.commit();
    } else if (isActive == false) {
      await firestore.collection('cloudinary_accounts').doc(id).update({'isActive': false});
    }
    if (cloudName != null || uploadPreset != null) {
      final data = <String, dynamic>{};
      if (cloudName != null) data['cloudName'] = cloudName.trim();
      if (uploadPreset != null) data['uploadPreset'] = uploadPreset.trim();
      await firestore.collection('cloudinary_accounts').doc(id).update(data);
    }
  }

  static Future<void> deleteCloudinaryAccount(String id) async {
    await firestore.collection('cloudinary_accounts').doc(id).delete();
  }

  static Future<String> uploadToCloudinary(Uint8List bytes, String filename) async {
    final accounts = await getCloudinaryAccounts();
    final active = accounts.firstWhere((a) => a['isActive'] == true, orElse: () => {});

    if (active.isEmpty) {
      throw Exception('No active Cloudinary account. Go to Admin Settings \u2192 Storage Provider \u2192 Cloudinary \u2192 Add Account.');
    }

    final cloudName = active['cloudName'] as String;
    final uploadPreset = active['uploadPreset'] as String;

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/raw/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = uploadPreset;
    request.fields['resource_type'] = 'raw';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(const Duration(minutes: 15));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('Cloudinary upload failed ($cloudName): ${streamed.statusCode} $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final secureUrl = decoded['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('No URL returned from Cloudinary ($cloudName)');
      }
      return secureUrl;
    } finally {
      client.close();
    }
  }

  // ─── Assistant Cloudinary Accounts ───────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAssistantCloudinaryAccounts() async {
    final snap = await firestore.collection('assistant_cloudinary').orderBy('createdAt', descending: false).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<String> addAssistantCloudinaryAccount({
    required String assistantUid,
    required String assistantName,
    required String cloudName,
    required String uploadPreset,
  }) async {
    final doc = await firestore.collection('assistant_cloudinary').add({
      'assistantUid': assistantUid,
      'assistantName': assistantName,
      'cloudName': cloudName.trim(),
      'uploadPreset': uploadPreset.trim(),
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final snap = await firestore.collection('assistant_cloudinary').where('assistantUid', isEqualTo: assistantUid).get();
    final batch = firestore.batch();
    for (final d in snap.docs) {
      if (d.id != doc.id) {
        batch.update(d.reference, {'isActive': false});
      }
    }
    await batch.commit();
    return doc.id;
  }

  static Future<void> updateAssistantCloudinaryAccount(String id, {String? cloudName, String? uploadPreset, bool? isActive}) async {
    if (isActive == true) {
      final docSnap = await firestore.collection('assistant_cloudinary').doc(id).get();
      final assistantUid = (docSnap.data())?['assistantUid'] as String?;
      if (assistantUid != null) {
        final snap = await firestore.collection('assistant_cloudinary').where('assistantUid', isEqualTo: assistantUid).get();
        final batch = firestore.batch();
        for (final doc in snap.docs) {
          if (doc.id != id) {
            batch.update(doc.reference, {'isActive': false});
          } else {
            batch.update(doc.reference, {'isActive': true});
          }
        }
        await batch.commit();
      }
    } else if (isActive == false) {
      await firestore.collection('assistant_cloudinary').doc(id).update({'isActive': false});
    }
    if (cloudName != null || uploadPreset != null) {
      final data = <String, dynamic>{};
      if (cloudName != null) data['cloudName'] = cloudName.trim();
      if (uploadPreset != null) data['uploadPreset'] = uploadPreset.trim();
      await firestore.collection('assistant_cloudinary').doc(id).update(data);
    }
  }

  static Future<void> deleteAssistantCloudinaryAccount(String id) async {
    await firestore.collection('assistant_cloudinary').doc(id).delete();
  }

  // ─── Assistant Supabase Accounts ──────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAssistantSupabaseAccounts() async {
    final snap = await firestore.collection('assistant_supabase').orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<String> addAssistantSupabaseAccount({
    required String assistantUid,
    required String assistantName,
    required String projectUrl,
    required String serviceRoleKey,
    required String anonKey,
    int storageLimitMB = 1024,
    bool autoSwitchEnabled = true,
  }) async {
    final doc = await firestore.collection('assistant_supabase').add({
      'assistantUid': assistantUid,
      'assistantName': assistantName,
      'projectUrl': projectUrl.trim(),
      'serviceRoleKey': serviceRoleKey.trim(),
      'anonKey': anonKey.trim(),
      'bucketStatus': 'pending',
      'failedBuckets': <String>[],
      'isActive': true,
      'storageLimitMB': storageLimitMB,
      'autoSwitchEnabled': autoSwitchEnabled,
      'currentUsageMB': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final snap = await firestore.collection('assistant_supabase').where('assistantUid', isEqualTo: assistantUid).get();
    final batch = firestore.batch();
    for (final d in snap.docs) {
      if (d.id != doc.id) {
        batch.update(d.reference, {'isActive': false});
      }
    }
    await batch.commit();
    final bucketResult = await _autoCreateBuckets(projectUrl.trim(), serviceRoleKey.trim());
    await firestore.collection('assistant_supabase').doc(doc.id).update({
      'bucketStatus': bucketResult['status'],
      'failedBuckets': bucketResult['failedBuckets'],
    });
    return doc.id;
  }

  static Future<void> updateAssistantSupabaseAccount(String id, {String? projectUrl, String? serviceRoleKey, String? anonKey, bool? isActive, int? storageLimitMB, bool? autoSwitchEnabled}) async {
    if (isActive == true) {
      final docSnap = await firestore.collection('assistant_supabase').doc(id).get();
      final assistantUid = (docSnap.data())?['assistantUid'] as String?;
      if (assistantUid != null) {
        final snap = await firestore.collection('assistant_supabase').where('assistantUid', isEqualTo: assistantUid).get();
        final batch = firestore.batch();
        for (final doc in snap.docs) {
          if (doc.id != id) {
            batch.update(doc.reference, {'isActive': false});
          } else {
            batch.update(doc.reference, {'isActive': true});
          }
        }
        await batch.commit();
      }
    } else if (isActive == false) {
      await firestore.collection('assistant_supabase').doc(id).update({'isActive': false});
    }
    if (projectUrl != null || serviceRoleKey != null || anonKey != null || storageLimitMB != null || autoSwitchEnabled != null) {
      final data = <String, dynamic>{};
      if (projectUrl != null) data['projectUrl'] = projectUrl.trim();
      if (serviceRoleKey != null) data['serviceRoleKey'] = serviceRoleKey.trim();
      if (anonKey != null) data['anonKey'] = anonKey.trim();
      if (storageLimitMB != null) data['storageLimitMB'] = storageLimitMB;
      if (autoSwitchEnabled != null) data['autoSwitchEnabled'] = autoSwitchEnabled;
      await firestore.collection('assistant_supabase').doc(id).update(data);
    }
  }

  static Future<void> deleteAssistantSupabaseAccount(String id) async {
    await firestore.collection('assistant_supabase').doc(id).delete();
  }

  static Future<Map<String, dynamic>> retryAssistantSupabaseBuckets(String accountId) async {
    final doc = await firestore.collection('assistant_supabase').doc(accountId).get();
    if (!doc.exists) return {'status': 'error', 'error': 'Account not found'};
    final data = doc.data()!;
    final projectUrl = data['projectUrl'] as String;
    final serviceKey = data['serviceRoleKey'] as String;
    final result = await _autoCreateBuckets(projectUrl, serviceKey);
    await firestore.collection('assistant_supabase').doc(accountId).update({
      'bucketStatus': result['status'],
      'failedBuckets': result['failedBuckets'],
    });
    return result;
  }

  static Future<String> getActiveCloudinaryAccountName() async {
    try {
      final accounts = await getCloudinaryAccounts();
      final active = accounts.firstWhere((a) => a['isActive'] == true, orElse: () => {});
      if (active.isEmpty) return 'supabase';
      return active['cloudName'] as String? ?? 'cloudinary';
    } catch (_) {
      return 'supabase';
    }
  }

  // ─── Supabase Multi-Account ────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSupabaseAccounts() async {
    final snap = await firestore.collection('supabase_accounts').orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<Map<String, dynamic>> verifySupabaseCredentials(String projectUrl, String serviceKey) async {
    try {
      final uri = Uri.parse('$projectUrl/storage/v1/bucket');
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $serviceKey'}).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return {'valid': true};
      if (response.statusCode == 401 || response.statusCode == 403) return {'valid': false, 'error': 'Invalid credentials'};
      return {'valid': false, 'error': 'Server error: ${response.statusCode}'};
    } catch (e) {
      return {'valid': false, 'error': 'Connection failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _autoCreateBuckets(String projectUrl, String serviceKey) async {
    final results = <String, String>{};
    for (final bucket in ['folder_files', 'notices']) {
      try {
        final checkUri = Uri.parse('$projectUrl/storage/v1/bucket/$bucket');
        final checkResp = await http.get(checkUri, headers: {'Authorization': 'Bearer $serviceKey'}).timeout(const Duration(seconds: 15));
        if (checkResp.statusCode == 200) {
          results[bucket] = 'ready';
          continue;
        }
        final uri = Uri.parse('$projectUrl/storage/v1/bucket');
        final response = await http.post(uri,
          headers: {'Authorization': 'Bearer $serviceKey', 'Content-Type': 'application/json'},
          body: jsonEncode({'id': bucket, 'public': true}),
        ).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 409) {
          results[bucket] = 'ready';
        } else {
          results[bucket] = 'failed';
        }
      } catch (_) {
        results[bucket] = 'failed';
      }
    }
    final failed = results.entries.where((e) => e.value == 'failed').map((e) => e.key).toList();
    final allReady = failed.isEmpty;
    return {'status': allReady ? 'ready' : (failed.length == 2 ? 'failed' : 'partial'), 'failedBuckets': failed};
  }

  static Future<String> addSupabaseAccount(String projectUrl, String serviceRoleKey, String anonKey, {bool isActive = true, int storageLimitMB = 1024, bool autoSwitchEnabled = true}) async {
    final doc = await firestore.collection('supabase_accounts').add({
      'projectUrl': projectUrl.trim(),
      'serviceRoleKey': serviceRoleKey.trim(),
      'anonKey': anonKey.trim(),
      'bucketStatus': 'pending',
      'failedBuckets': <String>[],
      'isActive': isActive,
      'storageLimitMB': storageLimitMB,
      'autoSwitchEnabled': autoSwitchEnabled,
      'currentUsageMB': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (isActive) {
      final snap = await firestore.collection('supabase_accounts').get();
      final batch = firestore.batch();
      for (final d in snap.docs) {
        if (d.id != doc.id) {
          batch.update(d.reference, {'isActive': false});
        }
      }
      await batch.commit();
    }
    final bucketResult = await _autoCreateBuckets(projectUrl.trim(), serviceRoleKey.trim());
    await firestore.collection('supabase_accounts').doc(doc.id).update({
      'bucketStatus': bucketResult['status'],
      'failedBuckets': bucketResult['failedBuckets'],
    });
    return doc.id;
  }

  static Future<void> updateSupabaseAccount(String id, {String? projectUrl, String? serviceRoleKey, String? anonKey, bool? isActive, int? storageLimitMB, bool? autoSwitchEnabled}) async {
    if (isActive == true) {
      final snap = await firestore.collection('supabase_accounts').get();
      final batch = firestore.batch();
      for (final doc in snap.docs) {
        if (doc.id != id) {
          batch.update(doc.reference, {'isActive': false});
        } else {
          batch.update(doc.reference, {'isActive': true});
        }
      }
      await batch.commit();
    } else if (isActive == false) {
      await firestore.collection('supabase_accounts').doc(id).update({'isActive': false});
    }
    if (projectUrl != null || serviceRoleKey != null || anonKey != null || storageLimitMB != null || autoSwitchEnabled != null) {
      final data = <String, dynamic>{};
      if (projectUrl != null) data['projectUrl'] = projectUrl.trim();
      if (serviceRoleKey != null) data['serviceRoleKey'] = serviceRoleKey.trim();
      if (anonKey != null) data['anonKey'] = anonKey.trim();
      if (storageLimitMB != null) data['storageLimitMB'] = storageLimitMB;
      if (autoSwitchEnabled != null) data['autoSwitchEnabled'] = autoSwitchEnabled;
      await firestore.collection('supabase_accounts').doc(id).update(data);
    }
  }

  static Future<void> deleteSupabaseAccount(String id) async {
    await firestore.collection('supabase_accounts').doc(id).delete();
  }

  // ─── AI API Keys Multi-Account ────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAiApiKeys() async {
    // Mirror first for performance
    try {
      final mirror = await SupabaseReadService.getAllAiApiKeys();
      if (mirror != null && mirror.isNotEmpty) return mirror;
    } catch (_) {}
    // Fallback to Firestore
    final snap = await firestore.collection('ai_api_keys').orderBy('createdAt', descending: false).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<Map<String, dynamic>?> getActiveAiApiKey() async {
    // Mirror first — this bypasses the Firestore read quota.
    final mirrorKey = await SupabaseReadService.getActiveAiApiKey();
    if (mirrorKey != null) return mirrorKey;
    final snap = await firestore.collection('ai_api_keys').where('isActive', isEqualTo: true).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return {'id': d.id, ...d.data()};
  }

  /// Mirrors an AI key row into the read-mirror Supabase (best effort — never
  /// throws, so Firestore remains the source of truth even if mirroring fails).
  static Future<void> _mirrorAiApiKey({
    required String id,
    required Map<String, dynamic> data,
    bool? isActive,
  }) async {
    try {
      final mirrorData = <String, dynamic>{...data};
      if (isActive != null) mirrorData['isActive'] = isActive;
      await SupabaseReadService.writeToAll('ai_api_keys', id, mirrorData);
    } catch (_) {}
  }

  /// Best-effort dual-write of a Firestore doc into the read-mirror Supabase.
  /// Never throws. Plain values only (no FieldValue/Timestamp sentinels).
  static Future<void> _mirrorWrite(String table, String id, Map<String, dynamic> data, {bool? delete}) async {
    try {
      await SupabaseReadService.writeToAll(table, id, data, delete: delete == true);
    } catch (_) {}
  }

  static Future<void> mirrorWebSession(String sessionId, Map<String, dynamic> data, {bool? delete}) =>
      _mirrorWrite('web_sessions', sessionId, data, delete: delete);

  static Future<String> addAiApiKey({
    required String name,
    required String provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    List<String>? models,
    bool isActive = true,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'provider': provider.trim(),
      'baseUrl': baseUrl.trim(),
      'apiKey': apiKey.trim(),
      'model': model.trim(),
      'isActive': isActive,
    };
    if (models != null && models.isNotEmpty) {
      data['models'] = models.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
    }
    final doc = await firestore.collection('ai_api_keys').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (isActive) {
      final snap = await firestore.collection('ai_api_keys').get();
      final batch = firestore.batch();
      for (final d in snap.docs) {
        if (d.id != doc.id) {
          batch.update(d.reference, {'isActive': false});
        }
      }
      await batch.commit();
    }
    await _mirrorAiApiKey(id: doc.id, data: data, isActive: isActive);
    return doc.id;
  }

  static Future<void> updateAiApiKey(String id, {
    String? name, String? provider, String? baseUrl, String? apiKey, String? model, List<String>? models, bool? isActive,
  }) async {
    if (isActive == true) {
      final snap = await firestore.collection('ai_api_keys').get();
      final batch = firestore.batch();
      for (final doc in snap.docs) {
        if (doc.id != id) {
          batch.update(doc.reference, {'isActive': false});
        } else {
          batch.update(doc.reference, {'isActive': true});
        }
      }
      await batch.commit();
    } else if (isActive == false) {
      await firestore.collection('ai_api_keys').doc(id).update({'isActive': false});
    }
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name.trim();
    if (provider != null) data['provider'] = provider.trim();
    if (baseUrl != null) data['baseUrl'] = baseUrl.trim();
    if (apiKey != null) data['apiKey'] = apiKey.trim();
    if (model != null) data['model'] = model.trim();
    if (models != null) data['models'] = models.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
    if (data.isNotEmpty) {
      await firestore.collection('ai_api_keys').doc(id).update(data);
      await _mirrorAiApiKey(id: id, data: data, isActive: isActive);
    } else if (isActive != null) {
      await _mirrorAiApiKey(id: id, data: const {}, isActive: isActive);
    }
  }

  static Future<void> deleteAiApiKey(String id) async {
    await firestore.collection('ai_api_keys').doc(id).delete();
    try {
      await SupabaseReadService.writeToAll('ai_api_keys', id, const {}, delete: true);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> retryBucketCreation(String accountId) async {
    final doc = await firestore.collection('supabase_accounts').doc(accountId).get();
    if (!doc.exists) return {'status': 'error', 'error': 'Account not found'};
    final data = doc.data()!;
    final projectUrl = data['projectUrl'] as String;
    final serviceKey = data['serviceRoleKey'] as String;
    final result = await _autoCreateBuckets(projectUrl, serviceKey);
    await firestore.collection('supabase_accounts').doc(accountId).update({
      'bucketStatus': result['status'],
      'failedBuckets': result['failedBuckets'],
    });
    return result;
  }

  static Future<String> getActiveSupabaseAccountName() async {
    try {
      final accounts = await getSupabaseAccounts();
      final active = accounts.firstWhere((a) => a['isActive'] == true, orElse: () => {});
      if (active.isEmpty) return '';
      return active['projectUrl'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> uploadFile(Uint8List bytes, String filename, {void Function(double)? onProgress, String? forceProvider}) async {
    final provider = forceProvider ?? await getStorageProvider();

    if (provider == 'both') {
      if (bytes.length <= 10 * 1024 * 1024) {
        try {
          return await _uploadViaCloudinary(bytes, filename);
        } catch (_) {
          return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
        }
      } else {
        return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
      }
    }

    if (provider == 'cloudinary') {
      return await _uploadViaCloudinary(bytes, filename);
    }

    return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
  }

  static Future<String> _uploadViaCloudinary(Uint8List bytes, String filename) async {
    final user = currentUser;
    if (user != null) {
      final role = await getUserRole(user.uid);
      if (role == 'Assistant' || role == 'assistant') {
        return await _uploadToAssistantCloudinary(user.uid, bytes, filename);
      }
    }
    return await uploadToCloudinary(bytes, filename);
  }

  static Future<String> _uploadViaSupabase(Uint8List bytes, String filename, {void Function(double)? onProgress}) async {
    final storageName = '${DateTime.now().millisecondsSinceEpoch}_$filename';
    final ref = storage.ref('folder_files/$storageName');
    await ref.putData(bytes, metadata: fb_storage.SettableMetadata(contentDisposition: 'inline; filename="$filename"'), onProgress: onProgress);
    return ref.getDownloadURL();
  }

  static Future<String> _uploadToAssistantCloudinary(String assistantUid, Uint8List bytes, String filename) async {
    final snap = await firestore
        .collection('assistant_cloudinary')
        .where('assistantUid', isEqualTo: assistantUid)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      return await uploadToCloudinary(bytes, filename);
    }

    final data = snap.docs.first.data();
    final cloudName = data['cloudName'] as String;
    final uploadPreset = data['uploadPreset'] as String;

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/raw/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = uploadPreset;
    request.fields['resource_type'] = 'raw';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(const Duration(minutes: 15));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('Assistant Cloudinary upload failed ($cloudName): ${streamed.statusCode} $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final secureUrl = decoded['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('No URL returned from Cloudinary ($cloudName)');
      }
      return secureUrl;
    } finally {
      client.close();
    }
  }

  // ─── Folders ───────────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getAllFolders() {
    return SupabaseReadService.streamFolders().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<String?> createRootFolder({required String name, String? icon, String? color}) async {
    final doc = await firestore.collection('folders').add({
      'name': name,
      'icon': icon ?? 'folder',
      'color': color ?? '#4A148C',
      'item_count': 0,
      'locked': false,
      'invisible': false,
      'updating': false,
      'group_link': null,
      'sort_order': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _mirrorWrite('folders', doc.id, {
      'name': name,
      'icon': icon ?? 'folder',
      'color': color ?? '#4A148C',
      'item_count': 0,
      'locked': false,
      'invisible': false,
      'updating': false,
      'group_link': null,
      'sort_order': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return doc.id;
  }

  static Future<void> renameRootFolder(String folderId, String name) async {
    await firestore.collection('folders').doc(folderId).update({'name': name});
    await _mirrorWrite('folders', folderId, {'name': name});
  }

  static Future<void> deleteRootFolder(String folderId) async {
    // Delete ALL contents recursively (including nested subfolders)
    await _deleteAllContentsRecursive(folderId, 'contents');
    await _deleteAllContentsRecursive(folderId, 'content');
    await firestore.collection('folders').doc(folderId).delete();
    await _mirrorWrite('folders', folderId, const {}, delete: true);
  }

  static Future<void> _deleteAllContentsRecursive(String folderId, String subcollection) async {
    final snap = await firestore.collection('folders').doc(folderId).collection(subcollection).get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
      await _mirrorWrite('contents', doc.id, const {}, delete: true);
    }
  }

  static Future<void> deleteFolder(String folderId) async {
    await deleteRootFolder(folderId);
  }

  static Future<void> toggleFolderLock(String folderId, String field, dynamic value) async {
    await firestore.collection('folders').doc(folderId).update({field: value});
  }

  /// Async: check content-level group_link first, fall back to root folder doc.
  /// Respects [inheritGroup] flag: if false on the content doc, skip folder fallback.
  static Future<String?> getGroupLinkForLevel(String folderId, {String? parentContentId}) async {
    if (parentContentId != null && parentContentId != 'root') {
      final contentDoc = await firestore.collection('folders').doc(folderId).collection('contents').doc(parentContentId).get();
      if (contentDoc.exists) {
        final data = contentDoc.data();
        final link = data?['group_link'] as String?;
        final inherit = data?['inherit_group'] as bool? ?? true;
        if (link != null && link.isNotEmpty) return link;
        if (!inherit) return null;
      }
    }
    final folderDoc = await firestore.collection('folders').doc(folderId).get();
    if (folderDoc.exists) {
      final data = folderDoc.data();
      final link = data?['group_link'] as String?;
      if (link != null && link.isNotEmpty) return link;
    }
    return null;
  }

  /// Sync read from already-fetched folder data (falls back to root doc).
  static String? getGroupLink(dynamic folderData, {String? parentContentId}) {
    if (folderData == null) return null;
    Map<String, dynamic> data;
    if (folderData is DocumentSnapshot) {
      data = folderData.data() as Map<String, dynamic>? ?? {};
    } else {
      data = folderData as Map<String, dynamic>;
    }
    if (parentContentId != null && parentContentId != 'root') {
      final link = data['group_link'] as String?;
      final inherit = data['inherit_group'] as bool? ?? true;
      if (link != null && link.isNotEmpty) return link;
      if (!inherit) return null;
    }
    return data['group_link'] as String?;
  }

  static Future<void> setGroupLink(String folderId, String link, {String? parentContentId, bool inheritGroup = true}) async {
    if (parentContentId != null && parentContentId != 'root') {
      await firestore.collection('folders').doc(folderId).collection('contents').doc(parentContentId).update({
        'group_link': link,
        'inherit_group': inheritGroup,
      });
      if (inheritGroup) {
        await _propagateAllDescendants(folderId, parentContentId, link, true);
      }
    } else {
      await firestore.collection('folders').doc(folderId).update({
        'group_link': link,
        'inherit_group': inheritGroup,
      });
      if (inheritGroup) {
        await _propagateAllDescendants(folderId, null, link, true);
      }
    }
  }

  static Future<void> removeGroupLink(String folderId, {String? parentContentId}) async {
    if (parentContentId != null && parentContentId != 'root') {
      final doc = await firestore.collection('folders').doc(folderId).collection('contents').doc(parentContentId).get();
      final inherit = (doc.data())?['inherit_group'] as bool? ?? true;
      await firestore.collection('folders').doc(folderId).collection('contents').doc(parentContentId).update({
        'group_link': null,
        'inherit_group': true,
      });
      if (inherit) {
        await _propagateAllDescendants(folderId, parentContentId, null, true);
      }
    } else {
      final folderDoc = await firestore.collection('folders').doc(folderId).get();
      final inherit = (folderDoc.data())?['inherit_group'] as bool? ?? true;
      await firestore.collection('folders').doc(folderId).update({
        'group_link': null,
        'inherit_group': true,
      });
      if (inherit) {
        await _propagateAllDescendants(folderId, null, null, true);
      }
    }
  }

  static Future<void> _propagateAllDescendants(String folderId, String? startParentId, String? link, bool inheritGroup) async {
    final allDocs = await firestore
        .collection('folders').doc(folderId)
        .collection('contents')
        .get();
    if (allDocs.docs.isEmpty) return;
    final docMap = <String, Map<String, dynamic>>{};
    final parentMap = <String?, List<String>>{};
    for (final doc in allDocs.docs) {
      docMap[doc.id] = doc.data();
      final pid = doc.data()['parentContentId'] as String?;
      parentMap.putIfAbsent(pid, () => []).add(doc.id);
    }
    final toUpdate = <String>{};
    void collectDescendants(String id) {
      final children = parentMap[id];
      if (children == null) return;
      for (final childId in children) {
        if (toUpdate.add(childId)) {
          collectDescendants(childId);
        }
      }
    }
    if (startParentId == null) {
      for (final entry in parentMap.entries) {
        if (entry.key != null) {
          for (final childId in entry.value) {
            if (toUpdate.add(childId)) {
              collectDescendants(childId);
            }
          }
        }
      }
    } else {
      collectDescendants(startParentId);
    }
    if (toUpdate.isEmpty) return;
    final batch = firestore.batch();
    for (final id in toUpdate) {
      batch.update(
        firestore.collection('folders').doc(folderId).collection('contents').doc(id),
        {'group_link': link, 'inherit_group': inheritGroup},
      );
    }
    await batch.commit();
  }

  // ─── Folder Contents ───────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getContentsForFolder(String folderId) {
    return SupabaseReadService.streamContents(folderId).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<String?> addFolderContent(String folderId, Map<String, dynamic> data) async {
    final doc = await firestore.collection('folders').doc(folderId).collection('contents').add({
      'createdAt': FieldValue.serverTimestamp(),
      ...data,
    });
    await firestore.collection('folders').doc(folderId).update({'item_count': FieldValue.increment(1)});
    await _mirrorWrite('contents', doc.id, {
      'folderId': folderId,
      ...data,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return doc.id;
  }

  static Future<void> renameFolderContent(String folderId, String contentId, String name) async {
    await firestore.collection('folders').doc(folderId).collection('contents').doc(contentId).update({'name': name});
    await _mirrorWrite('contents', contentId, {'folderId': folderId, 'name': name});
  }

  static Future<void> deleteFolderContent(String folderId, String contentId) async {
    // Check if it's a subfolder — delete all children recursively
    final contentDoc = await firestore.collection('folders').doc(folderId).collection('contents').doc(contentId).get();
    if (contentDoc.exists) {
      final data = contentDoc.data();
      if (data != null && data['type'] == 'subfolder') {
        await _deleteSubfolderChildrenRecursive(folderId, contentId, 'contents');
        await _deleteSubfolderChildrenRecursive(folderId, contentId, 'content');
      }
    }
    await firestore.collection('folders').doc(folderId).collection('contents').doc(contentId).delete();
    await firestore.collection('folders').doc(folderId).update({'item_count': FieldValue.increment(-1)});
    await _mirrorWrite('contents', contentId, const {}, delete: true);
  }

  static Future<void> _deleteSubfolderChildrenRecursive(String folderId, String parentContentId, String subcollection) async {
    final snap = await firestore.collection('folders').doc(folderId).collection(subcollection)
        .where('parentContentId', isEqualTo: parentContentId).get();
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['type'] == 'subfolder') {
        await _deleteSubfolderChildrenRecursive(folderId, doc.id, subcollection);
      }
      await doc.reference.delete();
      await _mirrorWrite('contents', doc.id, const {}, delete: true);
    }
  }

  static Future<void> updateContentField(String folderId, String contentId, String field, dynamic value) async {
    await firestore.collection('folders').doc(folderId).collection('contents').doc(contentId).update({field: value});
    await _mirrorWrite('contents', contentId, {'folderId': folderId, field: value});
  }

  static Future<void> grantContentAccess(String uid, String folderId, String contentId, String name) async {
    await firestore.collection('content_Assistant_access').add({
      'content_id': contentId,
      'folder_id': folderId,
      'user_id': uid,
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> revokeContentAccess(String uid, String folderId, String contentId) async {
    final snap = await firestore
        .collection('content_Assistant_access')
        .where('content_id', isEqualTo: contentId)
        .where('user_id', isEqualTo: uid)
        .get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
  }

  // ─── Notices ────────────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getNotices() {
    return SupabaseReadService.streamNotices().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<String?> addNotice(String title, String? fileUrl, String fileType) async {
    final docId = 'nt_${DateTime.now().millisecondsSinceEpoch}';
    try {
      // If file is a local file path, upload to Supabase Storage
      String? supabaseUrl = fileUrl;
      if (fileUrl != null && (fileUrl.startsWith('/') || fileUrl.startsWith('file://'))) {
        try {
          final file = File(fileUrl.replaceFirst('file://', ''));
          final ext = fileUrl.split('.').last;
          final fileName = 'notices/${DateTime.now().millisecondsSinceEpoch}.$ext';
          supabaseUrl = await uploadFileToSupabase('notices', fileName, file);
        } catch (e) {
          debugPrint('[addNotice] Supabase file upload failed: $e');
          supabaseUrl = null;
        }
      }
      final userName = currentUser?.displayName ?? 'Admin';
      await SupabaseReadService.writeToAll('notices', docId, {
        'title': title,
        'fileUrl': supabaseUrl,
        'fileType': fileType,
        'addedBy': userName,
        'createdAt': DateTime.now().toIso8601String(),
      });
      return docId;
    } catch (e) {
      debugPrint('[addNotice] Supabase write failed: $e');
      return null;
    }
  }

  // ─── Notifications ─────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getNotificationsForUser(String uid, DateTime since) {
    return SupabaseReadService.streamNotifications(uid, since).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<void> markStudentNotificationsRead(String uid) async {
    List<Map<String, dynamic>>? unread;
    try { unread = await SupabaseReadService.getUnreadNotificationsForUser(uid); } catch (_) {}
    if (unread != null && unread.isNotEmpty) {
      for (final row in unread) {
        final id = row['id'] as String?;
        if (id != null && id.isNotEmpty) {
          await _mirrorWrite('notifications', id, {
            ...row,
            'read': true,
          });
        }
      }
    }
  }

  // ─── Admin Notifications ───────────────────────────────────────────────────────

  static Future<void> addAdminNotification(String type, String message, {String? relatedUid}) async {
    await firestore.collection('admin_notifications').add({
      'type': type,
      'message': message,
      'relatedUid': relatedUid,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot> getAdminNotifications() {
    return SupabaseReadService.streamAdminNotifications().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<int> getAdminUnreadCount() async {
    try {
      final mirror = await SupabaseReadService.getAdminUnreadCount();
      if (mirror >= 0) return mirror;
    } catch (_) {}
    final snap = await firestore.collection('admin_notifications').where('read', isEqualTo: false).get();
    return snap.docs.length;
  }

  static Future<void> markAdminNotificationsRead() async {
    final snap = await firestore.collection('admin_notifications').where('read', isEqualTo: false).get();
    final batch = firestore.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  static Future<void> clearAdminNotifications() async {
    final snap = await firestore.collection('admin_notifications').get();
    final batch = firestore.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // ─── Login Tracking & Auto-Block ──────────────────────────────────────────────

  static Future<bool> isMultiDeviceViolation(String uid, String currentDeviceId) async {
    try {
      if (currentDeviceId.isEmpty) return false;
      final snap = await firestore
          .collection('login_attempts')
          .where('uid', isEqualTo: uid)
          .get();
      final docs = snap.docs.toList();
      if (docs.isEmpty) return false;
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final devicesIn24h = <String>{};
      for (final d in docs) {
        final data = d.data();
        final devId = data['deviceId'] as String? ?? '';
        if (devId.isEmpty) continue;
        final ts = data['createdAt'];
        DateTime at;
        if (ts is Timestamp) {
          at = ts.toDate();
        } else {
          at = DateTime.tryParse(data['timestamp'] as String? ?? '') ?? DateTime.now();
        }
        if (!at.isBefore(cutoff)) {
          devicesIn24h.add(devId);
        }
      }
      if (devicesIn24h.length >= 3) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _trackLogin(String uid, String deviceId) async {
    try {
      final now = DateTime.now();
      final iso = now.toIso8601String();
      var deviceModel = 'Android device';
      var androidVersion = '';
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        deviceModel = '${info.manufacturer} ${info.model}';
        androidVersion = 'Android ${info.version.release} (API ${info.version.sdkInt})';
      } catch (_) {}
      await firestore.collection('login_attempts').add({
        'uid': uid,
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'androidVersion': androidVersion,
        'timestamp': iso,
        'createdAt': Timestamp.fromDate(now),
      });
      try {
        await firestore.collection('login_history').doc(uid).collection('logins').add({
          'timestamp': Timestamp.fromDate(now),
          'device': deviceModel,
          'deviceId': deviceId,
          'androidVersion': androidVersion,
          'ip': '',
        });
      } catch (_) {}
    } catch (_) {}
  }

  static Future<void> updateStreak(String uid) async {
    try {
      Map<String, dynamic>? data;
      try {
        data = await SupabaseReadService.getUser(uid);
      } catch (_) {}
      if (data == null) {
        final doc = await firestore.collection('users').doc(uid).get();
        if (!doc.exists) return;
        data = doc.data() as Map<String, dynamic>;
      }
      final lastActive = (data['lastActiveDate'] as String?) ?? (data['last_active_date'] as String?) ?? '';
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      if (lastActive == todayStr) return;

      int streak = (data['streakCount'] as int?) ?? (data['streak_count'] as int?) ?? (data['streak'] as int?) ?? 0;
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      if (lastActive == yesterdayStr) {
        streak += 1;
      } else {
        streak = 1;
      }

      final totalDays = (data['totalActiveDays'] as int?) ?? (data['total_active_days'] as int?) ?? 0;
      int streakBest = (data['streakBest'] as int?) ?? (data['streak_best'] as int?) ?? 0;
      if (streak > streakBest) streakBest = streak;

      // Read existing JSONB data so we don't destroy name/email/etc
      Map<String, dynamic>? existingData;
      try {
        existingData = await SupabaseReadService.readPrimary('users', uid);
      } catch (_) {}
      final mergedData = <String, dynamic>{
        if (existingData != null) ...existingData,
        'lastActiveDate': todayStr,
        'streakCount': streak,
        'totalActiveDays': totalDays + 1,
        'streakBest': streakBest,
        'lastLogin': today.toIso8601String(),
      };
      await _mirrorWrite('users', uid, mergedData);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getStreak(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) {
        final lastActive = (mirror['lastActiveDate'] as String?) ?? (mirror['last_active_date'] as String?) ?? '';
        int streakCount = (mirror['streakCount'] as int?) ?? (mirror['streak_count'] as int?) ?? (mirror['streak'] as int?) ?? 0;
        final today = DateTime.now();
        final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        final yesterday = today.subtract(const Duration(days: 1));
        final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
        if (lastActive != todayStr && lastActive != yesterdayStr) {
          streakCount = 0;
        }
        return {
          'streakCount': streakCount,
          'totalActiveDays': (mirror['totalActiveDays'] as int?) ?? (mirror['total_active_days'] as int?) ?? 0,
          'lastActiveDate': lastActive,
        };
      }
    } catch (_) {}
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      if (!doc.exists) return {'streakCount': 0, 'totalActiveDays': 0};
      final data = doc.data() as Map<String, dynamic>;
      return {
        'streakCount': data['streakCount'] as int? ?? 0,
        'totalActiveDays': data['totalActiveDays'] as int? ?? 0,
        'lastActiveDate': data['lastActiveDate'] as String? ?? '',
      };
    } catch (_) {
      return {'streakCount': 0, 'totalActiveDays': 0};
    }
  }

  static Future<bool> _isAnyAncestorRestricted(String folderId, String? contentId) async {
    if (contentId == null) return false;
    try {
      final doc = await firestore.collection('folders').doc(folderId).collection('contents').doc(contentId).get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;
      final locked = data['locked'] as bool? ?? false;
      final invisible = data['invisible'] as bool? ?? false;
      final updating = data['updating'] as bool? ?? false;
      if (locked || invisible || updating) return true;
      final parentContentId = data['parentContentId'] as String?;
      if (parentContentId != null) {
        return _isAnyAncestorRestricted(folderId, parentContentId);
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> _isNotificationBlocked(String? folderId, String? parentContentId, Map<String, dynamic>? contentData) async {
    if (contentData != null) {
      final locked = contentData['locked'] as bool? ?? false;
      final updating = contentData['updating'] as bool? ?? false;
      final invisible = contentData['invisible'] as bool? ?? false;
      if (locked || updating || invisible) return true;
    }
    if (folderId != null) {
      final folderDoc = await firestore.collection('folders').doc(folderId).get();
      if (folderDoc.exists) {
        final folderData = folderDoc.data();
        if (folderData != null) {
          final folderLocked = folderData['locked'] as bool? ?? false;
          final folderInvisible = folderData['invisible'] as bool? ?? false;
          final folderUpdating = folderData['updating'] as bool? ?? false;
          if (folderLocked || folderInvisible || folderUpdating) return true;
        }
      }
      if (parentContentId != null) {
        if (await _isAnyAncestorRestricted(folderId, parentContentId)) return true;
      }
    }
    return false;
  }

  static Future<String?> addNotification(String message, {String? folderId, String? parentContentId, Map<String, dynamic>? contentData}) async {
    if (await _isNotificationBlocked(folderId, parentContentId, contentData)) return null;
    final users = await firestore.collection('users').get();
    final batch = firestore.batch();
    for (final u in users.docs) {
      final ref = firestore.collection('notifications').doc();
      batch.set(ref, {
        'uid': u.id,
        'message': message,
        'folderId': folderId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'type': folderId != null ? 'folder_update' : 'general',
      });
    }
    await batch.commit();
    return 'batch';
  }

  static Future<String?> addTargetedNotification(String uid, String message, {String? folderId, String? parentContentId, Map<String, dynamic>? contentData}) async {
    if (await _isNotificationBlocked(folderId, parentContentId, contentData)) return null;
    final doc = await firestore.collection('notifications').add({
      'uid': uid,
      'message': message,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'targeted',
    });
    return doc.id;
  }

  static Future<int> addNotificationToAllStudents(String message) async {
    final users = await firestore.collection('users').where('role', isEqualTo: 'student').get();
    final batch = firestore.batch();
    int count = 0;
    for (final u in users.docs) {
      final ref = firestore.collection('notifications').doc();
      batch.set(ref, {
        'uid': u.id,
        'message': message,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'general',
      });
      count++;
    }
    if (count > 0) await batch.commit();
    return count;
  }

  // ─── Student Activity Tracking ───────────────────────────────────────────────

  static Future<String> logActivity({
    required String uid,
    required String name,
    required String type,
    required String folderPath,
    String? contentId,
  }) async {
    final docId = 'act_${DateTime.now().millisecondsSinceEpoch}';
    await SupabaseReadService.writeToAll('student_activities', docId, {
      'uid': uid,
      'name': name,
      'type': type,
      'folderPath': folderPath,
      if (contentId != null) 'contentId': contentId,
      'startedAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<void> endActivity(String activityId) async {
    try {
      // Read existing data first to preserve all fields
      Map<String, dynamic>? existing;
      try {
        existing = await SupabaseReadService.readPrimary('student_activities', activityId);
      } catch (_) {}
      final merged = <String, dynamic>{
        if (existing != null) ...existing,
        'endedAt': DateTime.now().toIso8601String(),
      };
      await _mirrorWrite('student_activities', activityId, merged);
    } catch (_) {}
  }

  static Stream<QuerySnapshot> getStudentActivities(String uid) {
    return SupabaseReadService.streamStudentActivities(uid).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror;
    } catch (_) {}
    try {
      final fallback = await SupabaseReadService.readPrimary('users', uid);
      if (fallback != null) return fallback;
    } catch (_) {}
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      return doc.exists ? doc.data() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getStudentFeedbacks(String uid) async {
    try {
      final mirror = await SupabaseReadService.getFeedbacksForUser(uid);
      if (mirror != null) return mirror;
    } catch (_) {}
    try {
      final snap = await firestore.collection('feedbacks')
          .where('uid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs.map((d) => d.data()..['id'] = d.id).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Feedback ──────────────────────────────────────────────────────────────────

  static bool _submittingFeedback = false;

  static Future<String?> submitFeedback(dynamic feedback) async {
    if (_submittingFeedback) return null;
    _submittingFeedback = true;
    try {
      Map<String, dynamic> data;
      if (feedback is String) {
        data = {
          'message': feedback,
          'uid': currentUser?.uid ?? '',
          'student_name': currentUser?.displayName ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
          'viewed': false,
        };
      } else if (feedback is Map<String, dynamic>) {
        data = Map.from(feedback);
        data['createdAt'] ??= FieldValue.serverTimestamp();
        data['viewed'] ??= false;
      } else {
        return null;
      }
      final doc = await firestore.collection('feedbacks').add(data);
      final ticketNo = doc.id.substring(0, 6).toUpperCase();
      await doc.update({'ticketNo': ticketNo});
      await _mirrorWrite('feedbacks', doc.id, {
        'message': data['message'],
        'uid': data['uid'],
        'student_name': data['student_name'],
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'pending',
        'viewed': false,
        'ticketNo': ticketNo,
      });
      final name = currentUser?.displayName ?? 'Unknown';
      await addAdminNotification('feedback', 'New Contact Support message from $name', relatedUid: currentUser?.uid);
      return doc.id;
    } finally {
      _submittingFeedback = false;
    }
  }

  static Future<List<Map<String, dynamic>>> getStudentFeedbacksOnce(String uid) async {
    try {
      final mirror = await SupabaseReadService.getFeedbacksForUser(uid);
      if (mirror != null && mirror.isNotEmpty) {
        mirror.sort((a, b) {
          final aTime = a['createdAt'] ?? a['created_at'] ?? '';
          final bTime = b['createdAt'] ?? b['created_at'] ?? '';
          return bTime.toString().compareTo(aTime.toString());
        });
        return mirror;
      }
    } catch (_) {}
    try {
      final snap = await firestore
          .collection('feedbacks')
          .where('uid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();
      return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
    } catch (_) {}
    try {
      final snap = await firestore
          .collection('feedbacks')
          .where('uid', isEqualTo: uid)
          .get();
      final list = snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
      list.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];
        if (aTime is Timestamp && bTime is Timestamp) return bTime.compareTo(aTime);
        return 0;
      });
      return list;
    } catch (_) {}
    return [];
  }

  static Stream<QuerySnapshot> getAllFeedbacks() {
    return SupabaseReadService.streamAllFeedbacks().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<int> getPendingFeedbackCount() async {
    try {
      final mirror = await SupabaseReadService.getPendingFeedbackCount();
      if (mirror >= 0) return mirror;
    } catch (_) {}
    final snap = await firestore.collection('feedbacks').where('status', isEqualTo: 'pending').get();
    return snap.docs.length;
  }

  static Future<void> updateFeedbackStatus(String id, String status) async {
    await firestore.collection('feedbacks').doc(id).update({'status': status});
  }

  static Future<void> updateFeedbackReply(String id, String reply) async {
    await firestore.collection('feedbacks').doc(id).update({'reply': reply});
  }

  // ─── Notes ─────────────────────────────────────────────────────────────────────

  static Future<DocumentSnapshot?> getNote(String lectureId) async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) return null;
      final mirror = await SupabaseReadService.getNote(lectureId, uid);
      if (mirror != null) return _MirrorDocumentSnapshot(mirror);
    } catch (e) {
      debugPrint('[getNote] Supabase read failed: $e');
    }
    return null;
  }

  static Future<bool> saveNote(String lectureId, String content, {String? lectureName}) async {
    final uid = currentUser?.uid;
    if (uid == null) return false;
    try {
      await SupabaseReadService.writeToAll('notes', lectureId, {
        'uid': uid,
        'content': content,
        'lectureName': lectureName ?? '',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('[saveNote] Supabase write failed: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllNotes() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    
    for (int i = 0; i < 3; i++) {
      try {
        final mirror = await SupabaseReadService.getNotes(uid);
        if (mirror != null && mirror.isNotEmpty) return mirror;
      } catch (e) {
        debugPrint('[getAllNotes] Supabase read attempt ${i + 1} failed: $e');
      }
      if (i < 2) await Future.delayed(const Duration(milliseconds: 300));
    }
    return [];
  }

  static Future<void> deleteNote(String id) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await SupabaseReadService.writeToAll('notes', id, const {}, delete: true);
  }

  static Future<void> renameNote(String id, String newName) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await SupabaseReadService.writeToAll('notes', id, {'uid': uid, 'lectureName': newName, 'updatedAt': DateTime.now().toIso8601String()});
  }

  // ─── Assistant Access ─────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getAssistantLoginsForFolder(String folderId) {
    return SupabaseReadService.streamAssistantLogins(folderId).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<Map<String, List<String>>> getContentAccess(String uid) async {
    try {
      final map = await SupabaseReadService.getContentAccess(uid);
      if (map.isNotEmpty) return map;
    } catch (_) {}
    final snap = await firestore
        .collection('content_Assistant_access')
        .where('user_id', isEqualTo: uid)
        .get();
    final map = <String, List<String>>{};
    for (final d in snap.docs) {
      final data = d.data();
      final folderId = data['folder_id'] as String? ?? 'unknown';
      final contentId = data['content_id'] as String?;
      if (contentId != null) {
        map.putIfAbsent(folderId, () => []).add(contentId);
      }
    }
    return map;
  }

  static Future<void> grantAssistantAccess(String uid, String folderId, String name) async {
    await firestore.collection('Assistant_access').add({
      'uid': uid,
      'folderId': folderId,
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> revokeAssistantAccess(String uid, String folderId) async {
    final snap = await firestore
        .collection('Assistant_access')
        .where('uid', isEqualTo: uid)
        .where('folderId', isEqualTo: folderId)
        .get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
    // Cascade: also revoke content/subfolder access inside this folder so the
    // assistant loses access at every level that was granted under this folder.
    try {
      final contentSnap = await firestore
          .collection('content_Assistant_access')
          .where('user_id', isEqualTo: uid)
          .where('folder_id', isEqualTo: folderId)
          .get();
      for (final d in contentSnap.docs) {
        await d.reference.delete();
      }
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getAssistantFolderIds(String uid) async {
    try {
      final mirror = await SupabaseReadService.getAssistantFolderAccess(uid);
      if (mirror != null) {
        return mirror.map((e) => {'id': e['id'], 'folderId': e['folder_id'] ?? e['folderId']}).toList();
      }
    } catch (_) {}
    final snap = await firestore
        .collection('Assistant_access')
        .where('uid', isEqualTo: uid)
        .get();
    return snap.docs.map((e) => {'id': e.id, 'folderId': e.data()['folderId']}).toList();
  }

  static Future<Set<String>> getUidsWithFolderAccess(String folderId) async {
    try {
      final mirror = await SupabaseReadService.getUidsWithFolderAccess(folderId);
      if (mirror != null) return mirror;
    } catch (_) {}
    final snap = await firestore
        .collection('Assistant_access')
        .where('folderId', isEqualTo: folderId)
        .get();
    return snap.docs.map((d) => d.data()['uid'] as String).toSet();
  }

  static Future<Set<String>> getUidsWithContentAccess(String folderId, String contentId) async {
    try {
      final mirror = await SupabaseReadService.getUidsWithContentAccess(contentId, folderId: folderId);
      if (mirror != null) return mirror;
    } catch (_) {}
    final snap = await firestore
        .collection('content_Assistant_access')
        .where('folder_id', isEqualTo: folderId)
        .where('content_id', isEqualTo: contentId)
        .get();
    return snap.docs.map((d) => d.data()['user_id'] as String).toSet();
  }

  // ─── Settings ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSettings() async {
    try {
      final mirror = await SupabaseReadService.getSettings('general');
      if (mirror != null) return mirror;
    } catch (_) {}
    final snap = await firestore.collection('settings').doc('general').get();
    return snap.data() ?? {};
  }

  static Future<void> updateSetting(String key, dynamic value) async {
    SupabaseReadService.invalidateSettingsCache();
    Map<String, dynamic>? current;
    try { current = await SupabaseReadService.readPrimary('settings', 'general'); } catch (_) {}
    current ??= await SupabaseReadService.getSettings('general');
    final data = Map<String, dynamic>.from(current ?? {});
    data[key] = value;
    try {
      await SupabaseReadService.writeToAll('settings', 'general', data);
    } catch (_) {}
    SupabaseReadService.invalidateSettingsCache();
  }

  // ─── AI Conversations ──────────────────────────────────────────────────────────

  static Future<String?> createConversation(String title) async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    final doc = await firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .add({'title': title, 'updatedAt': FieldValue.serverTimestamp()});
    await _mirrorWrite('conversations', doc.id, {
      'uid': uid,
      'title': title,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    return doc.id;
  }

  static Future<List<Map<String, dynamic>>> getConversations() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final mirror = await SupabaseReadService.getConversations(uid);
      if (mirror != null) return mirror;
    } catch (_) {}
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .orderBy('updatedAt', descending: true)
        .get();
    return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
  }

  static Future<void> addMessage(String convId, String role, String content) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    final msgRef = firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(convId)
        .collection('messages');
    final msgDoc = await msgRef.add({
      'role': role,
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await _mirrorWrite('messages', msgDoc.id, {
      'conversationId': convId,
      'uid': uid,
      'role': role,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(convId)
        .update({'updatedAt': FieldValue.serverTimestamp()});
    await _mirrorWrite('conversations', convId, {
      'uid': uid,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getMessages(String convId) async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final mirror = await SupabaseReadService.getMessages(convId);
      if (mirror != null) return mirror;
    } catch (_) {}
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .get();
    return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
  }

  static Future<void> deleteConversation(String convId) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await firestore.collection('users').doc(uid).collection('conversations').doc(convId).delete();
  }

  // ─── App Updates ───────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getAppUpdates() {
    return SupabaseReadService.streamAppUpdates().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<bool> getUserAutoDownload() async {
    final user = FirebaseService.currentUser;
    if (user == null) return true;
    final doc = await FirebaseService.firestore.collection('users').doc(user.uid).get();
    final data = doc.data();
    return data?['autoDownload'] as bool? ?? false;
  }

  static Future<void> updateUserAutoDownload(bool value) async {
    final user = FirebaseService.currentUser;
    if (user == null) return;
    await FirebaseService.firestore.collection('users').doc(user.uid).update({'autoDownload': value});
  }
}

/// Minimal Supabase Storage compat class so existing code using `FirebaseService.storage.ref(...)` works.
class _SupabaseStorageService {
  _SupabaseStorageReference ref(String path) => _SupabaseStorageReference(path);
}

class _SupabaseStorageReference {
  final String fullPath;
  _SupabaseStorageReference(this.fullPath);

  _SupabaseStorageReference get ref => this;

  String get name => fullPath.split('/').last;

  String get _bucket => fullPath.contains('/') ? fullPath.split('/').first : 'notices';
  String get _objectPath => fullPath.contains('/') ? fullPath.substring(fullPath.indexOf('/') + 1) : fullPath;

  Future<String> getDownloadURL() async {
    return '${FirebaseService.supabaseUrl}/storage/v1/object/public/$_bucket/$_objectPath';
  }

  Future<void> putFile(dynamic file) async {
    if (kIsWeb) throw UnsupportedError('putFile not supported on web');
    final bytes = await (file as File).readAsBytes();
    await putData(bytes);
  }

  Future<_SupabaseStorageReference> putData(Uint8List data, {fb_storage.SettableMetadata? metadata, void Function(double progress)? onProgress}) async {
    final uri = Uri.parse('${FirebaseService.supabaseUrl}/storage/v1/object/$_bucket/$_objectPath');
    final filename = _objectPath.split('/').last;
    onProgress?.call(0.1);

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer ${FirebaseService.serviceRoleKey}';
    request.files.add(http.MultipartFile.fromBytes('file', data, filename: filename));
    if (metadata?.contentDisposition != null) {
      request.fields['metadata'] = jsonEncode({'Content-Disposition': metadata!.contentDisposition});
    }
    onProgress?.call(0.5);

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(const Duration(minutes: 5));
      if (streamed.statusCode >= 400) {
        final body = await streamed.stream.bytesToString();
        throw Exception('Supabase upload failed ($fullPath): $body');
      }
      await streamed.stream.bytesToString();
      onProgress?.call(1.0);
    } finally {
      client.close();
    }
    return this;
  }

  Future<void> delete() async {
    final uri = Uri.parse('${FirebaseService.supabaseUrl}/storage/v1/object/$_bucket/$_objectPath');
    final request = http.Request('DELETE', uri)
      ..headers['Authorization'] = 'Bearer ${FirebaseService.serviceRoleKey}';
    final streamed = await request.send();
    if (streamed.statusCode >= 400) {
      final body = await streamed.stream.bytesToString();
      throw Exception('Supabase delete failed ($fullPath): $body');
    }
  }
}

class SessionManager {
  static const Duration _timeout = Duration(minutes: 12);
  static Timer? _timer;
  static DateTime? _lastActivity;
  static VoidCallback? onExpired;
  static bool _isPaused = false;

  static DateTime? get lastActivity => _lastActivity;

  static void start({VoidCallback? onExpiredCallback}) {
    onExpired = onExpiredCallback;
    _lastActivity = DateTime.now();
    _isPaused = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  static void reset() {
    _lastActivity = DateTime.now();
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _lastActivity = null;
    _isPaused = false;
  }

  static void pause() {
    _isPaused = true;
    _timer?.cancel();
    _timer = null;
  }

  static void resume() {
    if (_lastActivity == null || onExpired == null) return;
    final elapsed = DateTime.now().difference(_lastActivity!);
    if (elapsed >= _timeout) {
      stop();
      onExpired?.call();
      return;
    }
    _isPaused = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  static void _check() {
    if (_lastActivity == null || _isPaused) return;
    if (DateTime.now().difference(_lastActivity!) >= _timeout) {
      stop();
      onExpired?.call();
    }
  }
}

/// Lightweight [DocumentSnapshot] adapter backed by a mirror (Supabase) row so
/// code that expects a `DocumentSnapshot` can keep working without a Firestore
/// read. Only `id` / `exists` / `data()` are needed by the app's callers.
class _MirrorDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _MirrorDocumentSnapshot(this._data);

  final Map<String, dynamic> _data;

  @override
  String get id => _data['id'] as String? ?? '';

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('reference not available on mirror snapshot');

  @override
  SnapshotMetadata get metadata => throw UnsupportedError('metadata not available on mirror snapshot');

  @override
  bool get exists => true;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];
}

/// [QueryDocumentSnapshot] adapter for mirror rows.
class _MirrorQueryDocumentSnapshot extends _MirrorDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _MirrorQueryDocumentSnapshot(super.data);

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => _data;
}

/// [QuerySnapshot] adapter so existing `StreamBuilder<QuerySnapshot>` widgets
/// keep working against mirror (Supabase) rows without any UI changes.
class _MirrorQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _MirrorQuerySnapshot(this._rows);

  final List<Map<String, dynamic>> _rows;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs =>
      _rows.map((r) => _MirrorQueryDocumentSnapshot(r)).toList();

  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges {
    // Polls re-emit full lists; flag rows created within the last 30s as
    // "added" so the admin feedback-notification logic keeps working.
    final now = DateTime.now();
    return [
      for (var i = 0; i < _rows.length; i++)
        if (_isRecent(_rows[i]['createdAt'] ?? _rows[i]['created_at'], now))
          _MirrorDocumentChange(
            type: DocumentChangeType.added,
            oldIndex: -1,
            newIndex: i,
            doc: _MirrorQueryDocumentSnapshot(_rows[i]),
          ),
    ];
  }

  @override
  SnapshotMetadata get metadata =>
      throw UnsupportedError('metadata not available on mirror snapshot');

  @override
  int get size => _rows.length;

  static bool _isRecent(dynamic value, DateTime now) {
    final d = _mirrorToDate(value);
    return d != null && now.difference(d).inSeconds < 30;
  }
}

class _MirrorDocumentChange implements DocumentChange<Map<String, dynamic>> {
  _MirrorDocumentChange({
    required this.type,
    required this.oldIndex,
    required this.newIndex,
    required this.doc,
  });

  @override
  final DocumentChangeType type;

  @override
  final int oldIndex;

  @override
  final int newIndex;

  @override
  final DocumentSnapshot<Map<String, dynamic>> doc;
}

/// Parses a mirror date (ISO string, [Timestamp], or [DateTime]) to [DateTime].
DateTime? _mirrorToDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) {
    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {
      return null;
    }
  }
  return null;
}
