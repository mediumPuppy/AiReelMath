import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/learning_progress_service.dart';
import '../services/quiz_scheduler_service.dart';
import '../screens/quiz_screen.dart';
import '../screens/topics_screen.dart';
import '../models/quiz_model.dart';
import 'dart:async';

// the quiz class is undefined below, do we need to import it here?

class LearningPathsScreen extends StatefulWidget {
  const LearningPathsScreen({super.key});

  @override
  _LearningPathsScreenState createState() => _LearningPathsScreenState();
}

class _LearningPathsScreenState extends State<LearningPathsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LearningProgressService _progressService = LearningProgressService();
  final QuizSchedulerService _quizScheduler = QuizSchedulerService();
  bool _isInitialized = false;
  String? _selectedPathId;
  StreamSubscription? _pathSubscription;
  Timer? _quizCheckTimer;
  bool _isLoading = false;
  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
    _startQuizCheck();
  }

  @override
  void dispose() {
    _pathSubscription?.cancel();
    _quizCheckTimer?.cancel();
    super.dispose();
  }

  void _startQuizCheck() {
    // Check for quiz triggers every 5 minutes
    _quizCheckTimer =
        Timer.periodic(Duration(minutes: 5), (_) => _checkForQuiz());
  }

  Future<void> _checkForQuiz() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final shouldTrigger = await _progressService.shouldTriggerQuiz(user.uid);
      if (!shouldTrigger) return;

      final currentTopics = await _getCurrentTopics();
      if (currentTopics.isEmpty) return;

      final quiz = await _quizScheduler.generateQuizForUser(
        userId: user.uid,
        currentTopics: currentTopics,
      );

      if (quiz != null && mounted) {
        _showQuizPrompt(quiz);
      }
    } catch (e) {
      // Error handling without logging
    }
  }

  Future<List<String>> _getCurrentTopics() async {
    if (_selectedPathId == null) return [];

    final pathDoc =
        await _firestoreService.getLearningPathTopics(_selectedPathId!).first;

    final topics =
        pathDoc.docs.map((doc) => doc.data()['id'] as String).toList();
    return topics;
  }

  void _showQuizPrompt(Quiz quiz) {
    final user = _auth.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Time for a Progress Check!'),
        content: Text(
          'Ready to test your knowledge of recent topics? '
          'This quiz will help reinforce your learning.',
        ),
        actions: [
          TextButton(
            child: Text('Later'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: Text('Start Quiz'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QuizScreen(
                    quiz: quiz,
                    userId: user.uid,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _initializeData() async {
    if (!_isInitialized && mounted) {
      try {
        await _firestoreService.initializeSampleData();
        await _firestoreService.temporaryUpdateLearningPaths();
        await _firestoreService.initializeTopics();
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error initializing data: $e')),
          );
        }
      }
    }
  }

  void _refreshData() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Clear existing data first (learning paths, topics, and videos)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Clearing existing data...')),
      );
      await _firestoreService.clearExistingData();
      
      // Re-initialize with fresh data
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploading new data...')),
      );
      
      // Initialize curriculum data (includes learning paths and topics)
      await _firestoreService.initializeCurriculumData();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Data refresh complete!')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _loadCurrentPath() {
    final user = _auth.currentUser;
    if (user != null) {
      _pathSubscription =
          _firestoreService.getUserLearningPath(user.uid).listen((snapshot) {
        if (mounted) {
          setState(() {
            _selectedPathId = snapshot.data()?['currentPath'] as String?;
          });
        }
      });
    }
  }

  Future<void> _selectLearningPath(String pathId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestoreService.setCurrentLearningPath(user.uid, pathId);
      setState(() => _selectedPathId = pathId);

      // Navigate to topics screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TopicsScreen(
              learningPathId: pathId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting learning path: $e')),
        );
      }
    }
  }

  Widget _buildPathCard(DocumentSnapshot<Map<String, dynamic>> doc) {
    final path = doc.data()!;
    final pathId = doc.id;

    return FutureBuilder<int>(
      future: _firestoreService.getTopicCount(pathId),
      builder: (context, snapshot) {
        final topicCount = snapshot.data ?? 0;

        return Card(
          margin: EdgeInsets.all(8.0),
          child: ListTile(
            title: Text(path['title']),
            subtitle: Text(path['description']),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text('$topicCount topics'),
                  backgroundColor: Colors.blue.shade100,
                ),
                if (_selectedPathId == pathId)
                  Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            onTap: () => _selectLearningPath(pathId),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Learning Paths'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestoreService.getLearningPaths(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final paths = snapshot.data?.docs ?? [];

          return ListView.builder(
            itemCount: paths.length,
            itemBuilder: (context, index) => _buildPathCard(paths[index]),
          );
        },
      ),
    );
  }
}
