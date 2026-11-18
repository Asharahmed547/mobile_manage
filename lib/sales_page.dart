import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';

final _db = Supabase.instance.client;

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;
  String _search = '';
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _db
          .from('sales')
          .select('*, mobiles(brand, model, imei_1, purchase_price)')
          .order('sale_date', ascending: false);
      setState(() => _sales = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  String _date(String iso) {
    final d = DateTime.parse(iso).toLocal();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day}/${d.month}/${d.year}  $h:$m $ap';
  }

  // ---------- SEARCH + FILTER ----------
  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _sales.where((s) {
      final pl = (s['profit_loss'] as num).toDouble();
      if (_filter == 'PROFIT' && pl < 0) return false;
      if (_filter == 'LOSS' && pl >= 0) return false;
      if (q.isEmpty) return true;
      final mob = s['mobiles'] as Map<String, dynamic>?;
      final text = '${mob?['brand'] ?? ''} ${mob?['model'] ?? ''} '
              '${mob?['imei_1'] ?? ''} ${s['customer_name'] ?? ''} '
              '${s['customer_phone'] ?? ''} ${s['payment_mode'] ?? ''}'
          .toLowerCase();
      return text.contains(q);
    }).toList();
  }

  int get _profitCount =>
      _sales.where((s) => (s['profit_loss'] as num) >= 0).length;
  int get _lossCount =>
      _sales.where((s) => (s['profit_loss'] as num) < 0).length;

  // ---------- PICK AN AVAILABLE PHONE ----------
  Future<Map<String, dynamic>?> _pickPhone() async {
    List<Map<String, dynamic>> available;
    try {
      final data = await _db
          .from('mobiles')
          .select()
          .eq('status', 'AVAILABLE')
          .order('created_at', ascending: false);
      available = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      _snack('Error: $e');
      return null;
    }
    if (!mounted) return null;
    if (available.isEmpty) {
      _snack('No phones available in stock.');
      return null;
    }

    String q = '';
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final items = available.where((m) {
            final t =
                '${m['brand']} ${m['model']} ${m['variant'] ?? ''} ${m['color'] ?? ''} ${m['imei_1']} ${m['imei_2'] ?? ''}'
                    .toLowerCase();
            return t.contains(q.trim().toLowerCase());
          }).toList();
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            title: const Text('Select Phone',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 440,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setS(() => q = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search model, color or IMEI',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('No match found'))
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final m = items[i];
                              return ListTile(
                                leading: const Icon(Icons.phone_android,
                                    color: kPrimary),
                                title: Text('${m['brand']} ${m['model']}'),
                                subtitle: Text(
                                    'IMEI ${m['imei_1']}\nCost: ${rs(m['purchase_price'] as num)}'),
                                isThreeLine: true,
                                onTap: () => Navigator.pop(ctx, m),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
            ],
          );
        },
      ),
    );
  }

  // ---------- NEW SALE ----------
  Future<void> _showSaleDialog() async {
    final phone = await _pickPhone();
    if (phone == null || !mounted) return;

    final retail = TextEditingController();
    final discount = TextEditingController();
    final custName = TextEditingController();
    final custPhone = TextEditingController();
    final warranty = TextEditingController(text: '0');
    String payment = 'CASH';
    String? errorText;
    bool saving = false;

    final cost = (phone['purchase_price'] as num).toDouble();

    double finalPrice() =>
        (double.tryParse(retail.text.trim()) ?? 0) -
        (double.tryParse(discount.text.trim()) ?? 0);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final fp = finalPrice();
          final profit = fp - cost;
          final isProfit = profit >= 0;
          final pc =
              isProfit ? const Color(0xFF059669) : const Color(0xFFDC2626);

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
            title: Row(
              children: [
                const Icon(Icons.point_of_sale, color: kPrimary),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('New Sale',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                IconButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (errorText != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(errorText!,
                            style: TextStyle(color: Colors.red.shade800)),
                      ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${phone['brand']} ${phone['model']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text('IMEI ${phone['imei_1']}',
                              style: TextStyle(color: Colors.grey.shade700)),
                          Text('Purchase cost: ${rs(cost)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Price',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: kPrimary)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: retail,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setD(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Retail Price *',
                                prefixText: 'Rs '),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: discount,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setD(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Discount', prefixText: 'Rs '),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: pc.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Final Sale Price: ${rs(fp)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            '${isProfit ? 'Profit' : 'Loss'}: ${rs(profit.abs())}',
                            style: TextStyle(
                                color: pc,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Customer',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: kPrimary)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: custName,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Customer Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: custPhone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                          labelText: 'Customer Phone'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: payment,
                            decoration: const InputDecoration(
                                labelText: 'Payment Mode'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'CASH', child: Text('Cash')),
                              DropdownMenuItem(
                                  value: 'BANK',
                                  child: Text('Bank Transfer')),
                              DropdownMenuItem(
                                  value: 'CARD', child: Text('Card')),
                            ],
                            onChanged: (v) => setD(() => payment = v!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: warranty,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Warranty (months)'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                icon: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text('Complete Sale'),
                onPressed: saving
                    ? null
                    : () async {
                        final r = double.tryParse(retail.text.trim());
                        final d = double.tryParse(discount.text.trim()) ?? 0;
                        if (r == null || r <= 0) {
                          setD(() =>
                              errorText = 'Enter a valid retail price.');
                          return;
                        }
                        if (d < 0 || d > r) {
                          setD(() => errorText =
                              'Discount must be between 0 and the retail price.');
                          return;
                        }
                        setD(() {
                          saving = true;
                          errorText = null;
                        });
                        try {
                          await _db.rpc('sell_mobile', params: {
                            'p_mobile_id': phone['id'],
                            'p_sell_price': r - d,
                            'p_customer_name': custName.text.trim().isEmpty
                                ? null
                                : custName.text.trim(),
                            'p_customer_phone': custPhone.text.trim().isEmpty
                                ? null
                                : custPhone.text.trim(),
                            'p_payment_mode': payment,
                            'p_warranty_months':
                                int.tryParse(warranty.text.trim()) ?? 0,
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          _snack('Sale completed ✅');
                          _load();
                        } on PostgrestException catch (e) {
                          setD(() {
                            saving = false;
                            errorText = e.message;
                          });
                        } catch (e) {
                          setD(() {
                            saving = false;
                            errorText = 'Error: $e';
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summary(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 17)),
              ),
              Text(label,
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final revenue =
        list.fold<double>(0, (s, e) => s + (e['sell_price'] as num).toDouble());
    final profit = list.fold<double>(
        0, (s, e) => s + (e['profit_loss'] as num).toDouble());

    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Sales', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSaleDialog,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New Sale'),
      ),
      body: Column(
        children: [
          // ---- Search bar ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search phone, IMEI, customer or payment',
              ),
            ),
          ),
          // ---- Filter chips ----
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in [
                  ['ALL', 'All', _sales.length],
                  ['PROFIT', 'Profit', _profitCount],
                  ['LOSS', 'Loss', _lossCount],
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${f[1]} (${f[2]})'),
                      selected: _filter == f[0],
                      onSelected: (_) =>
                          setState(() => _filter = f[0] as String),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      children: [
                        Row(
                          children: [
                            _summary('Sales', '${list.length}',
                                Icons.receipt_long, kPrimary),
                            const SizedBox(width: 10),
                            _summary('Revenue', rs(revenue), Icons.payments,
                                const Color(0xFF0891B2)),
                            const SizedBox(width: 10),
                            _summary(
                                profit >= 0 ? 'Net Profit' : 'Net Loss',
                                rs(profit.abs()),
                                profit >= 0
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                profit >= 0
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFDC2626)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (list.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 50),
                            child: Column(
                              children: [
                                Icon(Icons.receipt_long,
                                    size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                    _sales.isEmpty
                                        ? 'No sales yet'
                                        : 'No matching sales',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 16)),
                                Text(
                                    _sales.isEmpty
                                        ? 'Tap "New Sale" to sell your first phone'
                                        : 'Try a different search or filter',
                                    style: TextStyle(
                                        color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                        for (final s in list) ...[
                          _saleCard(s),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _saleCard(Map<String, dynamic> s) {
    final mob = s['mobiles'] as Map<String, dynamic>?;
    final pl = (s['profit_loss'] as num).toDouble();
    final good = pl >= 0;
    final c = good ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final customer = (s['customer_name'] ?? '').toString().isEmpty
        ? 'Walk-in customer'
        : s['customer_name'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: c.withValues(alpha: 0.12),
              child: Icon(good ? Icons.trending_up : Icons.trending_down,
                  color: c),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      mob == null
                          ? 'Phone'
                          : '${mob['brand']} ${mob['model']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text('$customer  •  ${s['payment_mode']}',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13)),
                  Text(_date(s['sale_date']),
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(rs(s['sell_price'] as num),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${good ? '+' : '-'}${rs(pl.abs())}',
                    style: TextStyle(
                        color: c, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}