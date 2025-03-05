import 'dart:convert'; // Needed for JSON parsing
import 'dart:math'; // For min/max functions
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:http/http.dart' as http; // Added for Gemini REST calls
import '../models/quiz_model.dart'; // Added for Quiz and QuizQuestion models

// Simple model to handle chat responses
class ChatResponse {
  final String content;
  final List<dynamic> toolCalls;

  ChatResponse({required this.content, this.toolCalls = const []});

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      content: json['content'] as String? ?? '',
      toolCalls: json['toolCalls'] as List<dynamic>? ?? [],
    );
  }
}

class GptService {
  static final GptService _instance = GptService._internal();
  factory GptService() => _instance;

  late final String _provider;
  late final String _geminiApiKey;
  late final String _geminiEndpoint;

  GptService._internal() {
    // Choose provider based on environment variable; default is 'gemini'
    _provider = dotenv.env['AI_PROVIDER'] ?? 'gemini';
    _initialize();
  }

  void _initialize() {
    if (_provider == 'openai') {
      final apiKey = dotenv.env['OPENAI_API_KEY'];
      if (apiKey == null) {
        throw Exception('OpenAI API key not found in environment variables');
      }

      OpenAI.apiKey = apiKey;
    } else if (_provider == 'gemini') {
      final geminiKey = dotenv.env['GEMINI_API_KEY'];
      if (geminiKey == null) {
        throw Exception('Gemini API key not found in environment variables');
      }
      _geminiApiKey = geminiKey;
      _geminiEndpoint = dotenv.env['GEMINI_ENDPOINT'] ??
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent'; // Gemini API endpoint
    }
  }

  Future<Map<String, dynamic>> _getLayoutDescription(String prompt) async {
    try {
      if (_provider == 'openai') {
        final response = await OpenAI.instance.chat.create(
          model: 'gpt-4o-mini',
          messages: [
            OpenAIChatCompletionChoiceMessageModel(
              role: OpenAIChatMessageRole.system,
              content: [
                OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt),
              ],
            ),
          ],
          temperature: 0.7,
          maxTokens: 500,
        );
        final jsonStr =
            response.choices.first.message.content?.firstOrNull?.text?.trim() ??
                '{}';
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } else if (_provider == 'gemini') {
        final payload = {
          "contents": [
            {
              "parts": [
                {"text": prompt}
              ]
            }
          ]
        };

        final uri = Uri.parse(_geminiEndpoint)
            .replace(queryParameters: {"key": _geminiApiKey});
        final geminiResponse = await http.post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        if (geminiResponse.statusCode != 200) {
          throw Exception(
              'Gemini API call failed with status: ${geminiResponse.statusCode}');
        }

        Map<String, dynamic> respJson = jsonDecode(geminiResponse.body);
        var rawText = respJson['candidates'][0]['content']['parts'][0]['text']
                ?.toString()
                .trim() ??
            '{}';
        rawText =
            rawText.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(rawText) as Map<String, dynamic>;
      } else {
        throw Exception('Unsupported AI provider: $_provider');
      }
    } catch (e) {
      throw Exception('Error generating layout description: $e');
    }
  }

  Future<Map<String, dynamic>> sendPrompt(String topic) async {
    try {
      // First, get the layout description based on the topic
      final layoutPrompt =
          '''You are helping us pre-generate the exact shape arrangement and teaching content for a CustomPainter-based educational video lesson.

Topic: $topic

This topic is part of a K-5 math curriculum. Create content that uses SPECIFIC, CONCRETE math examples - not abstract meta-lessons about learning.

IMPORTANT:
1. DO NOT create videos that teach abstract concepts like "perseverance" or "problem-solving steps"
2. DO create videos that teach actual math with specific numbers, equations, and concrete examples
3. AVOID phrases like "Let's try option A... Now let's try option B" or "Remember to persevere"
4. INSTEAD use real math problems like "If Sarah has 5 apples and gives 2 to John, how many does she have left?"

Your goal is to teach through CONCRETE examples using numbers, shapes, and mathematical operations that are directly applicable.

Return a concise description of the final drawing we want and the teaching script. Include:
1. Specific math concept with NUMBERS and CONCRETE examples (not abstract meta-learning)
2. List of shapes with approximate coordinates, colors, and labeling ideas
3. 2-3 sentence teaching script summary that demonstrates solving an actual math problem

Output as a simple JSON with "layoutDescription" and "teachingFocus" fields only. No additional text or commentary.''';

      final layoutDescription = await _getLayoutDescription(layoutPrompt);

      // Now use the layout description for the main drawing prompt
      final drawingPrompt =
          '''Your topic is ${layoutDescription['layoutDescription']}

CRITICALLY IMPORTANT: Create a lesson that teaches ACTUAL MATH with SPECIFIC NUMBERS and CONCRETE EXAMPLES. 
DO NOT create abstract meta-lessons about "how to solve problems" or "multiple ways to think about math."

For K-5 math students:
1. Use SPECIFIC NUMBERS and CONCRETE EXAMPLES - work through actual math problems 
2. Show step-by-step solving of real math equations or problems with definite answers
3. Use colorful, meaningful visuals that directly relate to the specific math being taught
4. Avoid abstract lessons about perseverance, problem-solving approaches, or thinking strategies

You are an AI that generates perfect JSON output (with no additional text or explanations) to instruct Flutter's CustomPainter on how to draw and label mathematical concepts in a context-aware manner. Follow these rules precisely:
1. JSON-Only Output Your response must be a single, valid JSON object. It must contain no extra text, commentary, or Markdown formatting. Do not wrap it in triple backticks, do not provide any explanation—only the JSON.
2. Context-Aware of a 320×568 Grid
    * Assume a coordinate system sized for an iPhone SE (1st gen) screen, 320 points wide by 568 points high.
    * All coordinates must ensure shapes and labels fit comfortably within this space.
    * Place shapes and labels so they do not overlap each other, unless layering is intentional
    * If multiple shapes exist, they should each occupy unique or well-arranged areas, respecting the shapes that are already drawn. For example, if you draw an angle near x=100,y=300, ensure labels for that angle are placed clearly away from crossing lines or other shapes.
    * Be aware that each handwritten letter/number is about 35px high and 20 px wide. Take this into consideration when calculating vertical and horizontal space.
3. Flutter CustomPainter Instructions Only
    * All drawing commands must be specified as Flutter path operations (e.g., "moveTo(x, y)", "lineTo(x, y)", "quadraticBezierTo(x1, y1, x2, y2)").
    * No SVG or HTML. No extraneous placeholders like <path> or <svg>.
    * The path key for each shape must be a single string containing these commands, separated by spaces (e.g. "moveTo(10, 10) lineTo(50, 10) lineTo(50, 40)").
    * For shapes that should be closed (e.g., polygons), you may include "lineTo(...)" plus "close()", or simply end with a lineTo that returns to the starting point.
4. Timing and Animation Include an array "timing" under "instructions" that lists drawing stages in chronological order. For each stage:
    * "stage": A unique string identifier (e.g., "draw_triangle").
    * "startTime" and "endTime" in seconds, controlling when the shape is drawn.
    * "description": A brief text about what is being drawn or labeled.
    * "easing" (optional): e.g., "easeIn", "easeOut", "linear".
5. Drawing Elements Inside "drawing", include two arrays: "shapes" and "labels".
    * shapes
        * "id": Must match a stage in the "timing".
        * "vertices": List of { "x": _, "y": _ } points (optional but encouraged for clarity).
        * "path": The hand-drawn path instructions. For example: "moveTo(50, 20) lineTo(20, 80) lineTo(80, 80) lineTo(50, 20)", arcTo(centerX, centerY, width, height, startAngle, sweepAngle, forceMoveTo) (centerX, centerY: center point of arc, width, height: dimensions of bounding box, startAngle: start angle in radians (0 = right), sweepAngle: angle to draw (6.28 = full circle), ForceMoveTo: true to prevent connecting line)
        * "style": "stroke" or "fill".
        * "strokeWidth": A reasonable line thickness (e.g., 2–5).
        * "color": A color in hex format (e.g. "#000000").
        * "fadeInRange": [start, end] controlling when the shape fades from transparent to fully visible. Typically matches or is within the shape's drawing time.
    * labels
        * "id": Must match a stage in the "timing" (e.g., "label_rectangle").
        * "text": The text content (for math, LaTeX in \\\$...\\\$ is allowed).
        * "position": { "x":..., "y":... }
        * "color": The label color (hex).
        * "fadeInRange": [start, end] for label fade-in.
        * "handwritten": true makes it write out handwritten chars instead of plaintext. Helpful for learning, but bigger size. (35 x 20, h x w)
    * Context Awareness:
        * Ensure label positions do not overlap with shapes or lines. Place them near the relevant shape but with enough spacing to be visually pleasing.
        * If a shape extends to x=200,y=250, position the label in a clear spot that does not intersect lines or corners.
        * If you have multiple shapes, ensure each shape has enough space in the 320×568 area.
        * If a shape is near the bottom of the screen, do not place the label below 568.
        * Place angle labels near corners but offset so lines do not cross them.
        * Place rectangle labels near edges or corners but offset so it's not overlapped by lines.
6. Speech Under "speech", include:
    * "script": A concise narration explaining the concept.
    * "pacing": { "initialDelay": ..., "betweenStages": ..., "finalDelay": ... }
7. Topic-Specific
    * The final JSON must illustrate a particular topic. For example, "basics of geometry," "pythagorean theorem," "circle theorems," etc.
    * The shapes, labels, and text must be thematically relevant (e.g., lines, angles, polygons for geometry basics).
8. No Additional Text
    * Output only the JSON object described.
    * No preamble, no postscript, no code fences.

You are an AI that outputs a single JSON object with instructions for Flutter's CustomPainter on the topic of: YOUR_TOPIC_HERE

===IMPORTANT REQUIREMENTS===
1) The JSON must have this structure:
{
  "instructions": {
    "timing": [...],
    "drawing": {
      "shapes": [...],
      "labels": [...]
    },
    "speech": {
      "script": "...",
      "pacing": {
        "initialDelay": ...,
        "betweenStages": ...,
        "finalDelay": ...
      }
    }
  }
}

2) Under "timing", produce drawing stages that do NOT overlap and are logically ordered, each with "stage", "startTime", "endTime", "description", and optional "easing".

3) Under "drawing.shapes", each shape has:
   - "id" matching a stage
   - "vertices" (optional)
   - "path" with commands (moveTo, lineTo, etc.)
   - "style" ("stroke" or "fill")
   - "strokeWidth"
   - "color" (hex)
   - "fadeInRange": e.g. [start, end]

4) Under "drawing.labels", each label has:
   - "id" (matching a stage if relevant)
   - "text"
   - "position" { "x":..., "y":... }
   - "color" (hex)
   - "fadeInRange" [start, end]
   - "handwritten" true
   - ***Place label positions so they do not overlap shapes or lines.***

5) Be context-aware of a 320x568 grid:
   - Arrange shapes so they do not overlap unless intended.
   - Place labels near the shape but avoid crossing lines.
   - Don't place anything off-screen (x < 0 or x > 320 or y < 0 or y > 568).
   - Be aware that each letter is about 35px high and 20 px wide. Take this into consideration when calculating vertical and horizontal space.

6) Provide a "speech" object with:
   - "script" explaining a CONCRETE math problem with SPECIFIC NUMBERS:
     * Use a SPECIFIC, REAL math problem with definite numerical answers (not abstract concepts)
     * Include actual NUMBERS, EQUATIONS, or MATHEMATICAL OPERATIONS
     * Show how to solve this specific problem step-by-step
     * Use simple words a K-5 student would understand
     * Be enthusiastic but FOCUS ON THE ACTUAL MATH, not abstract meta-lessons
     * Avoid phrases like "Let's try option A... Now let's try option B"
     * Do not teach about perseverance, multiple approaches, or general problem-solving
   - "pacing" with "initialDelay", "betweenStages", and "finalDelay"

8) No LaTeX or slashes in labels. Use plain text or Unicode symbols for geometry (e.g., ΔABC, ∠A, "Line XY," etc.). Do not produce strings like \\\$\\triangle\\\$ or \\\$\\angle A\\\$.

9) For angle arcs, compute parameters geometrically:
   - Use the vertex as the arc's center point
   - Compute start angle using atan2(y2-y1, x2-x1) where (x1,y1) is the vertex and (x2,y2) is the point on the first ray
   - Compute sweep angle as the signed angle between the two rays forming the angle
   - Choose radius size proportional to the triangle size (typically 20-40 units)
   - Example arcTo format: arcTo(centerX, centerY, radius*2, radius*2, startAngle, sweepAngle, true)

10) Output only the JSON object, with no extra text or explanation.

===END OF REQUIREMENTS===

Now produce the JSON instructions that depict the concept of YOUR_TOPIC_HERE in a hand-drawn style, ensuring each shape is drawn progressively, labeled clearly, and fully visible on the 320x568 grid.''';

      if (_provider == 'openai') {
        final response = await OpenAI.instance.chat.create(
          model: 'gpt-4o-mini',
          messages: [
            OpenAIChatCompletionChoiceMessageModel(
              role: OpenAIChatMessageRole.system,
              content: [
                OpenAIChatCompletionChoiceMessageContentItemModel.text(
                    drawingPrompt),
              ],
            ),
          ],
          temperature: 1,
          maxTokens: 2000,
        );
        final jsonStr =
            response.choices.first.message.content?.firstOrNull?.text?.trim() ??
                '{}';
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      } else if (_provider == 'gemini') {
        final payload = {
          "contents": [
            {
              "parts": [
                {"text": drawingPrompt}
              ]
            }
          ],
          "generationConfig": {"temperature": 1.7, "topP": 0.8, "topK": 40}
        };

        final uri = Uri.parse(_geminiEndpoint)
            .replace(queryParameters: {"key": _geminiApiKey});
        final geminiResponse = await http.post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        if (geminiResponse.statusCode != 200) {
          throw Exception(
              'Gemini API call failed with status: ${geminiResponse.statusCode}');
        }

        Map<String, dynamic> respJson = jsonDecode(geminiResponse.body);
        var rawText = respJson['candidates'][0]['content']['parts'][0]['text']
                ?.toString()
                .trim() ??
            '{}';
        rawText =
            rawText.replaceAll('```json', '').replaceAll('```', '').trim();
        return jsonDecode(rawText) as Map<String, dynamic>;
      } else {
        throw Exception('Unsupported AI provider: $_provider');
      }
    } catch (e) {
      throw Exception('Error generating response: $e');
    }
  }

  Future<Map<String, String>> generateVideoMetadata(
      Map<String, dynamic> videoJson) async {
    try {
      final instructions = videoJson['instructions'];
      final script = instructions['speech']['script'] as String;
      final timingDescriptions = (instructions['timing'] as List)
          .map((t) => t['description'] as String)
          .join('\n');

      final prompt =
          '''Analyze this math lesson content and generate a kid-friendly title and description that focuses on SPECIFIC MATH CONTENT.
The content includes:

VISUAL STEPS:
$timingDescriptions

EXPLANATION:
$script

REQUIREMENTS:
1. Title: Create a fun, specific title that mentions the ACTUAL MATH being taught (max 30 chars)
2. Description: Focus on the SPECIFIC math problem or concept with actual numbers (max 75 chars)
3. Ensure both title and description refer to concrete math operations or numbers
4. Avoid abstract concepts like "multiple approaches" or "perseverance"
5. Make it clear what SPECIFIC math skill students will learn

Format your response as a JSON object with exactly these fields:
{
  "title": "Your Title Here",
  "description": "Your Description Here"
}

Do not include any other text or explanation in your response.''';

      if (_provider == 'openai') {
        final response = await OpenAI.instance.chat.create(
          model: 'gpt-4o-mini',
          messages: [
            OpenAIChatCompletionChoiceMessageModel(
              role: OpenAIChatMessageRole.system,
              content: [
                OpenAIChatCompletionChoiceMessageContentItemModel.text(prompt)
              ],
            ),
          ],
          temperature: 0.7,
          maxTokens: 200,
        );

        final jsonStr =
            response.choices.first.message.content?.firstOrNull?.text?.trim() ??
                '{}';
        final metadata = jsonDecode(jsonStr) as Map<String, dynamic>;
        return {
          'title': metadata['title'] as String? ?? 'Math Lesson',
          'description': metadata['description'] as String? ??
              'Learn an important mathematical concept.',
        };
      } else if (_provider == 'gemini') {
        final payload = {
          "contents": [
            {
              "parts": [
                {"text": prompt}
              ]
            }
          ]
        };

        final uri = Uri.parse(_geminiEndpoint)
            .replace(queryParameters: {"key": _geminiApiKey});
        final geminiResponse = await http.post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        if (geminiResponse.statusCode != 200) {
          throw Exception(
              'Gemini API call failed with status: ${geminiResponse.statusCode}');
        }

        Map<String, dynamic> respJson = jsonDecode(geminiResponse.body);
        var rawText = respJson['candidates'][0]['content']['parts'][0]['text']
                ?.toString()
                .trim() ??
            '{}';
        rawText =
            rawText.replaceAll('```json', '').replaceAll('```', '').trim();

        final metadata = jsonDecode(rawText) as Map<String, dynamic>;
        return {
          'title': metadata['title'] as String? ?? 'Math Lesson',
          'description': metadata['description'] as String? ??
              'Learn an important mathematical concept.',
        };
      } else {
        throw Exception('Unsupported AI provider: $_provider');
      }
    } catch (e) {
      // Return default values if metadata generation fails
      return {
        'title': 'Math Lesson',
        'description': 'Learn an important mathematical concept.',
      };
    }
  }

  Future<Quiz?> generateQuizFromTopics({
    required List<String> topics,
    required DifficultyLevel difficulty,
    int questionCount = 5,
  }) async {
    try {
      // Ensure questionCount is between 2-3
      questionCount = questionCount.clamp(2, 3);

      final prompt = '''Required structure:
{
  "title": "string - quiz title",
  "questions": [
    {
      "question": "string - the question text using simple symbols (>, <, >=, <=, =)",
      "type": "string - one of: multipleChoice, openEnded, wordProblem, mathExpression",
      "difficulty": "${difficulty.name}",
      "topics": ["string"],
      "metadata": {
        "category": "string - math category",
        "subtype": "string - specific type of problem"
      },
      "options": [
        "string - correct answer",
        "string - wrong answer 1",
        "string - wrong answer 2",
        "string - wrong answer 3"
      ],
      "correctAnswer": "string - must match first option exactly",
      "explanation": "string - explanation using simple symbols",
      "commonMistakes": {
        "wrong answer 1": "string - explanation of this mistake",
        "wrong answer 2": "string - explanation of this mistake",
        "wrong answer 3": "string - explanation of this mistake"
      }
    }
  ]
}

VARIETY REQUIREMENTS:
1. Each question MUST be significantly different from others
2. Use different problem structures (e.g., solve for x, word problems, comparisons)
3. Use different numbers and scenarios
4. Mix different subtopics within the main topic
5. Vary the complexity while staying within the specified difficulty level
6. Include at least one word problem if appropriate for the topic
7. Use different formats for presenting similar concepts
8. RANDOMIZATION REQUIREMENTS:
   - Use random numbers appropriate for the skill level of the user
   - Randomly choose from different real-world contexts (sports, cooking, shopping, travel, etc.)
   - Randomly vary question formats (equations, word problems, comparisons)
   - Use different variable names (not just x, try a, b, n, p, etc.)
   - Mix positive and negative numbers
   - Include decimals and fractions randomly
   - Vary the length and complexity of word problems
   - Use different types of mathematical relationships (greater than, equal to, etc.)

Topics to cover: ${topics.join(", ")}
Difficulty Level: ${difficulty.name}
Number of questions: $questionCount

Additional Guidelines:
1. For ${difficulty.name} difficulty:
   - Beginner: Focus on basic concepts, single-step problems, use small whole numbers (-20 to 20)
   - Intermediate: Two-step problems, basic word problems, include decimals and simple fractions
   - Advanced: Multi-step problems, complex applications, include harder fractions and negative numbers
2. Ensure questions build on different aspects of the topic
3. Include real-world applications where possible
4. Make wrong answers plausible but clearly incorrect
5. Provide detailed explanations for both correct and incorrect answers
6. CONTEXTUAL VARIETY:
   - Use different measurement units (meters, feet, liters, etc.)
   - Include various real-world scenarios (shopping, sports, cooking, travel)
   - Mix abstract and concrete problems
   - Vary between story problems and direct calculations
   - Use different ways to present the same concept

Output ONLY the JSON object.''';

      final systemPrompt =
          '''You are a creative math quiz generator. Your goal is to create highly varied, unique questions that test the same concepts in different ways. Never repeat patterns or numbers.

$prompt''';

      String rawResponse;
      if (_provider == 'openai') {
        final response = await OpenAI.instance.chat.create(
          model: 'gpt-4o-mini',
          messages: [
            OpenAIChatCompletionChoiceMessageModel(
              role: OpenAIChatMessageRole.system,
              content: [
                OpenAIChatCompletionChoiceMessageContentItemModel.text(
                    systemPrompt),
              ],
            ),
          ],
          temperature: 1.7, // Increased from 0.7 for more randomness
          maxTokens: 2000,
        );

        rawResponse =
            response.choices.first.message.content?.firstOrNull?.text?.trim() ??
                '{}';
      } else if (_provider == 'gemini') {
        final payload = {
          "contents": [
            {
              "parts": [
                {"text": systemPrompt}
              ]
            }
          ],
          "generationConfig": {"temperature": 1.7, "topP": 0.8, "topK": 40}
        };

        final uri = Uri.parse(_geminiEndpoint)
            .replace(queryParameters: {"key": _geminiApiKey});
        final geminiResponse = await http.post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        );

        if (geminiResponse.statusCode != 200) {
          throw Exception(
              'Gemini API call failed with status: ${geminiResponse.statusCode}');
        }

        Map<String, dynamic> respJson = jsonDecode(geminiResponse.body);
        rawResponse = respJson['candidates'][0]['content']['parts'][0]['text']
                ?.toString()
                .trim() ??
            '{}';
      } else {
        throw Exception('Unsupported AI provider: $_provider');
      }

      // Clean up the response
      rawResponse =
          rawResponse.replaceAll('```json', '').replaceAll('```', '').trim();

      // Log raw response for debugging
      print('[GPTService] Raw quiz response: $rawResponse');

      // Validate JSON structure before parsing
      if (!rawResponse.startsWith('{') || !rawResponse.endsWith('}')) {
        print('[GPTService] Invalid JSON structure');
        print(
            '[GPTService] Response starts with: ${rawResponse.substring(0, min(20, rawResponse.length))}');
        print(
            '[GPTService] Response ends with: ${rawResponse.substring(max(0, rawResponse.length - 20))}');
        return null;
      }

      Map<String, dynamic> quizData;
      try {
        quizData = jsonDecode(rawResponse) as Map<String, dynamic>;
      } catch (e) {
        print('[GPTService] JSON parsing error: $e');
        print('[GPTService] Failed to parse response: $rawResponse');
        return null;
      }

      // Validate required fields
      if (!quizData.containsKey('questions') ||
          !(quizData['questions'] is List)) {
        print('[GPTService] Missing or invalid questions array');
        print('[GPTService] Quiz data structure: ${quizData.keys.join(', ')}');
        return null;
      }

      return _createQuizFromAIResponse(quizData, topics, difficulty);
    } catch (e, stackTrace) {
      print('[GPTService] Error generating quiz: $e');
      print('[GPTService] Stack trace: $stackTrace');
      return null;
    }
  }

  Quiz _createQuizFromAIResponse(
    Map<String, dynamic> aiResponse,
    List<String> topics,
    DifficultyLevel difficulty,
  ) {
    try {
      print('\n[GPTService] DIAGNOSTIC LOGS:');
      print('[GPTService] Requested difficulty: ${difficulty.name}');
      print(
          '[GPTService] Initial questions from AI: ${(aiResponse['questions'] as List).length}');

      // Log all questions and their difficulties before filtering
      print('\n[GPTService] Questions before filtering:');
      (aiResponse['questions'] as List).forEach((q) {
        final questionPreview = q['question']?.toString() ?? '';
        // Safely truncate the question preview
        final previewLength =
            questionPreview.length > 30 ? 30 : questionPreview.length;
        print(
            '[GPTService] Question: "${questionPreview.substring(0, previewLength)}${previewLength == 30 ? '...' : ''}" - Difficulty: ${q['difficulty']}');
      });

      // Filter questions to match exact difficulty and limit count
      var filteredQuestions = (aiResponse['questions'] as List)
          .where((q) {
            try {
              final questionDifficulty =
                  q['difficulty']?.toString().toLowerCase() ?? '';
              final targetDifficulty = difficulty.name.toLowerCase();
              print('\n[GPTService] Difficulty comparison:');
              print('  Question difficulty: "$questionDifficulty"');
              print('  Target difficulty:   "$targetDifficulty"');
              print('  Match: ${questionDifficulty == targetDifficulty}');
              return questionDifficulty == targetDifficulty;
            } catch (e) {
              print('[GPTService] Error comparing difficulties: $e');
              return false;
            }
          })
          .take(3) // Ensure we get at most 3 questions
          .map((q) {
            try {
              if (!q.containsKey('question') || !q.containsKey('type')) {
                print(
                    '[GPTService] Invalid question structure: ${q.keys.join(', ')}');
                throw FormatException('Invalid question format');
              }

              return QuizQuestion(
                id: DateTime.now().millisecondsSinceEpoch.toString() +
                    '_${q['question'].hashCode}',
                question: q['question'],
                type: QuestionType.values.firstWhere(
                  (t) => t.toString().split('.').last == q['type'],
                  orElse: () => QuestionType.multipleChoice,
                ),
                difficulty: difficulty,
                topics: List<String>.from(q['topics'] ?? topics),
                metadata: Map<String, dynamic>.from(q['metadata'] ?? {}),
                options: q['options'] != null
                    ? List<String>.from(q['options'])
                    : null,
                correctAnswer: q['correctAnswer'],
                explanation: q['explanation'],
                commonMistakes: q['commonMistakes'] != null
                    ? Map<String, String>.from(q['commonMistakes'])
                    : null,
              );
            } catch (e) {
              print('[GPTService] Error creating question: $e');
              return null;
            }
          })
          .where((q) => q != null)
          .cast<QuizQuestion>()
          .toList();

      print('\n[GPTService] RESULTS:');
      print(
          '[GPTService] Questions after filtering: ${filteredQuestions.length}');
      print('[GPTService] Final difficulty level: ${difficulty.name}');

      // Ensure we have at least 2 questions
      if (filteredQuestions.length < 2) {
        print('[GPTService] Not enough valid questions generated');
        throw FormatException(
            'Not enough valid questions of the specified difficulty');
      }

      return Quiz(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: aiResponse['title'] ?? 'AI Generated Quiz',
        topics: topics,
        difficulty: difficulty,
        questions: filteredQuestions,
        timeLimit: 300, // 5 minutes for AI generated quizzes
        shuffleQuestions: true,
        metadata: {
          'generatedBy': 'ai',
          'generatedAt': DateTime.now().toIso8601String(),
          'provider': _provider,
        },
      );
    } catch (e, stackTrace) {
      print('[GPTService] Error creating quiz from response: $e');
      print('[GPTService] Stack trace: $stackTrace');
      rethrow;
    }
  }
}

// Custom parser to handle JSON responses
class JsonOutputParser {
  const JsonOutputParser();

  Map<String, dynamic> parse(String text) {
    try {
      // Find the first opening brace to ensure we capture the JSON object
      final startIndex = text.indexOf('{');
      if (startIndex == -1) {
        throw Exception('No JSON object found in response');
      }
      final jsonString = text.substring(startIndex);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to parse JSON: $e');
    }
  }

  String getFormatInstructions() {
    return 'Output must be a valid JSON object.';
  }
}
