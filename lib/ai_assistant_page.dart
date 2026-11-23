import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';

final _db = Supabase.instance.client;

// Keys build time par --dart-define se aati hain:
// flutter run --dart-define=GEMINI_API_KEY=xxx --dart-define=GROK_API_KEY=yyy
// NOTE: Production mein keys Supabase Edge Function mein rakhein, app mein nahi.
const String _geminiApiKey =
    String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
const String _grokApiKey =
    String.fromEnvironment('GROK_API_KEY', defaultValue: '');

// ---- Model names (ai.google.dev/gemini-api/docs/models se check kar lein) ----
// Curl test mein jo models 200 diye woh pehle rakhe hain. Ek fail ho (401/404/429/503
// ya timeout) to code khud agla model try karta hai.
const List<String> _geminiModels = [
  'gemini-3.5-flash-lite',
  'gemini-3.5-flash',
  'gemini-3.1-flash-lite',
  'gemini-flash-lite-latest',
  'gemini-flash-latest',
  'gemini-3.8-flash', // abhi kabhi kabhi 503 (busy) deta hai, is liye aakhir mein
];
// Fallback. xAI docs (docs.x.ai/models) ke mutabiq current model grok-4.7 hai.
// Agar 404 aaye to console.x.ai/team/default/models se exact ID copy karein.
const String _grokModel = 'grok-4.7';

const Duration _aiTimeout = Duration(seconds: 15);
const Duration _grokTimeout = Duration(seconds: 25); // reasoning model slow ho sakta hai
const Duration _dataTtl = Duration(seconds: 15);

// ======================= HELPERS =======================
double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

String _mobileName(dynamic m) {
  Map? mm;
  if (m is Map) {
    mm = m;
  } else if (m is List && m.isNotEmpty && m.first is Map) {
    mm = m.first as Map;
  }
  if (mm == null) return 'Unknown';
  final name = [mm['brand'], mm['model'], mm['variant']]
      .where((e) => e != null && '$e'.trim().isNotEmpty)
      .join(' ');
  return name.isEmpty ? 'Unknown' : name;
}

String _rs(double v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${neg ? '-' : ''}Rs $buf';
}

class _Sale {
  final DateTime? date;
  final double price;
  final double profit;
  final String payment;
  final String mobile;
  _Sale(this.date, this.price, this.profit, this.payment, this.mobile);
}

// ======================= PERSISTENT GLOBAL AI SERVICE =======================
class ShopAiService extends ChangeNotifier {
  static final ShopAiService instance = ShopAiService._();
  ShopAiService._() {
    _addWelcome();
  }

  final List<Map<String, dynamic>> messages = [];
  bool thinking = false;

  List<Map<String, dynamic>> _mobiles = [];
  List<_Sale> _sales = [];
  List<Map<String, dynamic>> _saleRows = []; // poori raw sales rows
  DateTime? _lastSync;
  Future<void>? _syncing;
  String _lastError = ''; // debugging: chat mein asli error dikhane ke liye

  void _addWelcome() {
    if (messages.isNotEmpty) return;
    messages.add({
      'isUser': false,
      'text':
          'Assalam-o-Alaikum! Main $shopName ka AI Assistant hoon 😊\n\nAap mujh se Urdu, Roman Urdu ya English mein baat kar sakte hain — sales aur profit poochhna ho, stock check karna ho, ya koi business mashwara lena ho!',
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

  // ---------- DATA ----------
  // Sirf zaroori columns (IMEI aur customer name nahi), aur 15 sec cache.
  Future<void> syncShopData({bool force = false}) {
    final fresh = _lastSync != null &&
        DateTime.now().difference(_lastSync!) < _dataTtl;
    if (!force && fresh) return Future.value();
    return _syncing ??= _doSync().whenComplete(() => _syncing = null);
  }

  Future<void> _doSync() async {
    try {
      final results = await Future.wait([
        _db
            .from('mobiles')
            .select('*')
            .order('created_at', ascending: false)
            .limit(5000),
        _db
            .from('sales')
            .select('*, mobiles(*)')
            .order('sale_date', ascending: false)
            .limit(5000),
      ]);

      _saleRows = (results[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      _mobiles = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      _sales = (results[1] as List).map((e) {
        final r = e as Map;
        final d = DateTime.tryParse('${r['sale_date'] ?? ''}')?.toLocal();
        return _Sale(
          d,
          _num(r['sell_price']),
          _num(r['profit_loss']),
          '${r['payment_mode'] ?? ''}',
          _mobileName(r['mobiles']),
        );
      }).toList();

      _lastSync = DateTime.now();
      debugPrint(
          '[AI][Data] synced: mobiles=${_mobiles.length}, sales=${_sales.length}');
    } catch (e) {
      debugPrint('[AI][Data] SYNC ERROR: $e');
      // purana cache use hota rahega
    }
  }

  // ---------- SUMMARY (calculation Dart mein, AI mein nahi) ----------
  Map<String, dynamic> _agg(DateTime from, [DateTime? to]) {
    int count = 0;
    double revenue = 0, profit = 0;
    for (final s in _sales) {
      final d = s.date;
      if (d == null || d.isBefore(from)) continue;
      if (to != null && !d.isBefore(to)) continue;
      count++;
      revenue += s.price;
      profit += s.profit;
    }
    return {
      'mobiles_sold': count,
      'revenue': _rs(revenue),
      'profit': _rs(profit),
    };
  }

  List<Map<String, dynamic>> _topModels(DateTime? from, {int n = 5}) {
    final counts = <String, int>{};
    final profits = <String, double>{};
    for (final s in _sales) {
      if (from != null) {
        final d = s.date;
        if (d == null || d.isBefore(from)) continue;
      }
      counts[s.mobile] = (counts[s.mobile] ?? 0) + 1;
      profits[s.mobile] = (profits[s.mobile] ?? 0) + s.profit;
    }
    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return keys
        .take(n)
        .map((k) => {
              'mobile': k,
              'sold': counts[k],
              'profit': _rs(profits[k] ?? 0),
            })
        .toList();
  }

  Map<String, dynamic> _buildSummary() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: now.weekday - 1));
    final last7 = today.subtract(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);

    // Stock
    final stockGroups = <String, int>{};
    final statusCounts = <String, int>{};
    int inStock = 0;
    double stockValue = 0;
    for (final m in _mobiles) {
      final status = '${m['status'] ?? ''}'.toLowerCase().trim();
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      if (status == 'sold') continue;
      inStock++;
      stockValue += _num(m['purchase_price']);
      final key = _mobileName(m);
      stockGroups[key] = (stockGroups[key] ?? 0) + 1;
    }
    final stockKeys = stockGroups.keys.toList()
      ..sort((a, b) => stockGroups[b]!.compareTo(stockGroups[a]!));

    // Payment modes (is mahine)
    final payments = <String, double>{};
    for (final s in _sales) {
      final d = s.date;
      if (d == null || d.isBefore(monthStart)) continue;
      final p = s.payment.isEmpty ? 'unknown' : s.payment;
      payments[p] = (payments[p] ?? 0) + s.price;
    }

    // Recent 8 sales
    final recent = _sales.take(8).map((s) => {
          'mobile': s.mobile,
          'price': _rs(s.price),
          'profit': _rs(s.profit),
          'date': s.date?.toIso8601String().substring(0, 10),
        });

    return {
      'today': _agg(today),
      'yesterday': _agg(yesterday, today),
      'last_7_days': _agg(last7),
      'this_week_since_monday': _agg(weekStart),
      'this_month': _agg(monthStart),
      'last_month': _agg(lastMonthStart, monthStart),
      'all_time': _agg(DateTime(2000)),
      'top_sellers_this_month': _topModels(monthStart),
      'top_sellers_all_time': _topModels(null),
      'payment_totals_this_month':
          payments.map((k, v) => MapEntry(k, _rs(v))),
      'stock': {
        'units_in_stock': inStock,
        'stock_value_at_purchase_price': _rs(stockValue),
        'status_counts': statusCounts,
        'models_in_stock': stockKeys
            .take(40)
            .map((k) => {'mobile': k, 'units': stockGroups[k]})
            .toList(),
      },
      'recent_sales': recent.toList(),
    };
  }

  // ---------- POORA DATA (compact table, tokens bachane ke liye) ----------
  // Prompt mein sirf latest itni rows jati hain. Zyada karein to AI thora slow hoga.
  static const int _maxRowsInPrompt = 5000;
  static const Set<String> _skipKeys = {
    'id',
    'user_id',
    'owner_id',
    'created_by',
    'updated_at',
  };

  Map<String, String> _flat(Map row, [String prefix = '']) {
    final out = <String, String>{};
    row.forEach((k, v) {
      final name = '$k';
      final key = '$prefix$name';
      if (v == null) return;
      if (v is Map) {
        out.addAll(_flat(v, '${key}_'));
        return;
      }
      if (v is List) {
        if (v.isNotEmpty && v.first is Map) {
          out.addAll(_flat(v.first as Map, '${key}_'));
        }
        return;
      }
      if (_skipKeys.contains(name) || name.endsWith('_id')) return;
      var s = '$v'.trim();
      if (s.isEmpty) return;
      if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) {
        s = s.substring(0, 16).replaceFirst('T', ' ');
      }
      out[key] = s.length > 40 ? s.substring(0, 40) : s;
    });
    return out;
  }

  String _toTable(List<Map<String, dynamic>> rows) {
    final flat = rows.take(_maxRowsInPrompt).map((r) => _flat(r)).toList();
    if (flat.isEmpty) return '(no rows)';
    final cols = <String>[];
    for (final r in flat) {
      for (final k in r.keys) {
        if (!cols.contains(k)) cols.add(k);
      }
    }
    final b = StringBuffer()..writeln(cols.join('|'));
    for (final r in flat) {
      b.writeln(cols
          .map((c) => (r[c] ?? '').replaceAll('|', '/').replaceAll('\n', ' '))
          .join('|'));
    }
    return b.toString();
  }

  // ---------- CHAT ----------
  Future<void> sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || thinking) return;

    messages.add({'isUser': true, 'text': text, 'time': _nowTime()});
    thinking = true;
    notifyListeners();

    try {
      final reply = await _askAiWithFallback(text);
      messages.add({'isUser': false, 'text': reply, 'time': _nowTime()});
    } catch (_) {
      messages.add({
        'isUser': false,
        'text':
            'Maaf kijiyega, abhi AI service se rabta nahi ho saka. Thori der baad dobara try karein.\n\n[DEBUG]\n${_lastError.isEmpty ? "koi detail nahi" : _lastError}',
        'time': _nowTime(),
      });
    } finally {
      thinking = false;
      notifyListeners();
    }
  }

  Future<String> _askAiWithFallback(String question) async {
    _lastError = '';
    await syncShopData();

    final summary = jsonEncode(_buildSummary());

    // Aakhri 6 messages (welcome message skip, latest question alag se jata hai)
    final history = messages.length > 1
        ? messages.sublist(1, messages.length - 1)
        : <Map<String, dynamic>>[];
    final recentChat = history
        .skip(history.length > 6 ? history.length - 6 : 0)
        .map((m) {
      final t = (m['text'] as String);
      final short = t.length > 300 ? '${t.substring(0, 300)}...' : t;
      return '${(m['isUser'] as bool) ? "Shopkeeper" : "Assistant"}: $short';
    }).join('\n');

    final system = '''
You are a friendly AI business assistant for "$shopName", a mobile phone shop in Pakistan. Currency is Rs.
Rules:
1. Reply in the same language the shopkeeper uses (Roman Urdu, Urdu script or English). Keep it short, natural and friendly.
2. Use ONLY the data given below, never guess. Totals (sales, profit, counts) are in SHOP SUMMARY and already calculated, so do not recalculate them. For specific details (which mobile, IMEI, customer, purchase price, supplier, dates, colour, condition) look in the MOBILES and SALES tables. Both tables are newest first, and in MOBILES the created_at column is when the mobile was purchased / added, so the first row is the latest purchased mobile. Answer the question fully and directly with the real details. Only say something is not available if that column really does not exist in the tables, or if the question is about rows older than the ones shown.
3. If the user just chats or greets, reply naturally without dumping reports.
4. Never output raw JSON. Format money like "Rs 50,000".
''';

    final userContent = '''
Current date & time: ${DateTime.now().toIso8601String()}

SHOP SUMMARY (already calculated, trusted):
$summary

MOBILES TABLE (newest first; showing ${_mobiles.length > _maxRowsInPrompt ? _maxRowsInPrompt : _mobiles.length} of ${_mobiles.length} rows):
${_toTable(_mobiles)}

SALES TABLE (newest first; showing ${_saleRows.length > _maxRowsInPrompt ? _maxRowsInPrompt : _saleRows.length} of ${_saleRows.length} rows):
${_toTable(_saleRows)}

RECENT CHAT:
${recentChat.isEmpty ? '(none)' : recentChat}

Shopkeeper's latest message:
$question
''';

    final geminiKey = _geminiApiKey;
    final grokKey = _grokApiKey;

    debugPrint(
        '[AI] keys: gemini=${geminiKey.isNotEmpty ? "set" : "MISSING"}, grok=${grokKey.isNotEmpty ? "set" : "MISSING"}');

    if (geminiKey.isEmpty) {
      _lastError += 'GEMINI_API_KEY build mein nahi di gayi (khali hai)\n';
    }
    if (grokKey.isEmpty) {
      _lastError += 'GROK_API_KEY build mein nahi di gayi (khali hai)\n';
    }

    // 1. Gemini
    if (geminiKey.isNotEmpty) {
      final r = await _askGemini(system, userContent, geminiKey);
      if (r != null) return r;
    }

    // 2. Grok fallback
    if (grokKey.isNotEmpty) {
      final r = await _askGrok(system, userContent, grokKey);
      if (r != null) return r;
    }

    throw Exception('AI unavailable');
  }

  // ---------- GEMINI ----------
  Future<String?> _askGemini(
      String system, String userContent, String apiKey) async {
    for (final model in _geminiModels) {
      try {
        final sw = Stopwatch()..start();
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
        );
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': apiKey,
              },
              body: jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {'text': system}
                  ]
                },
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      {'text': userContent}
                    ]
                  }
                ],
                'generationConfig': {'maxOutputTokens': 1024},
              }),
            )
            .timeout(_aiTimeout);

        debugPrint(
            '[AI][Gemini][$model] status=${response.statusCode} time=${sw.elapsedMilliseconds}ms');
        if (response.statusCode != 200) {
          final b = response.body;
          debugPrint(
              '[AI][Gemini][$model] ERROR: ${b.length > 400 ? b.substring(0, 400) : b}');
          _lastError +=
              'Gemini $model → ${response.statusCode}: ${b.length > 250 ? b.substring(0, 250) : b}\n';
        }

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          _lastError +=
              'Gemini $model → 200 but no text: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}\n';
          final candidates = decoded['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null) {
              final answer = parts
                  .map((p) => p['text']?.toString() ?? '')
                  .join()
                  .trim();
              if (answer.isNotEmpty) return answer;
            }
          }
        }
      } catch (e) {
        debugPrint('[AI][Gemini][$model] EXCEPTION: $e');
        _lastError += 'Gemini $model → exception: $e\n';
        // agla model try hoga
      }
    }
    return null;
  }

  // ---------- GROK (xAI) ----------
  Future<String?> _askGrok(
      String system, String userContent, String apiKey) async {
    try {
      final sw = Stopwatch()..start();
      final response = await http
          .post(
            Uri.parse('https://api.x.ai/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': _grokModel,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': userContent},
              ],
              'temperature': 0.5,
              'max_tokens': 1024,
            }),
          )
          .timeout(_grokTimeout);

      debugPrint(
          '[AI][Grok][$_grokModel] status=${response.statusCode} time=${sw.elapsedMilliseconds}ms');
      if (response.statusCode != 200) {
        final b = response.body;
        debugPrint(
            '[AI][Grok] ERROR: ${b.length > 400 ? b.substring(0, 400) : b}');
        _lastError +=
            'Grok $_grokModel → ${response.statusCode}: ${b.length > 250 ? b.substring(0, 250) : b}\n';
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final choices = decoded['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final answer = choices[0]['message']?['content']?.toString().trim();
          if (answer != null && answer.isNotEmpty) return answer;
        }
      }
    } catch (e) {
      debugPrint('[AI][Grok] EXCEPTION: $e');
      _lastError += 'Grok $_grokModel → exception: $e\n';
    }
    return null;
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

  final List<String> _suggestions = [
    'Aaj kitni sales aur profit huwa?',
    'What was our weekly profit?',
    'Is mahine sab se zyada konsa mobile bika?',
    'Konsa mobile stock mein available hai?',
    'Shop ki sale barhane ka koi mashwara do',
  ];

  @override
  void initState() {
    super.initState();
    _ai.addListener(_onAiUpdate);
    _ai.syncShopData(force: true);
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
              separatorBuilder: (_, __) => const SizedBox(width: 8),
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
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
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
                          msg['text'] as String,
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 14.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg['time'] as String,
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