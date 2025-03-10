final List<Map<String, dynamic>> sampleVideos = [
  // Kindergarten Math Videos - Mathematical Practices
  {
    'id': '19',
    'title': 'Making Sense of Math Problems',
    'topicId': 'k.mp.1',
    'subject': 'mathematics',
    'skillLevel': 'beginner',
    'prerequisites': [],
    'description': 'Learn how to understand and solve simple math problems',
    'learningPathId': 'kindergarten-mathematics',
    'orderInPath': 1,
    'estimatedMinutes': 5,
    'hasQuiz': true,
    'videoUrl': '',
    'videoJson': {},
    'creatorId': 'teacher1',
    'likes': 45,
    'shares': 12,
    'createdAt': DateTime.now().subtract(Duration(days: 19)),
  },
  {
    'id': '20',
    'title': 'Thinking About Numbers',
    'topicId': 'k.mp.2',
    'subject': 'mathematics',
    'skillLevel': 'beginner',
    'prerequisites': [],
    'description': 'Understanding quantities and their relationships',
    'learningPathId': 'kindergarten-mathematics',
    'orderInPath': 2,
    'estimatedMinutes': 6,
    'hasQuiz': true,
    'videoUrl': '',
    'videoJson': {},
    'creatorId': 'teacher1',
    'likes': 38,
    'shares': 8,
    'createdAt': DateTime.now().subtract(Duration(days: 20)),
  },

  // Grade 1 Math Videos - Mathematical Practices
  {
    'id': '21',
    'title': 'Problem Solving Strategies',
    'topicId': '1.mp.1',
    'subject': 'mathematics',
    'skillLevel': 'beginner',
    'prerequisites': ['k.mp.1'],
    'description': 'Building on problem-solving skills from kindergarten',
    'learningPathId': 'grade-1-mathematics',
    'orderInPath': 1,
    'estimatedMinutes': 7,
    'hasQuiz': true,
    'videoUrl': '',
    'videoJson': {},
    'creatorId': 'teacher1',
    'likes': 42,
    'shares': 15,
    'createdAt': DateTime.now().subtract(Duration(days: 21)),
  },
  {
    'id': '22',
    'title': 'Abstract and Quantitative Reasoning',
    'topicId': '1.mp.2',
    'subject': 'mathematics',
    'skillLevel': 'beginner',
    'prerequisites': ['k.mp.2'],
    'description': 'Understanding numbers and their relationships in problems',
    'learningPathId': 'grade-1-mathematics',
    'orderInPath': 2,
    'estimatedMinutes': 6,
    'hasQuiz': true,
    'videoUrl': '',
    'videoJson': {},
    'creatorId': 'teacher1',
    'likes': 40,
    'shares': 10,
    'createdAt': DateTime.now().subtract(Duration(days: 22)),
  }
];
