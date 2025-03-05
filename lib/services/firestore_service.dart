import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:test/data/sample_videos.dart';
import './learning_progress_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:convert';
import '../data/geometry_drawing_spec.dart';
import '../models/video_feed.dart';
import 'package:flutter/services.dart' show rootBundle;

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LearningProgressService _progressService = LearningProgressService();

  // User Methods
  Future<void> createUserProfile(String userId, String email,
      {String? userName}) {
    return _db.collection('users').doc(userId).set({
      'email': email,
      'userName': userName ?? email.split('@')[0],
      'createdAt': FieldValue.serverTimestamp(),
      'completedTopics': [],
      'progress': {},
    });
  }

  Future<String?> getUserName(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return doc.data()?['email'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> getMentionSuggestions(String prefix) async {
    if (prefix.isEmpty) return [];

    final userQuery = await _db
        .collection('users')
        .where('userName', isGreaterThanOrEqualTo: prefix)
        .where('userName', isLessThan: '${prefix}z')
        .limit(5)
        .get();

    return userQuery.docs
        .map((doc) => doc.data()['userName'] as String)
        .where((userName) => userName.isNotEmpty)
        .toList();
  }

  // Learning Path Methods
  Stream<DocumentSnapshot<Map<String, dynamic>>> getUserLearningPath(
      String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data() ?? {},
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getLearningPaths() {
    return _db
        .collection('learning_paths')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data() ?? {},
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getLearningPathTopics(
      String learningPathId) {
    return _db
        .collection('topics')
        .where('learningPathId', isEqualTo: learningPathId)
        .orderBy('orderIndex')
        .snapshots();
  }

  Future<void> setCurrentLearningPath(String userId, String pathId) {
    return _db.collection('users').doc(userId).update({
      'currentPath': pathId,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setUserLearningPath(String userId, String pathId) async {
    await _db.collection('users').doc(userId).set({
      'currentPath': pathId,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<int> getTopicCount(String pathId) async {
    final snapshot = await _db
        .collection('topics')
        .where('learningPathId', isEqualTo: pathId)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  // Video Methods
  Stream<QuerySnapshot<Map<String, dynamic>>> getVideosForDifficulty(
      String difficulty) {
    var query = _db.collection('videos').orderBy('order');

    if (difficulty != "All") {
      query = query.where('difficulty', isEqualTo: difficulty);
    }

    return query
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data()!,
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getVideosByTopic(String topicId) {
    return _db
        .collection('videos')
        .where('topicId', isEqualTo: topicId)
        .orderBy('createdAt')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data()!,
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getVideosByLearningPath(
      String learningPathId) async* {
    debugPrint('learningPathId: $learningPathId');
    final userId = _auth.currentUser?.uid;
    debugPrint('userId: $userId');
    if (userId == null) {
      debugPrint('No user logged in, returning empty video list');
      yield* _db
          .collection('videos')
          .where('learningPathId', isEqualTo: learningPathId)
          .limit(1) // Changed from limit(0)
          .snapshots();
      return;
    }

    // Get current progress
    final progressDoc = await _db.collection('user_progress').doc(userId).get();
    final progress = progressDoc.data() ?? {};
    final completedTopics =
        (progress['topicsCompleted'] as Map<String, dynamic>? ?? {})
            .keys
            .toSet();

    debugPrint('User completed topics: $completedTopics');

    // Get learning path topics
    final topicsQuery = await _db
        .collection('topics')
        .where('learningPathId', isEqualTo: learningPathId)
        .orderBy('orderIndex')
        .get();

    final topics = topicsQuery.docs;
    debugPrint(
        'Found ${topics.length} topics for learning path: $learningPathId');

    if (topics.isEmpty) {
      debugPrint('No topics found for learning path: $learningPathId');
      yield* _db
          .collection('videos')
          .where('learningPathId', isEqualTo: learningPathId)
          .limit(1)
          .snapshots();
      return;
    }

    // Find the first incomplete topic
    String? currentTopicId;
    for (final topic in topics) {
      final topicId = topic.id;
      final topicData = topic.data();
      debugPrint('Checking topic: ${topicData['title']} (ID: $topicId)');

      if (!completedTopics.contains(topicId)) {
        currentTopicId = topicId;
        debugPrint('Found first incomplete topic: $topicId');
        break;
      }
    }

    if (currentTopicId == null) {
      debugPrint('All topics completed, returning empty video list');
      yield* _db
          .collection('videos')
          .where('learningPathId', isEqualTo: 'completed_$learningPathId')
          .snapshots();
      return;
    }

    debugPrint('Getting videos for topic: $currentTopicId');
    // Get videos for the current topic
    yield* _db
        .collection('videos')
        .where('topicId', isEqualTo: currentTopicId)
        .where('learningPathId', isEqualTo: learningPathId)
        .orderBy('orderInPath')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getVideosBySelectedTopic(
      String topicId) {
    return _db
        .collection('videos')
        .where('topic', isEqualTo: topicId)
        .orderBy('createdAt')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data()!,
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getRandomVideos() {
    return _db
        .collection('videos')
        .orderBy('createdAt')
        .limit(20)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data()!,
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Stream<int> getVideoCommentsCount(String videoId) {
    return _db
        .collection('videos')
        .doc(videoId)
        .snapshots()
        .map((snapshot) => snapshot.data()?['comments'] ?? 0);
  }

  Stream<int> getVideoLikesCount(String videoId) {
    return _db
        .collection('videos')
        .doc(videoId)
        .snapshots()
        .map((snapshot) => snapshot.data()?['likes'] ?? 0);
  }

  // Comment Methods
  Future<DocumentReference> addVideoComment(
    String videoId,
    String comment, {
    String? replyToId,
    List<String> mentionedUsers = const [],
  }) async {
    if (userId == null) {
      debugPrint('[ERROR] addVideoComment - User not signed in');
      throw Exception('User not signed in');
    }

    final userName = await getUserName(userId!);
    if (userName == null) {
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email != null) {
        final commentData = {
          'videoId': videoId,
          'userId': userId,
          'userName': email,
          'comment': comment,
          'timestamp': FieldValue.serverTimestamp(),
          'likes': 0,
          'replyToId': replyToId,
          'mentionedUsers': mentionedUsers,
        };

        try {
          final commentRef =
              await _db.collection('video_comments').add(commentData);
          await _db
              .collection('videos')
              .doc(videoId)
              .update({'comments': FieldValue.increment(1)});

          if (mentionedUsers.isNotEmpty) {
            for (final mentionedUser in mentionedUsers) {
              await _db.collection('notifications').add({
                'type': 'mention',
                'userId': userId,
                'mentionedUser': mentionedUser,
                'mentionedBy': email,
                'commentId': commentRef.id,
                'videoId': videoId,
                'timestamp': FieldValue.serverTimestamp(),
                'read': false,
              });
            }
          }

          return commentRef;
        } catch (e) {
          throw Exception('Failed to add comment: $e');
        }
      }
      throw Exception('User profile not found');
    }

    final commentData = {
      'videoId': videoId,
      'userId': userId,
      'userName': userName,
      'comment': comment,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': 0,
      'replyToId': replyToId,
      'mentionedUsers': mentionedUsers,
    };

    try {
      final commentRef =
          await _db.collection('video_comments').add(commentData);
      await _db
          .collection('videos')
          .doc(videoId)
          .update({'comments': FieldValue.increment(1)});

      if (mentionedUsers.isNotEmpty) {
        for (final mentionedUser in mentionedUsers) {
          await _db.collection('notifications').add({
            'type': 'mention',
            'userId': userId,
            'mentionedUser': mentionedUser,
            'mentionedBy': userName,
            'commentId': commentRef.id,
            'videoId': videoId,
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
          });
        }
      }

      return commentRef;
    } catch (e) {
      throw Exception('Failed to add comment: $e');
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getVideoComments(
    String videoId, {
    required String sortBy,
    DocumentSnapshot? lastDocument,
    int limit = 10,
  }) {
    var query = _db
        .collection('video_comments')
        .where('videoId', isEqualTo: videoId)
        .where('replyToId', isNull: true)
        .limit(limit);

    if (sortBy == 'likes') {
      query = query.orderBy('likes', descending: true);
    } else {
      query = query.orderBy('timestamp', descending: true);
    }

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }

    return query
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) {
            return snapshot.data()!;
          },
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getCommentReplies(
      String commentId) {
    return _db
        .collection('video_comments')
        .where('replyToId', isEqualTo: commentId)
        .orderBy('timestamp', descending: false)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data()!,
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  // Topic Methods
  Stream<QuerySnapshot<Map<String, dynamic>>> getTopics() {
    return _db
        .collection('topics')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data()!,
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  Future<void> setUserSelectedTopic(String userId, String topicId) async {
    await _db.collection('users').doc(userId).set({
      'selectedTopic': topicId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<String?> getUserSelectedTopic(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) => snapshot.data()?['selectedTopic'] as String?);
  }
  
  Future<Map<String, dynamic>?> getCurrentTopicInfo(String learningPathId) async {
    try {
      // Get all topics for this learning path
      final topicsQuery = await _db
          .collection('topics')
          .where('learningPathId', isEqualTo: learningPathId)
          .orderBy('orderIndex')
          .get();
      
      // User progress tracking
      String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (userId.isEmpty) return null;
      
      // Get completed topics for this user
      final userProgressDoc = await _db.collection('user_progress').doc(userId).get();
      final completedTopics = (userProgressDoc.data()?['topicsCompleted'] as Map<String, dynamic>? ?? {})
          .keys
          .toSet();
      
      // Find the first incomplete topic (current topic)
      for (final topicDoc in topicsQuery.docs) {
        final topicId = topicDoc.id;
        if (!completedTopics.contains(topicId)) {
          return {
            'id': topicId,
            'title': topicDoc.data()['title'] as String? ?? '',
            'description': topicDoc.data()['description'] as String? ?? '',
            'subject': topicDoc.data()['subject'] as String? ?? '',
            'learningPathId': learningPathId,
          };
        }
      }
      
      // If all topics are completed, return the last one
      if (topicsQuery.docs.isNotEmpty) {
        final lastTopic = topicsQuery.docs.last;
        return {
          'id': lastTopic.id,
          'title': lastTopic.data()['title'] as String? ?? '',
          'description': lastTopic.data()['description'] as String? ?? '',
          'subject': lastTopic.data()['subject'] as String? ?? '',
          'learningPathId': learningPathId,
        };
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting current topic: $e');
      return null;
    }
  }

  Future<void> markTopicAsCompleted(String userId, String topicId) async {
    // Update the completedTopics array
    await _db.collection('users').doc(userId).update({
      'completedTopics': FieldValue.arrayUnion([topicId])
    });

    // Also store in the subcollection for more detailed tracking
    await _db
        .collection('users')
        .doc(userId)
        .collection('completedTopics')
        .doc(topicId)
        .set({
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markTopicAsIncomplete(String userId, String topicId) async {
    // Remove from the completedTopics array
    await _db.collection('users').doc(userId).update({
      'completedTopics': FieldValue.arrayRemove([topicId])
    });

    // Also remove from the subcollection
    await _db
        .collection('users')
        .doc(userId)
        .collection('completedTopics')
        .doc(topicId)
        .delete();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getCompletedTopics(
      String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('completedTopics')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data()!,
          toFirestore: (data, _) => data,
        )
        .snapshots();
  }

  // Initialization Methods
  Future<void> clearExistingData() async {
    debugPrint('Starting data cleanup...');
    
    // Use separate batches to avoid exceeding batch size limits
    final videosBatch = _db.batch();
    final topicsBatch = _db.batch();
    final learningPathsBatch = _db.batch();
    
    // Clear videos
    debugPrint('Clearing existing videos...');
    final existingVideos = await _db.collection('videos').get();
    for (final doc in existingVideos.docs) {
      videosBatch.delete(doc.reference);
    }
    await videosBatch.commit();
    debugPrint('Existing videos cleared: ${existingVideos.docs.length} videos');
    
    // Clear topics
    debugPrint('Clearing existing topics...');
    final existingTopics = await _db.collection('topics').get();
    for (final doc in existingTopics.docs) {
      topicsBatch.delete(doc.reference);
    }
    await topicsBatch.commit();
    debugPrint('Existing topics cleared: ${existingTopics.docs.length} topics');
    
    // Clear learning paths
    debugPrint('Clearing existing learning paths...');
    final existingPaths = await _db.collection('learning_paths').get();
    for (final doc in existingPaths.docs) {
      learningPathsBatch.delete(doc.reference);
    }
    await learningPathsBatch.commit();
    debugPrint('Existing learning paths cleared: ${existingPaths.docs.length} learning paths');
    
    debugPrint('Data cleanup complete');
  }

  Future<void> initializeSampleData() async {
    debugPrint('Starting sample data initialization...');
    
    debugPrint('Initializing videos...');

    // Add sample videos directly with their topic IDs
    for (var video in sampleVideos) {
      final videoData = Map<String, dynamic>.from(video);

      // Convert DateTime to Timestamp for Firestore
      videoData['createdAt'] =
          Timestamp.fromDate(videoData['createdAt'] as DateTime);
      
      // Ensure videoJson is properly formatted to enable rendering
      if (videoData['videoJson'] == null || (videoData['videoJson'] is Map && videoData['videoJson'].isEmpty)) {
        // Use the geometry drawing spec for videoJson
        final Map<String, dynamic> videoJsonData = 
            jsonDecode(geometryDrawingSpec) as Map<String, dynamic>;
        videoData['videoJson'] = videoJsonData;
      }

      await _db.collection('videos').add(videoData);
      debugPrint(
          'Added video: ${videoData['title']} for topic: ${videoData['topicId']}');
    }

    debugPrint('Sample data initialization complete');
  }

  Future<void> initializeSampleLearningPaths() async {
    // Check if learning paths already exist
    final existingPaths = await _db.collection('learning_paths').get();
    if (existingPaths.docs.isNotEmpty) {
      debugPrint('Learning paths already initialized');
      return;
    }

    debugPrint('Initializing learning paths...');
    final learningPaths = [
      {
        'creatorId': 'teacher1',
        'description': 'Learn fundamental algebra concepts',
        'difficulty': 'beginner',
        'estimatedHours': 0.5,
        'id': 'algebra_basics',
        'prerequisites': [],
        'subject': 'algebra',
        'thumbnail': '',
        'title': 'Algebra Basics',
        'totalVideos': 7,
        'topics': [
          {
            'id': 'variables_expressions',
            'name': 'Variables and Expressions',
            'description': 'Understanding variables and basic expressions',
            'subject': 'algebra',
            'prerequisite': null,
            'order': 1,
          },
          {
            'id': 'equations',
            'name': 'Equations',
            'description': 'Solving basic equations',
            'subject': 'algebra',
            'prerequisite': 'variables_expressions',
            'order': 2,
          },
          {
            'id': 'inequalities',
            'name': 'Inequalities',
            'description': 'Understanding and solving inequalities',
            'subject': 'algebra',
            'prerequisite': 'equations',
            'order': 3,
          }
        ]
      },
      {
        'creatorId': 'teacher1',
        'description': 'Master basic geometric concepts',
        'difficulty': 'beginner',
        'estimatedHours': 0.5,
        'id': 'geometry_fundamentals',
        'prerequisites': ['algebra_basics'],
        'subject': 'geometry',
        'thumbnail': '',
        'title': 'Geometry Fundamentals',
        'totalVideos': 6,
        'topics': [
          {
            'id': 'basic_shapes',
            'name': 'Basic Shapes',
            'description': 'Understanding basic geometric shapes',
            'subject': 'geometry',
            'prerequisite': null,
            'order': 1,
          },
          {
            'id': 'area_perimeter',
            'name': 'Area and Perimeter',
            'description': 'Calculating area and perimeter',
            'subject': 'geometry',
            'prerequisite': 'basic_shapes',
            'order': 2,
          }
        ]
      }
    ];

    debugPrint('Initializing learning paths...');
    for (final path in learningPaths) {
      final topics = List<Map<String, dynamic>>.from(path['topics'] as List);
      path.remove('topics');

      final pathRef = await _db.collection('learning_paths').add(path);
      debugPrint('Created learning path: ${path['title']}');

      for (final topic in topics) {
        final topicId = topic['id'] as String;
        await _db
            .collection('learning_paths')
            .doc(pathRef.id)
            .collection('topics')
            .doc(topicId)
            .set(topic);
        debugPrint(
            'Added topic: ${topic['name']} with ID: $topicId to ${path['title']}');
      }
    }
  }

  Future<void> initializeTopics() async {
    // Check if topics already exist
    final topicsSnapshot = await _db.collection('topics').get();
    if (topicsSnapshot.docs.isNotEmpty) {
      debugPrint('Topics already initialized');
      return;
    }

    debugPrint('Initializing topics...');
    final batch = _db.batch();

    final topics = [
      {
        'id': 'variables_expressions',
        'name': 'Variables and Expressions',
        'description': 'Understanding variables and basic expressions',
        'subject': 'algebra',
        'prerequisite': null,
        'order': 1,
      },
      {
        'id': 'equations',
        'name': 'Equations',
        'description': 'Solving basic equations',
        'subject': 'algebra',
        'prerequisite': 'variables_expressions',
        'order': 2,
      },
      {
        'id': 'inequalities',
        'name': 'Inequalities',
        'description': 'Understanding and solving inequalities',
        'subject': 'algebra',
        'prerequisite': 'equations',
        'order': 3,
      },
      {
        'id': 'basic_shapes',
        'name': 'Basic Shapes',
        'description': 'Understanding basic geometric shapes',
        'subject': 'geometry',
        'prerequisite': null,
        'order': 1,
      },
      {
        'id': 'area_perimeter',
        'name': 'Area and Perimeter',
        'description': 'Calculating area and perimeter',
        'subject': 'geometry',
        'prerequisite': 'basic_shapes',
        'order': 2,
      }
    ];

    for (final topic in topics) {
      final id = topic['id'] as String;
      batch.set(_db.collection('topics').doc(id), topic);
    }

    await batch.commit();
    debugPrint('Topics initialized');
  }

  Future<void> temporaryUpdateLearningPaths() async {
    debugPrint('Starting temporary learning path update...');

    final pathsSnapshot = await _db.collection('learning_paths').get();

    for (final doc in pathsSnapshot.docs) {
      final data = doc.data();
      if (data['title'] == 'Algebra Basics') {
        await doc.reference.update({
          'creatorId': 'teacher1',
          'description': 'Learn fundamental algebra concepts',
          'difficulty': 'beginner',
          'estimatedHours': 0.5,
          'id': 'algebra_basics',
          'prerequisites': [],
          'subject': 'algebra',
          'thumbnail': '',
          'title': 'Algebra Basics',
          'totalVideos': 7
        });
        debugPrint('Updated Algebra Basics path');
      } else if (data['title'] == 'Geometry Fundamentals') {
        await doc.reference.update({
          'creatorId': 'teacher1',
          'description': 'Master basic geometric concepts',
          'difficulty': 'beginner',
          'estimatedHours': 0.5,
          'id': 'geometry_fundamentals',
          'prerequisites': ['algebra_basics'],
          'subject': 'geometry',
          'thumbnail': '',
          'title': 'Geometry Fundamentals',
          'totalVideos': 6
        });
        debugPrint('Updated Geometry Fundamentals path');
      }
    }
    debugPrint('Temporary learning path update complete');
  }

  // Progress Methods
  Future<void> updateProgress(String learningPathId, double progress) {
    return _db.collection('users').doc(userId).update({
      'progress.$learningPathId': progress,
    });
  }

  // Rating Methods
  Future<void> rateVideo(String videoId, bool understood) {
    return _db.collection('videoRatings').add({
      'userId': userId,
      'videoId': videoId,
      'understood': understood,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Comment Methods
  Future<void> toggleCommentLike(String commentId) async {
    if (userId == null) return;

    final likeRef = _db.collection('comment_likes').doc('${userId}_$commentId');
    final commentRef = _db.collection('video_comments').doc(commentId);

    try {
      await _db.runTransaction((transaction) async {
        final likeDoc = await transaction.get(likeRef);
        final commentDoc = await transaction.get(commentRef);

        if (!commentDoc.exists) {
          throw Exception('Comment not found');
        }

        if (!likeDoc.exists) {
          // Add like
          transaction.set(likeRef, {
            'userId': userId,
            'commentId': commentId,
            'timestamp': FieldValue.serverTimestamp(),
          });
          transaction.update(commentRef, {'likes': FieldValue.increment(1)});
        } else {
          // Remove like
          transaction.delete(likeRef);
          transaction.update(commentRef, {'likes': FieldValue.increment(-1)});
        }
      });
    } catch (e) {
      throw Exception('Failed to toggle comment like: $e');
    }
  }

  Stream<bool> isCommentLiked(String commentId) {
    if (userId == null) return Stream.value(false);

    return _db
        .collection('comment_likes')
        .doc('${userId}_$commentId')
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  // Topic Methods
  Stream<List<String>> getUserCompletedTopics() {
    if (userId == null) return Stream.value([]);

    return _db.collection('users').doc(userId).snapshots().map((snapshot) =>
        List<String>.from(snapshot.data()?['completedTopics'] ?? []));
  }

  Future<bool> canAccessTopic(String topicId) async {
    if (userId == null) return false;

    // Get the topic to check prerequisites
    final topicDoc = await _db.collection('topics').doc(topicId).get();
    if (!topicDoc.exists) return false;

    final topic = topicDoc.data() as Map<String, dynamic>;
    final prerequisites = List<String>.from(topic['prerequisites'] ?? []);

    if (prerequisites.isEmpty) return true;

    // Get user's completed topics
    final userDoc = await _db.collection('users').doc(userId).get();
    final completedTopics =
        List<String>.from(userDoc.data()?['completedTopics'] ?? []);

    // Check if all prerequisites are completed
    return prerequisites.every((prereq) => completedTopics.contains(prereq));
  }

  Future<double> getTopicProgress(String topicId) async {
    if (userId == null) return 0.0;

    final userDoc = await _db.collection('users').doc(userId).get();
    final progress =
        (userDoc.data()?['progress'] ?? {}) as Map<String, dynamic>;

    return (progress[topicId] ?? 0.0) as double;
  }

  Future<void> updateTopicProgress(String topicId, double progress) async {
    if (userId == null) return;

    await _db.collection('users').doc(userId).update({
      'progress.$topicId': progress,
    });

    // If progress is 100%, mark topic as completed
    if (progress >= 100) {
      await markTopicAsCompleted(userId!, topicId);
    }
  }

  // Video Likes Methods
  Future<void> toggleVideoLike(String videoId) async {
    if (userId == null) return;

    final likeRef = _db.collection('video_likes').doc('${userId}_$videoId');
    final videoRef = _db.collection('videos').doc(videoId);

    try {
      // First check if the video document exists
      final videoDoc = await videoRef.get();
      if (!videoDoc.exists) {
        throw Exception('Video not found');
      }

      await _db.runTransaction((transaction) async {
        final likeDoc = await transaction.get(likeRef);

        if (!likeDoc.exists) {
          // Add like
          transaction.set(likeRef, {
            'userId': userId,
            'videoId': videoId,
            'timestamp': FieldValue.serverTimestamp(),
          });
          transaction.update(videoRef, {'likes': FieldValue.increment(1)});
        } else {
          // Remove like
          transaction.delete(likeRef);
          transaction.update(videoRef, {'likes': FieldValue.increment(-1)});
        }
      });
    } catch (e) {
      throw Exception('Failed to toggle video like: $e');
    }
  }

  Stream<bool> isVideoLiked(String videoId) {
    if (userId == null) return Stream.value(false);

    return _db
        .collection('video_likes')
        .doc('${userId}_$videoId')
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  Future<void> createVideo(VideoFeed video) async {
    await _db.collection('videos').doc(video.id).set({
      'id': video.id,
      'videoUrl': video.videoUrl,
      'creatorId': video.creatorId,
      'description': video.description,
      'likes': video.likes,
      'shares': video.shares,
      'createdAt': video.createdAt,
      'learningPathId': video.learningPathId,
      'orderInPath': video.orderInPath,
      'title': video.title,
      'topicId': video.topicId,
      'subject': video.subject,
      'skillLevel': video.skillLevel,
      'prerequisites': video.prerequisites,
      'topics': video.topics,
      'estimatedMinutes': video.estimatedMinutes,
      'hasQuiz': video.hasQuiz,
      'progress': video.progress,
      'isCompleted': video.isCompleted,
      'videoJson': video.videoJson,
    });
  }

  Future<void> addCurriculumData(Map<String, dynamic> curriculumData) async {
    try {
      debugPrint('Processing curriculum data...');
      final curriculum = curriculumData['curriculum'] as List<dynamic>;
      final Map<String, List<String>> pathTopics = {}; // Track topics per learning path
      
      // First pass: Create learning paths
      for (final yearData in curriculum) {
        final year = yearData['year'] as String;
        final subject = yearData['subject'] as String;
        final learningPathId = '$year-$subject'.replaceAll(' ', '-').toLowerCase();
        
        pathTopics[learningPathId] = []; // Initialize topic list for this path

        // Create learning path with all required fields
        await _db.collection('learning_paths').doc(learningPathId).set({
          'id': learningPathId,
          'title': '$year $subject',
          'description': yearData['introduction'] as String,
          'creatorId': 'teacher1',
          'difficulty': 'beginner',
          'estimatedHours': 0.5,
          'prerequisites': [],
          'subject': subject.toLowerCase(),
          'thumbnail': '',
          'totalVideos': 0,
        });
        
        debugPrint('Created learning path: $learningPathId');
      }
      
      // Second pass: Create topics with proper relationships
      for (final yearData in curriculum) {
        final year = yearData['year'] as String;
        final subject = yearData['subject'] as String;
        final learningPathId = '$year-$subject'.replaceAll(' ', '-').toLowerCase();
        
        // Add topics (standards) to the main topics collection
        final strands = yearData['strands'] as List<dynamic>;
        int orderIndex = 1; // Start at 1 and increment for each topic

        for (final strandData in strands) {
          final strandName = strandData['strandName'] as String;
          final standards = strandData['standards'] as List<dynamic>;
          
          debugPrint('Processing strand: $strandName with ${standards.length} standards');
          
          for (final standardData in standards) {
            final standardId = standardData['id'] as String;
            final topicId = standardId.toLowerCase();
            // Take first sentence as title (or full text if no period)
            final String description = standardData['description'] as String;
            final topicTitle = description.split('.').first.trim();

            // Track this topic as belonging to this learning path
            pathTopics[learningPathId]?.add(topicId);

            // Create the topic document with proper metadata
            await _db.collection('topics').doc(topicId).set({
              'id': topicId,
              'title': topicTitle,
              'description': description,
              'difficulty': 'beginner',
              'subject': subject.toLowerCase(),
              'prerequisites': [],
              'thumbnail': '',
              'orderIndex': orderIndex, // Use the sequential order
              'learningPathId': learningPathId,
              'strandName': strandName,
              'standardId': standardId,
            });
            
            debugPrint('Created topic: $topicId (order: $orderIndex) in path: $learningPathId');
            orderIndex++; // Increment for next topic
          }
        }
        
        // Update the learning path with topic count
        final topicCount = pathTopics[learningPathId]?.length ?? 0;
        await _db.collection('learning_paths').doc(learningPathId).update({
          'totalTopics': topicCount,
        });
        
        debugPrint('Updated learning path $learningPathId with $topicCount topics');
      }

      debugPrint('Curriculum data added successfully!');
    } catch (e) {
      debugPrint('Error adding curriculum data: $e');
      rethrow;
    }
  }

  Future<void> initializeCurriculumData() async {
    try {
      debugPrint('Starting curriculum data initialization...');
      
      // Load and parse curriculum data from assets
      final jsonString = await rootBundle.loadString('assets/curriculum.json');
      final curriculumData = jsonDecode(jsonString);

      // First add the curriculum structure (learning paths and topics)
      await addCurriculumData(curriculumData);
      debugPrint('Curriculum structure initialized successfully!');
      
      // Then add the sample videos with properly formatted videoJson
      await initializeSampleVideos();
      debugPrint('Sample videos initialized successfully!');
      
      // Wait a moment to ensure all data is committed
      await Future.delayed(Duration(seconds: 1));
      
      debugPrint('Curriculum data initialization complete!');
    } catch (e) {
      debugPrint('Error initializing curriculum data: $e');
      rethrow; // Rethrow to allow the UI to show the error
    }
  }

  Future<void> initializeSampleVideos() async {
    debugPrint('Initializing sample videos...');
    
    // Parse the geometry drawing spec once outside the loop
    final Map<String, dynamic> baseVideoJsonData = 
        jsonDecode(geometryDrawingSpec) as Map<String, dynamic>;
    
    // First, get all learning paths to make sure we assign videos to valid paths
    final pathsSnapshot = await _db.collection('learning_paths').get();
    final Map<String, String> validPaths = {};
    for (final doc in pathsSnapshot.docs) {
      final data = doc.data();
      validPaths[doc.id] = data['title'] as String? ?? doc.id;
    }
    
    // Get topics to ensure we can assign videos to valid topics
    final topicsSnapshot = await _db.collection('topics').get();
    final Map<String, Map<String, dynamic>> validTopics = {};
    for (final doc in topicsSnapshot.docs) {
      validTopics[doc.id] = doc.data();
    }
    
    debugPrint('Found ${validPaths.length} learning paths and ${validTopics.length} topics');
    
    // Process each sample video and ensure consistent structure
    for (final videoData in sampleVideos) {
      try {
        // Create a deep copy to avoid modifying the original sample data
        final processedVideo = Map<String, dynamic>.from(videoData);
        
        // Create unique video JSON for each video to avoid sharing references
        final Map<String, dynamic> videoJsonData = 
            Map<String, dynamic>.from(baseVideoJsonData);
            
        // Customize some aspects of the drawing for each video to make them unique
        if (videoJsonData.containsKey('instructions') && 
            videoJsonData['instructions'].containsKey('speech')) {
          // Customize the speech script based on video title
          videoJsonData['instructions']['speech']['script'] = 
              "In this video about ${processedVideo['title']}, we'll explore " +
              "key concepts related to ${processedVideo['description']}";
        }
        
        // Add video-specific timing if instructions exist
        if (videoJsonData.containsKey('instructions') && 
            videoJsonData['instructions'].containsKey('timing')) {
          // Adjust the timing for this specific video
          final List<dynamic> timing = videoJsonData['instructions']['timing'];
          if (timing.isNotEmpty) {
            // Adjust end times to match estimated minutes
            final double totalMinutes = (processedVideo['estimatedMinutes'] as int).toDouble();
            final int totalSeconds = (totalMinutes * 60).round();
            
            // Create timing stages proportionally
            final int stageCount = timing.length;
            for (int i = 0; i < stageCount; i++) {
              // Calculate proportional end time
              final double proportion = (i + 1) / stageCount;
              final double endTime = totalSeconds * proportion;
              timing[i]['endTime'] = endTime;
              
              // If not the first stage, set startTime to previous endTime
              if (i > 0) {
                timing[i]['startTime'] = timing[i-1]['endTime'];
              }
            }
          }
        }
        
        // Set the properly formatted videoJson
        processedVideo['videoJson'] = videoJsonData;
        
        // Ensure we have a timestamp for createdAt
        processedVideo['createdAt'] = FieldValue.serverTimestamp();
        
        // Make sure video has an ID
        final String videoId = processedVideo['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
        
        // Verify and assign to valid learning path
        String learningPathId = processedVideo['learningPathId'] as String? ?? '';
        if (!validPaths.containsKey(learningPathId)) {
          // Try to find a matching path or assign to first available one
          final String topicId = processedVideo['topicId'] as String? ?? '';
          if (validTopics.containsKey(topicId)) {
            learningPathId = validTopics[topicId]?['learningPathId'] as String? ?? '';
          }
          
          // If still no valid path, use the first one available
          if (!validPaths.containsKey(learningPathId) && validPaths.isNotEmpty) {
            learningPathId = validPaths.keys.first;
          }
          
          processedVideo['learningPathId'] = learningPathId;
          debugPrint('Reassigned video ${processedVideo['title']} to learning path: $learningPathId');
        }
        
        // Verify and assign to valid topic
        String topicId = processedVideo['topicId'] as String? ?? '';
        if (!validTopics.containsKey(topicId)) {
          // Find a topic in the assigned learning path
          final matchingTopics = validTopics.entries
              .where((entry) => entry.value['learningPathId'] == learningPathId)
              .toList();
          
          if (matchingTopics.isNotEmpty) {
            topicId = matchingTopics.first.key;
            processedVideo['topicId'] = topicId;
            debugPrint('Reassigned video ${processedVideo['title']} to topic: $topicId');
          }
        }
        
        // Handle empty topics list
        if (!processedVideo.containsKey('topics') || processedVideo['topics'] == null) {
          processedVideo['topics'] = [topicId];
        }
        
        // Ensure prerequisites is a list
        if (!processedVideo.containsKey('prerequisites') || processedVideo['prerequisites'] == null) {
          processedVideo['prerequisites'] = [];
        }
        
        // Set appropriate order in path
        if (!processedVideo.containsKey('orderInPath') || processedVideo['orderInPath'] == null) {
          // Check existing video count for this topic to determine order
          final existingVideos = await _db.collection('videos')
              .where('topicId', isEqualTo: topicId)
              .count()
              .get();
          
          processedVideo['orderInPath'] = (existingVideos.count ?? 0) + 1;
        }
        
        // Save to Firestore with the ID
        await _db.collection('videos').doc(videoId).set(processedVideo);
        debugPrint('Added video: ${processedVideo['title']} (ID: $videoId)');
        
        // Update the video count in the learning path
        if (validPaths.containsKey(learningPathId)) {
          await _db.collection('learning_paths').doc(learningPathId).update({
            'totalVideos': FieldValue.increment(1)
          });
        }
      } catch (e) {
        debugPrint('Error adding video: $e');
      }
    }
    
    debugPrint('Sample videos initialized successfully!');
  }
}
