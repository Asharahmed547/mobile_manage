import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';

final _db = Supabase.instance.client;

const String _geminiApiKey = '';



// ======================= PERSISTENT GLOBAL AI SERVICE =======================
class ShopAiService extends ChangeNotifier {
  static final ShopAiService instance = ShopAiService._();
  ShopAiService._() {
    _addWelcome();
  }

  final List messages = [];
  bool thinking = false;
  List? _cachedMobiles;
  List? _cachedSales;

  void _addWelcome() {
    if (messages.isNotEmpty) return;
    messages.add({
      'isUser': false,
      'text':
          'Assalam-o-Alaikum! Main $shopName ka AI Assistant hoon 😊\n\nAap mujh se bilkul dostana andaaz mein Urdu, Roman Urdu ya English mein baat kar sakte hain — chahe dukaan ki sales aur profit poochhna ho, stock check karna ho, ya koi business mashwara lena ho!',
      'time': _nowTime(),
    });
  }

  void clearChat() {
    messages.clear();
    _addWelcome();
    notifyListeners();
  }

  String _nowTime() {
    final d = DateTime.now();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  Future<void> syncShopData() async {
    try {
      final results = await Future.wait([
        _db
            .from('mobiles')
            .select(
                'brand, model, variant, color, condition, imei_1, purchase_price, status, created_at')
            .order('created_at', ascending: false),
        _db
            .from('sales')
            .select(
                'sell_price, profit_loss, customer_name, payment_mode, sale_date, mobiles(brand, model, variant, imei_1, purchase_price)')
            .order('sale_date', ascending: false),
      ]);
      _cachedMobiles = results[0];
      _cachedSales = results[1];
    } catch (_) {}
  }

  Future<void> sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || thinking) return;

    messages.add({
      'isUser': true,
      'text': text,
      'time': _nowTime(),
    });
    thinking = true;
    notifyListeners();

    try {
      final reply = await _askRealGemini(text);
      messages.add({
        'isUser': false,
        'text': reply,
        'time': _nowTime(),
      });
    } catch (e) {
      messages.add({
        'isUser': false,
        'text':
            'Maaf kijiyega, abhi Gemini se rabta nahi ho saka ($e). Ek baar phir try karein!',
        'time': _nowTime(),
      });
    } finally {
      thinking = false;
      notifyListeners();
    }
  }

  Future<String> _askRealGemini(String userQuestion) async {
    await syncShopData();

    final mobilesData = _cachedMobiles ?? [];
    final salesData = _cachedSales ?? [];
    final now = DateTime.now().toIso8601String();

    final recentChat = messages
        .skip(messages.length > 9 ? messages.length - 9 : 1)
        .map((m) =>
            '${(m['isUser'] as bool) ? "Shopkeeper" : "Assistant"}: ${m['text']}')
        .join('\n');

    final prompt = '''
You are Gemini, a warm, intelligent, human-like AI Assistant and Business Partner for "$shopName" (a mobile phone shop in Pakistan, currency is Rs).
Current Local Date & Time: $now

LIVE SHOP DATABASE (Use this ONLY when the user asks about inventory, mobiles, sales, revenue, profit, loss, customers, or business performance):
- INVENTORY (mobiles): ${jsonEncode(mobilesData)}
- SALES HISTORY (sales): ${jsonEncode(salesData)}

IMPORTANT PERSONALITY & CONVERSATION RULES:
1. Talk completely naturally like Gemini — friendly, helpful, polite, and conversational. NEVER output robotic database dumps or unrequested reports!
2. If the user just greets you, asks "kya tum Urdu mein baat kar sakte ho?", or chats casually, reply naturally to their message without dumping sales reports unless they ask for them.
3. Always match the user's language (Roman Urdu, Urdu script, or English).
4. When they DO ask about shop numbers (today's profit, weekly sales, available phones, best model, etc.), calculate exact numbers from the live JSON data above and explain them clearly in a friendly conversational tone (e.g., "Aaj aapki dukaan par 1 mobile sale huwa hai jis se Rs 50,000 ka net profit huwa!").
5. Format currency nicely like "Rs 50,000".

RECENT CONVERSATION:
$recentChat

Reply naturally as Assistant to the latest message from Shopkeeper:
''';

    // Sirf real text models discover karein (TTS, Audio, Image, Vision, Embedding excluded)
    final List modelsToTry = ['gemini-3.8-flash'];
    try {
      final listUri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$_geminiApiKey',
      );
      final listRes = await http.get(listUri, headers: {
        'x-goog-api-key': _geminiApiKey,
      }).timeout(const Duration(seconds: 5));

      if (listRes.statusCode == 200) {
        final rawModels =
            (jsonDecode(listRes.body)['models'] as List?) ?? [];
        for (final m in rawModels) {
          final methods = (m['supportedGenerationMethods'] as List?) ?? [];
          final name = m['name']?.toString().toLowerCase() ?? '';
          if (methods.contains('generateContent') &&
              name.startsWith('models/gemini') &&
              !name.contains('tts') &&
              !name.contains('audio') &&
              !name.contains('image') &&
              !name.contains('embedding') &&
              !name.contains('vision') &&
              !name.contains('robotics') &&
              !name.contains('computer')) {
            final shortName =
                m['name'].toString().replaceFirst('models/', '');
            if (!modelsToTry.contains(shortName)) {
              modelsToTry.add(shortName);
            }
          }
        }
      }
    } catch (_) {}

    String lastError = 'Server busy';

    for (final model in modelsToTry.take(5)) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final uri = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_geminiApiKey',
          );

          final response = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'x-goog-api-key': _geminiApiKey,
                },
                body: jsonEncode({
                  'contents': [
                    {
                      'parts': [
                        {'text': prompt}
                      ]
                    }
                  ],
                  'generationConfig': {
                    'temperature': 0.7,
                    'maxOutputTokens': 700,
                  }
                }),
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);
            final candidates = decoded['candidates'] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final parts = candidates[0]['content']?['parts'] as List?;
              final answer = parts != null && parts.isNotEmpty
                  ? parts[0]['text']?.toString().trim()
                  : null;
              if (answer != null && answer.isNotEmpty) {
                return answer;
              }
            }
          } else if (response.statusCode == 503 || response.statusCode == 429) {
            lastError = 'Gemini servers busy (503)';
            await Future.delayed(const Duration(milliseconds: 900));
            continue;
          } else {
            final err = jsonDecode(response.body);
            lastError =
                err['error']?['message'] ?? 'HTTP ${response.statusCode}';
            break;
          }
        } catch (e) {
          lastError = e.toString();
          break;
        }
      }
    }

    throw Exception(lastError);
  }
}

// ======================= AI ASSISTANT UI PAGE =======================
class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _ai = ShopAiService.instance;

  final List _suggestions = [
    'Assalam-o-Alaikum, Urdu mein baat kar sakte ho?',
    'Aaj kitni sales aur profit huwa?',
    'What was our weekly profit?',
    'Konsa mobile stock mein available hai?',
    'Shop ki sale barhane ka koi mashwara do',
  ];

  @override
  void initState() {
    super.initState();
    _ai.addListener(_onAiUpdate);
    _ai.syncShopData();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _ai.removeListener(_onAiUpdate);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onAiUpdate() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send([String? preset]) {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _ai.thinking) return;
    if (preset == null) _controller.clear();
    _ai.sendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    final messages = _ai.messages;
    final thinking = _ai.thinking;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.smart_toy, color: Color(0xFF7C3AED)),
            SizedBox(width: 8),
            Text('AI Assistant',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New Chat',
            onPressed: thinking ? null : _ai.clearChat,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ActionChip(
                label: Text(_suggestions[i],
                    style: const TextStyle(fontSize: 12)),
                onPressed: () => _send(_suggestions[i]),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: messages.length + (thinking ? 1 : 0),
              itemBuilder: (context, i) {
                if (thinking && i == messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Thinking...'),
                        ],
                      ),
                    ),
                  );
                }

                final msg = messages[i];
                final isUser = msg['isUser'] as bool;

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: isUser ? kGradient : null,
                      color: isUser ? null : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      border: isUser
                          ? null
                          : Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          msg['text'],
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 14.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg['time'],
                          style: TextStyle(
                            color: isUser
                                ? Colors.white70
                                : Colors.grey.shade500,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask anything about your shop...',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: thinking ? null : () => _send(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(52, 50),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}