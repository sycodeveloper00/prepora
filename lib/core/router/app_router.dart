import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/terms_accept_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/folders/presentation/folder_details_screen.dart';
import '../../features/ai_tutor/presentation/ai_chat_screen.dart';
import '../../features/test_practice/presentation/test_practice_screen.dart';
import '../../features/lectures/presentation/video_player_screen.dart';
import '../../features/pdf_reader/presentation/pdf_reader_screen.dart';
import '../../features/assistant/presentation/assistant_dashboard_screen.dart';
import '../../features/notepad/presentation/notepad_screen.dart';
import '../../features/notepad/presentation/notes_list_screen.dart';
import '../../features/notices/presentation/student_notice_screen.dart';
import '../../features/feedback/presentation/student_feedback_screen.dart';
import '../../features/media_player/presentation/media_player_screen.dart';
import '../../features/image_viewer/presentation/image_viewer_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/auto_downloads_screen.dart';
import '../../features/webview/presentation/webview_screen.dart';
import '../../features/splash_onboarding/presentation/splash_screen.dart';
import '../../features/student/presentation/student_progress_screen.dart';
import '../../features/link_web/presentation/link_web_screen.dart';
import '../../features/deep_link/presentation/deep_link_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    errorBuilder: (context, state) {
      final uri = state.uri.toString();
      // Admin routes not supported in Android app — redirect to login
      if (uri.startsWith('/admin')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.go('/auth/login');
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (uri.contains('.pdf') || uri.startsWith('content://') || uri.startsWith('file://')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.go('/pdf_reader/view', extra: {'url': uri});
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('Page not found', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Text(uri, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      );
    },
    routes: <RouteBase>[
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/auth/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/auth/signup', builder: (c, s) => const SignupScreen()),
      GoRoute(path: '/auth/forgot-password', builder: (c, s) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/auth/reset-password',
        builder: (c, s) {
          final token = s.uri.queryParameters['token'];
          return ResetPasswordScreen(token: token);
        },
      ),

      GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
      GoRoute(
        path: '/folders/:id/sub/:contentId',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return FolderDetailsScreen(
            key: ValueKey('/folders/${s.pathParameters['id']!}/sub/${s.pathParameters['contentId']!}'),
            folderId: s.pathParameters['id']!,
            parentContentId: s.pathParameters['contentId']!,
            canEdit: extra?['canEdit'] as bool? ?? false,
            canManage: extra?['canManage'] as bool? ?? false,
            isAdmin: extra?['isAdmin'] as bool? ?? false,
            targetStudentUid: extra?['targetStudentUid'] as String?,
            assistantContentAccess: extra?['assistantContentAccess'] is List
                ? (extra!['assistantContentAccess'] as List).cast<String>().toSet()
                : null,
          );
        },
      ),
      GoRoute(
        path: '/folders/:id',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return FolderDetailsScreen(
            key: ValueKey('/folders/${s.pathParameters['id']!}'),
            folderId: s.pathParameters['id']!,
            canEdit: extra?['canEdit'] as bool? ?? false,
            canManage: extra?['canManage'] as bool? ?? false,
            isAdmin: extra?['isAdmin'] as bool? ?? false,
            targetStudentUid: extra?['targetStudentUid'] as String?,
            assistantContentAccess: extra?['assistantContentAccess'] is List
                ? (extra!['assistantContentAccess'] as List).cast<String>().toSet()
                : null,
            parentContentId: extra?['parentContentId'] as String?,
          );
        },
      ),
      GoRoute(path: '/ai_tutor', builder: (c, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return AiChatScreen(folderContext: extra?['folderContext'] as String?);
      }),
      GoRoute(
        path: '/notepad/:lectureId',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return NotepadScreen(
            lectureId: s.pathParameters['lectureId']!,
            lectureName: extra?['name'] as String? ?? 'Lecture',
          );
        },
      ),
      GoRoute(path: '/terms', builder: (c, s) => const TermsAcceptScreen()),
      GoRoute(path: '/notes', builder: (c, s) => const NotesListScreen()),
      GoRoute(path: '/student/notices', builder: (c, s) => const StudentNoticeScreen()),
      GoRoute(path: '/student/feedbacks', builder: (c, s) => const StudentFeedbackScreen()),
      GoRoute(path: '/student/progress', builder: (c, s) => const StudentProgressScreen()),
      GoRoute(
        path: '/media_player',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MediaPlayerScreen(
            url: extra?['url'] as String? ?? '',
            title: extra?['title'] as String? ?? 'Media',
            isAudio: extra?['isAudio'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/image_viewer',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return ImageViewerScreen(
            url: extra?['url'] as String? ?? '',
            title: extra?['title'] as String? ?? 'Image',
          );
        },
      ),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/auto-downloads', builder: (c, s) => const AutoDownloadsScreen()),
      GoRoute(path: '/practice/:id', builder: (c, s) => TestPracticeScreen(testId: s.pathParameters['id']!)),
      GoRoute(
        path: '/lectures/:id',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return VideoPlayerScreen(
            videoId: s.pathParameters['id']!,
            lectureName: extra?['name'] as String? ?? 'Lecture',
            subFolderName: extra?['folderName'] as String?,
            folderId: extra?['folderId'] as String?,
            parentContentId: extra?['parentContentId'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/pdf_reader/view',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return PdfReaderScreen(
            documentId: extra?['url'] as String? ?? '',
            folderId: extra?['folderId'] as String?,
            parentContentId: extra?['parentContentId'] as String?,
            title: extra?['title'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/assistant',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AssistantDashboardScreen(
            folderIds: extra?['folderIds'] as List<String>?,
            assistantName: extra?['assistantName'] as String?,
          );
        },
      ),
      GoRoute(path: '/link-web', builder: (c, s) => const LinkWebScreen()),
      GoRoute(
        path: '/open',
        builder: (c, s) {
          final id = s.uri.queryParameters['id'];
          final type = s.uri.queryParameters['type'];
          final parent = s.uri.queryParameters['parent'];
          return DeepLinkScreen(id: id, type: type, parent: parent);
        },
      ),
      GoRoute(
        path: '/open/folder/:folderId/:slug/share',
        builder: (c, s) {
          final id = s.uri.queryParameters['id'];
          final type = s.uri.queryParameters['type'];
          final parent = s.uri.queryParameters['parent'];
          return DeepLinkScreen(id: id, type: type, parent: parent);
        },
      ),
      GoRoute(
        path: '/folder/:folderId/:slug/share',
        builder: (c, s) {
          final id = s.uri.queryParameters['id'];
          final type = s.uri.queryParameters['type'];
          final parent = s.uri.queryParameters['parent'];
          return DeepLinkScreen(id: id, type: type, parent: parent);
        },
      ),
      GoRoute(
        path: '/webview',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AppWebViewScreen(
            url: extra?['url'] as String?,
            html: extra?['html'] as String?,
            title: extra?['title'] as String? ?? 'Viewer',
            folderId: extra?['folderId'] as String?,
            parentContentId: extra?['parentContentId'] as String?,
            isMockTest: extra?['isMockTest'] as bool? ?? false,
          );
        },
      ),
    ],
  );
}
