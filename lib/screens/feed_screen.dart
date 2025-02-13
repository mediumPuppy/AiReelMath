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
  int _lastPage = 0;
  int _lastVideoCount = 0; // Track video count changes

  @override
  void initState() {
    super.initState();
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
    _pageController.removeListener(_handlePageChange);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedPath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Select a Learning Path',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/learning_paths');
              },
              child: const Text('Browse Learning Paths'),
            ),
          ],
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.celebration,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Congratulations!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You\'ve completed all topics in this learning path.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/learning_paths');
                  },
                  icon: const Icon(Icons.explore),
                  label: const Text('Explore New Learning Paths'),
                ),
              ],
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
              return Stack(
                children: [
                  VideoFeedItem(
                    index: index,
                    feed: video,
                    onShare: () {},
                    pageController: _pageController,
                  ),
                  // Detect last video by comparing index with total count
                  if (index == videos.length - 1)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: ElevatedButton(
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
                        child: const Text('Create new video?'),
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

    // Capture current topic
    final String? topic = "basic multiplication";
    if (topic == null) {
      print('[CreateVideo] ERROR: No topic selected');
      return;
    }
    print('[CreateVideo] Creating video for topic: $topic');

    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Creating new video...")),
      );

      // Step 1: Generate the video content
      print('[CreateVideo] Calling GPT service...');
      final Map<String, dynamic> videoJson =
          await _gptService.sendPrompt(topic);
      print('[CreateVideo] Received response from GPT service');

      // Step 2: Generate title and description based on the content
      print('[CreateVideo] Generating video metadata...');
      final metadata = await _gptService.generateVideoMetadata(videoJson);
      print('[CreateVideo] Generated metadata: $metadata');

      // Step 3: Create video with AI-generated title/description and manually set fields
      print('[CreateVideo] Creating VideoFeed object');
      final newVideo = VideoFeed(
        id: generateUniqueId(),
        title: metadata['title']!,
        topicId: "equations", // Manually set - should come from UI selection
        subject: "algebra", // Manually set - should come from UI selection
        skillLevel:
            "beginner", // Manually set - should come from UI/system setting
        prerequisites: [],
        description: metadata['description']!,
        learningPathId: _selectedLearningPath!,
        orderInPath: 0,
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
          const SnackBar(content: Text("New video created successfully!")),
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
