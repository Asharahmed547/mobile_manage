import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';

final _db = Supabase.instance.client;

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List _mobiles = [];
  bool _loading = true;
  String _search = '';
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadMobiles();
  }

  Future<void> _loadMobiles() async {
    setState(() => _loading = true);
    try {
      final data = await _db
          .from('mobiles')
          .select()
          .order('created_at', ascending: false);
      setState(() => _mobiles = data);
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

  List get _filtered {
    final q = _search.trim().toLowerCase();
    return _mobiles.where((m) {
      if (_filter != 'ALL' && m['status'] != _filter) return false;
      if (q.isEmpty) return true;
      final text =
          '${m['brand']} ${m['model']} ${m['variant'] ?? ''} ${m['color'] ?? ''} ${m['imei_1']} ${m['imei_2'] ?? ''}'
              .toLowerCase();
      return text.contains(q);
    }).toList();
  }

  int _count(String status) =>
      _mobiles.where((m) => m['status'] == status).length;

  Color _statusColor(String s) {
    switch (s) {
      case 'AVAILABLE':
        return const Color(0xFF059669);
      case 'SOLD':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFFEA580C);
    }
  }

  // ---------------- DELETE PHONE ----------------
  Future<void> _confirmAndDelete(Map m, BuildContext sheetCtx) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
            SizedBox(width: 8),
            Text('Delete Phone?',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Kya aap waqai "${m['brand']} ${m['model']}" (IMEI: ${m['imei_1']}) ko permanently delete karna chahte hain?\n\nIs se is mobile ka purchase/sale record bhi khatam ho jayega.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final id = m['id'];
      // Pehle linked records delete karein taake foreign key error na aaye
      await _db.from('sales').delete().eq('mobile_id', id);
      await _db.from('purchases').delete().eq('mobile_id', id);
      await _db.from('mobiles').delete().eq('id', id);

      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      _snack('Phone deleted successfully 🗑️');
      _loadMobiles();
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  // ---------------- ADD PHONE ----------------
  Future<void> _showAddDialog() async {
    final brand = TextEditingController();
    final model = TextEditingController();
    final variant = TextEditingController();
    final color = TextEditingController();
    final imei1 = TextEditingController();
    final imei2 = TextEditingController();
    final price = TextEditingController();
    final supplier = TextEditingController();
    final supplierContact = TextEditingController();
    String condition = 'NEW';
    String? errorText;
    bool saving = false;

    String? nullIfEmpty(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    Widget gap() => const SizedBox(height: 12);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
          title: Row(
            children: [
              const Icon(Icons.add_circle, color: kPrimary),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('Add New Phone',
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
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(errorText!,
                                  style:
                                      TextStyle(color: Colors.red.shade800))),
                        ],
                      ),
                    ),
                  const Text('Phone Details',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: kPrimary)),
                  gap(),
                  TextField(
                    controller: brand,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Brand *'),
                  ),
                  gap(),
                  TextField(
                    controller: model,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Model *'),
                  ),
                  gap(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: variant,
                          decoration: const InputDecoration(
                              labelText: 'Storage / RAM'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: color,
                          textCapitalization: TextCapitalization.words,
                          decoration:
                              const InputDecoration(labelText: 'Color'),
                        ),
                      ),
                    ],
                  ),
                  gap(),
                  DropdownButtonFormField<String>(
                    initialValue: condition,
                    decoration: const InputDecoration(labelText: 'Condition'),
                    items: const [
                      DropdownMenuItem(
                          value: 'NEW', child: Text('New (Box Packed)')),
                      DropdownMenuItem(
                          value: 'USED', child: Text('Used / Pre-Owned')),
                    ],
                    onChanged: (v) => setD(() => condition = v!),
                  ),
                  const SizedBox(height: 20),
                  const Text('IMEI & Price',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: kPrimary)),
                  gap(),
                  TextField(
                    controller: imei1,
                    keyboardType: TextInputType.number,
                    maxLength: 15,
                    decoration: const InputDecoration(
                        labelText: 'IMEI 1 * (15 digits)'),
                  ),
                  TextField(
                    controller: imei2,
                    keyboardType: TextInputType.number,
                    maxLength: 15,
                    decoration: const InputDecoration(
                        labelText: 'IMEI 2 (optional)'),
                  ),
                  gap(),
                  TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Purchase Price *', prefixText: 'Rs '),
                  ),
                  const SizedBox(height: 20),
                  const Text('Supplier (optional)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: kPrimary)),
                  gap(),
                  TextField(
                    controller: supplier,
                    decoration: const InputDecoration(
                        labelText: 'Supplier / Seller Name'),
                  ),
                  gap(),
                  TextField(
                    controller: supplierContact,
                    decoration: const InputDecoration(
                        labelText: 'Supplier Contact / CNIC'),
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
              label: const Text('Save Phone'),
              onPressed: saving
                  ? null
                  : () async {
                      final priceValue = double.tryParse(price.text.trim());
                      if (brand.text.trim().isEmpty ||
                          model.text.trim().isEmpty) {
                        setD(() =>
                            errorText = 'Brand and Model are required.');
                        return;
                      }
                      if (imei1.text.trim().length != 15) {
                        setD(() => errorText =
                            'IMEI 1 must be exactly 15 digits (now ${imei1.text.trim().length}).');
                        return;
                      }
                      if (imei2.text.trim().isNotEmpty &&
                          imei2.text.trim().length != 15) {
                        setD(() => errorText =
                            'IMEI 2 must be 15 digits, or leave it empty.');
                        return;
                      }
                      if (priceValue == null || priceValue < 0) {
                        setD(() =>
                            errorText = 'Enter a valid purchase price.');
                        return;
                      }
                      setD(() {
                        saving = true;
                        errorText = null;
                      });
                      try {
                        final mobile = await _db
                            .from('mobiles')
                            .insert({
                              'brand': brand.text.trim(),
                              'model': model.text.trim(),
                              'variant': nullIfEmpty(variant),
                              'color': nullIfEmpty(color),
                              'imei_1': imei1.text.trim(),
                              'imei_2': nullIfEmpty(imei2),
                              'purchase_price': priceValue,
                              'condition': condition,
                            })
                            .select()
                            .single();
                        await _db.from('purchases').insert({
                          'mobile_id': mobile['id'],
                          'buy_price': priceValue,
                          'supplier_name': nullIfEmpty(supplier),
                          'supplier_contact': nullIfEmpty(supplierContact),
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        _snack('Phone added successfully ✅');
                        _loadMobiles();
                      } on PostgrestException catch (e) {
                        setD(() {
                          saving = false;
                          errorText = e.code == '23505'
                              ? 'This IMEI already exists in stock.'
                              : 'Error: ${e.message}';
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
        ),
      ),
    );
  }

  // ---------------- DETAILS SHEET + DELETE BUTTON ----------------
  void _showDetails(Map m) {
    Widget row(String k, dynamic v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 110,
                  child: Text(k,
                      style: TextStyle(color: Colors.grey.shade600))),
              Expanded(
                  child: Text('${v ?? '-'}',
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
        );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${m['brand']} ${m['model']}',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Delete Phone',
                  onPressed: () => _confirmAndDelete(m, sheetCtx),
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFDC2626)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            row('Storage / RAM', m['variant']),
            row('Color', m['color']),
            row(
                'Condition',
                m['condition'] == 'NEW'
                    ? 'New (Box Packed)'
                    : 'Used / Pre-Owned'),
            row('IMEI 1', m['imei_1']),
            row('IMEI 2', m['imei_2']),
            row('Purchase Price', rs(m['purchase_price'] as num)),
            row('Status', m['status']),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFDC2626)),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _confirmAndDelete(m, sheetCtx),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Phone Entry',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- BUILD ----------------
  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Phone'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search brand, model, color or IMEI',
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in [
                  ['ALL', 'All', _mobiles.length],
                  ['AVAILABLE', 'Available', _count('AVAILABLE')],
                  ['SOLD', 'Sold', _count('SOLD')],
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
                : list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.phone_android,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text('No phones found',
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('Tap "Add Phone" to add your first one',
                                style:
                                    TextStyle(color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadMobiles,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                          itemCount: list.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final m = list[i];
                            final sc = _statusColor(m['status']);
                            final extra = [
                              if (m['variant'] != null) m['variant'],
                              if (m['color'] != null) m['color'],
                              m['condition'] == 'NEW' ? 'New' : 'Used',
                            ].join('  •  ');
                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _showDetails(m),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor:
                                            kPrimary.withValues(alpha: 0.1),
                                        child: Text(
                                          '${m['brand']}'
                                              .substring(0, 1)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                              color: kPrimary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('${m['brand']} ${m['model']}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 16)),
                                            const SizedBox(height: 2),
                                            Text(extra,
                                                style: TextStyle(
                                                    color:
                                                        Colors.grey.shade600,
                                                    fontSize: 13)),
                                            const SizedBox(height: 2),
                                            Text('IMEI ${m['imei_1']}',
                                                style: TextStyle(
                                                    color:
                                                        Colors.grey.shade500,
                                                    fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(rs(m['purchase_price'] as num),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15)),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4),
                                            decoration: BoxDecoration(
                                              color:
                                                  sc.withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(m['status'],
                                                style: TextStyle(
                                                    color: sc,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}