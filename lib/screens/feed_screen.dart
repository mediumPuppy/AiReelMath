import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../widgets/video_feed_item.dart';
import '../models/video_feed.dart';
import '../widgets/app_drawer.dart';
import '../services/firestore_service.dart';
import '../services/topic_progress_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../services/gpt_service.dart';
import 'package:uuid/uuid.dart';
import '../services/progress/video_progress_tracker.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _PathVideoFeed extends StatefulWidget {
  final String? selectedPath;

  const _PathVideoFeed({
    required this.selectedPath,
  });

  @override
  State<_PathVideoFeed> createState() => _PathVideoFeedState();
}

class _PathVideoFeedState extends State<_PathVideoFeed> {
  final PageController _pageController = PageController();
  final FirestoreService _firestoreService = FirestoreService();
  final _progressService = TopicProgressService();
  Map<String, VideoProgressTracker> _videoProgressTrackers = {};
  int _lastPage = 0;
  int _lastVideoCount = 0; // Track video count changes

  @override
  void initState() {
    super.initState();
    print('[FeedScreen] Initializing VideoProgressTracker map');
    _pageController.addListener(_handlePageChange);
  }

  void _handlePageChange() {
    if (_pageController.page != null) {
      final currentPage = _pageController.page!.round();
      if (currentPage > _lastPage) {
        // Scrolling down (next video)
        _progressService.incrementPosition();
      } else if (currentPage < _lastPage) {
        // Scrolling up (previous video)
        _progressService.decrementPosition();
      }
      _lastPage = currentPage;
    }
  }

  @override
  void dispose() {
    print('[FeedScreen] Disposing VideoProgressTracker');
    _pageController.removeListener(_handlePageChange);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please log in to view videos'));
    }

    if (widget.selectedPath == null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.explore_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 24),
              Text(
                'Choose Your Math Adventure!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Select a learning path to start watching fun math videos',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.black87,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/learning_paths');
                },
                icon: const Icon(Icons.map_rounded),
                label: const Text('Browse Learning Paths'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.getVideosByLearningPath(widget.selectedPath!),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        // Only show loading if we're waiting for the first data
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final videos = snapshot.data?.docs ?? [];

        if (videos.isEmpty) {
          return Center(
            child: Container(
              padding: const EdgeInsets.all(28),
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: Theme.of(context).colorScheme.tertiary.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Icon(
                        Icons.celebration_rounded,
                        size: 80,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Amazing Job! 🎉',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You\'ve mastered all topics in this learning path!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ready for a new challenge?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/learning_paths');
                    },
                    icon: const Icon(Icons.explore),
                    label: const Text('Find New Adventures'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.tertiary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Only set total videos when path/topic changes, not during scrolling
        if (_lastVideoCount != videos.length) {
          _lastVideoCount = videos.length;
          _progressService.setTotalVideos(videos.length);
        }

        return PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: videos.length,
          onPageChanged: (index) {
            if (index == 0) {
              // Reset progress when starting a new topic
              // _progressService.setTotalVideos(videos.length);
            }
          },
          itemBuilder: (context, index) {
            final videoData = videos[index].data() as Map<String, dynamic>;
            final videoId = videos[index].id;

            try {
              final video = VideoFeed.fromFirestore(videoData, videoId);
              // Create tracker for this video if it doesn't exist
              _videoProgressTrackers[videoId] ??= VideoProgressTracker(video);

              return Stack(
                children: [
                  VideoFeedItem(
                    index: index,
                    feed: video,
                    onShare: () {},
                    pageController: _pageController,
                    userId: user.uid,
                    progressTracker: _videoProgressTrackers[videoId]!,
                    onQuizComplete: () {
                      // Use the static method to start playback
                      VideoFeedItem.startPlayback(context);
                    },
                  ),
                  // Detect last video by comparing index with total count
                  if (index == videos.length - 1)
                    Positioned(
                      bottom: 24,
                      left: 20,
                      right: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            print('[VideoFeed] Create new video button clicked');
                            _FeedScreenState? feedScreenState = context
                                .findAncestorStateOfType<_FeedScreenState>();
                            if (feedScreenState != null) {
                              feedScreenState._handleCreateNewVideo();
                            } else {
                              print(
                                  '[VideoFeed] ERROR: Could not find FeedScreenState');
                            }
                          },
                          icon: const Icon(Icons.video_library_rounded),
                          label: const Text('Create New Math Video!'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            } catch (e) {
              return const SizedBox.shrink(); // Skip invalid videos
            }
          },
        );
      },
    );
  }
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _gptService = GptService();
  String? _selectedLearningPath;
  StreamSubscription? _pathSubscription;
  late AnimationController _animationController;
  final _uuid = const Uuid();

  String generateUniqueId() => _uuid.v4();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadUserLearningPath();
  }

  void _loadUserLearningPath() {
    final user = _auth.currentUser;
    if (user != null) {
      _pathSubscription =
          _firestoreService.getUserLearningPath(user.uid).listen(
        (snapshot) {
          if (mounted) {
            final data = snapshot.data();
            setState(() {
              _selectedLearningPath = data?['currentPath'] as String?;
            });
          }
        },
        onError: (error, stackTrace) {
          print('Error loading learning path: $error');
        },
      );
    } else {
      print('No user logged in');
    }
  }

  Future<void> _handleCreateNewVideo() async {
    print('[CreateVideo] Starting video creation process');

    if (_selectedLearningPath == null) {
      print('[CreateVideo] ERROR: No learning path selected');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a learning path first")),
      );
      return;
    }

    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Creating new video...")),
      );

      // Get the current topic info based on the learning path
      final topicInfo =
          await _firestoreService.getCurrentTopicInfo(_selectedLearningPath!);
      if (topicInfo == null) {
        print('[CreateVideo] ERROR: No topics found for learning path');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("No topics found for this learning path")),
        );
        return;
      }

      final String topicId = topicInfo['id'] as String;
      final String topicTitle = topicInfo['title'] as String;
      final String topicDescription = topicInfo['description'] as String;
      final String subject = topicInfo['subject'] as String;

      print('[CreateVideo] Creating video for topic: $topicTitle ($topicId)');

      // Generate prompt from topic information
      final String prompt =
          '''Create an educational video that teaches $topicTitle using SPECIFIC NUMBERS and CONCRETE EXAMPLES.
      
Topic description: $topicDescription

Subject: $subject
Learning path: ${_selectedLearningPath!}

IMPORTANT REQUIREMENTS:
1. Create a K-5 math lesson that teaches with ACTUAL NUMBERS and REAL MATH PROBLEMS
2. DO NOT create abstract lessons about "multiple approaches" or "perseverance in problem-solving"
3. DO show step-by-step solving of SPECIFIC math problems with definite numerical answers 
4. Use age-appropriate examples with actual equations, numbers, or operations
5. Focus on teaching the math directly through concrete examples, not through meta-lessons about thinking strategies

Example: Instead of "Remember to try different approaches when solving problems", show "5 + 3 = 8" or "If Amy has 7 apples and gives 2 away, she has 5 apples left."''';

      // Step 1: Generate the video content
      print('[CreateVideo] Calling GPT service with prompt: $prompt');
      final Map<String, dynamic> videoJson =
          await _gptService.sendPrompt(prompt);
      print('[CreateVideo] Received response from GPT service');

      // Step 2: Generate title and description based on the content
      print('[CreateVideo] Generating video metadata...');
      final metadata = await _gptService.generateVideoMetadata(videoJson);
      print('[CreateVideo] Generated metadata: $metadata');

      // Step 3: Create video with AI-generated title/description and topic information
      print('[CreateVideo] Creating VideoFeed object');

      // Get count of existing videos for this topic to determine order
      final existingVideos =
          await _firestoreService.getVideosByTopic(topicId).first;
      final int orderInPath = existingVideos.docs.length + 1;

      final newVideo = VideoFeed(
        id: generateUniqueId(),
        title: metadata['title']!,
        topicId: topicId,
        subject: subject,
        skillLevel: "beginner",
        prerequisites: [],
        description: metadata['description']!,
        learningPathId: _selectedLearningPath!,
        orderInPath: orderInPath,
        estimatedMinutes: 5,
        hasQuiz: false,
        videoUrl: "",
        videoJson: videoJson,
        creatorId: _auth.currentUser?.uid ?? "system",
        likes: 0,
        shares: 0,
        createdAt: DateTime.now(),
      );
      print('[CreateVideo] Created VideoFeed object with ID: ${newVideo.id}');

      // Step 4: Save to Firestore
      print('[CreateVideo] Storing video in Firestore...');
      await _firestoreService.createVideo(newVideo);
      print('[CreateVideo] Successfully stored video in Firestore');

      // Allow Firestore to update
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "New video created successfully for topic: $topicTitle")),
        );
      }
    } catch (e, stackTrace) {
      print('[CreateVideo] ERROR: Failed to create video');
      print('[CreateVideo] Error details: $e');
      print('[CreateVideo] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to create new video: $e")),
        );
      }
    }
  }

  @override
  void dispose() {
    _pathSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _PathVideoFeed(selectedPath: _selectedLearningPath),
      ),
    );
  }
}
