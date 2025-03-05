import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/learning_paths_screen.dart';
import 'screens/upload_answer_screen.dart';
import 'screens/quizzes_screen.dart';
import 'services/auth_service.dart';
import 'services/quiz_service.dart';
import 'widgets/app_drawer.dart';

void main() async {
  print('Starting app initialization...');
  WidgetsFlutterBinding.ensureInitialized();
  print('Flutter binding initialized');

  // Load environment variables
  try {
    await dotenv.load();
    print('Environment variables loaded successfully');
  } catch (e) {
    print('Error loading environment variables: $e');
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    print('Error initializing Firebase: $e');
  }

  // Initialize test data
  try {
    final quizService = QuizService();
    await quizService.initializeSampleQuizzes();
    print('Sample quizzes initialized');
  } catch (e) {
    print('Error initializing sample quizzes: $e');
  }

  print('Running app...');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('Building MyApp widget');
    return MaterialApp(
      title: 'ReelMath',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: StreamBuilder<User?>(
        stream: AuthService().authStateChanges,
        builder: (context, snapshot) {
          print('Auth state connection state: ${snapshot.connectionState}');
          print('Auth state has error: ${snapshot.hasError}');
          if (snapshot.hasError) {
            print('Auth state error: ${snapshot.error}');
          }

          if (snapshot.connectionState == ConnectionState.active) {
            User? user = snapshot.data;
            print('Current user: ${user?.uid ?? 'null'}');
            if (user == null) {
              print('Showing login screen');
              return const LoginScreen();
            }
            print('Showing home screen');
            return const HomeScreen();
          }
          print('Showing loading indicator');
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      ),
      routes: {
        '/learning_paths': (context) => LearningPathsScreen(),
        '/upload_answer': (context) => const UploadAnswerScreen(),
        '/quizzes': (context) => QuizzesScreen(),
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ReelMath'),
      ),
      drawer: const AppDrawer(),
      body: const FeedScreen(),
    );
  }
}
