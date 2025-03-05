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
          temperature: 0.5, // Lower temperature for more precise spatial planning
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
          ],
          "generationConfig": {"temperature": 0.5, "topP": 0.95, "topK": 10} // Lower temperature for more precise planning
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

  Future<Map<String, dynamic>> sendPrompt(String topic, {String? gradeLevel, String? learningPath}) async {
    try {
      // First, get the layout description based on the topic and grade level
      final layoutPrompt =
          '''You are helping us pre-generate the exact shape arrangement and teaching content for a CustomPainter-based educational video lesson.

Topic: $topic
${gradeLevel != null ? 'Grade Level: $gradeLevel' : ''}
${learningPath != null ? 'Learning Path: $learningPath' : ''}

⚠️ SCREEN SIZE CONSTRAINTS ⚠️
You are designing for a SMALL PHONE SCREEN that is exactly 320 pixels wide × 568 pixels tall.
All content must fit within these bounds with 10px margins (effective area: 10-310 pixels horizontally).
Keep your design SIMPLE - use at most 3-4 shapes and short, concise text that will fit on this small screen.

This topic is part of a K-5 math curriculum. Create content that uses SPECIFIC, CONCRETE math examples - not abstract meta-lessons about learning.

IMPORTANT:
1. DO NOT create videos that teach abstract concepts like "perseverance" or "problem-solving steps"
2. DO create videos that teach actual math with specific numbers, equations, and concrete examples
3. AVOID phrases like "Let's try option A... Now let's try option B" or "Remember to persevere"
4. INSTEAD use real math problems like "If Sarah has 5 apples and gives 2 to John, how many does she have left?"
5. Keep all text SHORT - each character takes 20px width, and anything over 15 characters won't fit properly
6. Avoid complex shapes or diagrams that require detailed labeling

Your goal is to teach through CONCRETE examples using simple numbers, basic shapes, and concise text that will fit on a small phone screen.

DETAILED PLANNING:
1. Choose a specific, age-appropriate math lesson based on the grade level and learning path
2. Decide exactly what to teach and what real-world example will illustrate it best
3. Plan a detailed, step-by-step teaching approach with 4 key sections (one for each screen section)
4. Think about what shapes and visuals will best communicate the concept
5. Plan exact teaching points with specific numbers for each part of the lesson
6. Define the coordinates where each shape and label should appear (ensuring nothing goes beyond x=310)
7. Design a clear progression: introduction → explanation → example → practice/recap

Return a comprehensive teaching and drawing plan as a JSON with these fields:
- "lessonTopic": The specific math concept being taught (age-appropriate for grade level)
- "targetAudience": Age range and grade level this is designed for
- "teachingApproach": Step-by-step explanation of the teaching method
- "keyPoints": 2-3 main points to convey in simple terms
- "visualElements": Array of planned visual elements with approximate coordinates, colors, and sizes
- "teachingScript": Concise script with 4 sections matching the 4 screen sections
- "spatialPlan": Layout guidelines including exact positioning and sizing of elements
- "examples": Specific numerical examples to use with calculated answers
- "conceptualProgression": How to build understanding step by step

Output as a JSON with all these fields structured to provide maximum guidance to the next prompt. No additional text or commentary.''';

      final layoutDescription = await _getLayoutDescription(layoutPrompt);
      final drawingPrompt =
          '''Your topic is ${layoutDescription['lessonTopic'] ?? layoutDescription['layoutDescription']}

TEACHING PLAN:
${layoutDescription['teachingApproach'] ?? ''}

KEY POINTS:
${layoutDescription['keyPoints']?.join('\n') ?? ''}

VISUAL ELEMENTS:
${layoutDescription['visualElements'] != null ? jsonEncode(layoutDescription['visualElements']) : ''}

SPATIAL PLAN:
${layoutDescription['spatialPlan'] ?? ''}

EXAMPLES:
${layoutDescription['examples'] != null ? jsonEncode(layoutDescription['examples']) : ''}

TEACHING SCRIPT (4 sections):
${layoutDescription['teachingScript'] ?? ''}

⚠️ X-COORDINATE BOUNDARY WARNING ⚠️
You are drawing on a phone screen that is EXACTLY 320 pixels wide by 568 pixels tall.
ALL x-coordinates in ALL shapes and labels MUST stay within 10-310 range (with 10px margins on both sides).
ANY point with x < 10 or x > 310 will be CLIPPED and NOT VISIBLE to the user.

HORIZONTAL SPACE CHECK:
- Before creating ANY path or label, check its rightmost x-coordinate
- If a shape or text would extend beyond x=310, you MUST reduce its size or reposition it
- For handwritten text, remember width = (number of characters × 20px)
- ALWAYS set "handwritten": true for ALL labels containing numbers, math symbols, or text
- NEVER use plain text labels - EVERYTHING should be handwritten
- Example: "345 + 678" is 9 characters, requiring 9×20 = 180px horizontal space
- If positioning this at x=200, the right edge would be at x=380, exceeding the boundary
- SOLUTION: Move starting position to x=60 so it ends at x=240 (within bounds)
- ALWAYS calculate: startX + (numberOfChars × 20) ≤ 310
- For MULTI-LINE TEXT: Create separate label objects for each line, positioned at the same x but different y-coordinates
- NEVER try to create multi-line text in a single label - it will NOT render correctly

Organize your drawing in 4 horizontal sections.

CRITICALLY IMPORTANT: Create a lesson that teaches ACTUAL MATH with SPECIFIC NUMBERS and CONCRETE EXAMPLES. 
DO NOT create abstract meta-lessons about "how to solve problems" or "multiple ways to think about math."

For K-5 math students:
1. Use SPECIFIC NUMBERS and CONCRETE EXAMPLES - work through actual math problems 
2. Show step-by-step solving of real math equations or problems with definite answers
3. Use colorful, meaningful visuals that directly relate to the specific math being taught
4. Avoid abstract lessons about perseverance, problem-solving approaches, or thinking strategies

You are an AI that generates perfect JSON output (with no additional text or explanations) to instruct Flutter's CustomPainter on how to draw and label mathematical concepts in a context-aware manner. Follow these rules precisely:
1. JSON-Only Output Your response must be a single, valid JSON object. It must contain no extra text, commentary, or Markdown formatting. Do not wrap it in triple backticks, do not provide any explanation—only the JSON.
2. Context-Aware of a 320×568 Grid with Horizontal Sections
    * Assume a coordinate system sized for an iPhone SE (1st gen) screen, 320 points wide by 568 points high.
    * CRITICAL: ALL x-coordinates must stay within 0-320 range with at least 10px padding from edges (so effective range is 10-310)
    * The screen must be organized into 4 horizontal sections:
      - Section 1: y=0 to y=142 (top quarter)
      - Section 2: y=143 to y=284 (second quarter)
      - Section 3: y=285 to y=426 (third quarter)
      - Section 4: y=427 to y=568 (bottom quarter)
    * You must explicitly assign each shape and label to ONE specific section
    * Each section should contain a complete part of the explanation (not partial concepts)
    * For each element you add, calculate its space requirements:
      - Shapes: Calculate based on the min/max y-values in the path commands
      - Handwritten text: Each character needs 35px×20px space
      - EXAMPLE CALCULATION: The label "5 + 7 = 12" has 9 characters including spaces. 
        Width = 9 chars × 20px = 180px, Height = 35px. This leaves 320-180 = 140px horizontal space remaining.
    * Track the remaining space in each section as you add elements
    * If a section won't fit an element, use the next section instead
    * Do not place more than 2 shapes or 3 labels in a single section
    * Place shapes and labels so they do not overlap each other, unless layering is intentional
    * Each handwritten letter/number is exactly 35px high and 20px wide
    * Always leave at least 15px margins from all screen edges
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
   - "handwritten": true (REQUIRED FOR ALL LABELS - no exceptions)
   - ***IMPORTANT: For ALL text, numbers, math symbols, we use "handwritten": true***
   - ***Position labels so they don't exceed the right edge (x=310) when accounting for full text width***
   - ***VERIFY all label positions with the formula: x_position + (text.length × 20) ≤ 310***

5) Advanced spatial awareness with horizontal sections:
   - Plan your entire layout before generating any paths
   - ALWAYS stay within screen bounds: x must be 10-310 (never outside this range)
   - Organize content following the 4 horizontal sections defined above
   - For handwritten text, calculate exact space needed: total width = (# characters × 20px)
   - For each shape, determine which section it belongs to based on y-coordinates
   - Track used and available space as you build the drawing:
     * Start with 4 empty sections
     * For each element, calculate its height and width
     * Assign it to the appropriate section
     * Update the remaining available space
     * If insufficient space, move to next section
   - Keep related elements (shapes and their labels) in the same section
   - Leave 15px minimum margins from all screen edges
   - Ensure sufficient space between elements (15px min vertical spacing)

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

11) FINAL CHECK BEFORE OUTPUTTING: 
    - Verify ALL x-coordinates in ALL paths and labels are within 10-310 range
    - Check EVERY label to ensure it has "handwritten": true
    - For EACH label, verify: position.x + (text.length × 20) ≤ 310
    - Any coordinate outside 10-310 range will create an invalid drawing that will be CLIPPED
    - Any text without "handwritten": true will NOT display properly
    - TRIPLE CHECK all text positioning to ensure nothing extends beyond the right edge

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
          temperature: 0.5, // Lowered for more precise spatial planning
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
          "generationConfig": {"temperature": 0.5, "topP": 0.9, "topK": 20} // Lower temperature for more precise spatial planning
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
    String? gradeLevel,
    String? learningPath,
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
${gradeLevel != null ? 'Grade Level: $gradeLevel' : ''}
${learningPath != null ? 'Learning Path: $learningPath' : ''}
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
          '''You are a creative, age-appropriate math quiz generator. Your goal is to create highly varied, unique questions that test math concepts in different ways while maintaining educational value. Never repeat patterns or numbers between questions.

IMPORTANT AGE-APPROPRIATE GUIDELINES:
1. If a grade level is specified, tailor questions to be challenging but appropriate for that grade
2. Choose topics that align with the specified learning path (if provided)
3. For kindergarten: Use counting, simple shapes, basic addition with numbers 1-10
4. For 1st grade: Addition/subtraction within 20, telling time to the hour
5. For 2nd grade: Addition/subtraction within 100, simple money problems
6. For 3rd grade: Multiplication/division within 100, fractions with like denominators
7. For 4th grade: Multi-digit arithmetic, area/perimeter, fractions with unlike denominators
8. For 5th grade: Decimals, volume, coordinate planes, operations with fractions

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
          temperature: 1.3, // Adjusted for creativity while maintaining relevance
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
          "generationConfig": {"temperature": 1.3, "topP": 0.8, "topK": 40}
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
