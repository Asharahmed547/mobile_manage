import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme.dart';

final _db = Supabase.instance.client;

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  List _sales = [];
  List _mobiles = [];
  bool _loading = true;
  String _period = 'TODAY';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final salesData = await _db
          .from('sales')
          .select('*, mobiles(brand, model, imei_1, purchase_price)')
          .order('sale_date', ascending: false);

      final mobilesData = await _db
          .from('mobiles')
          .select()
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _sales = salesData;
        _mobiles = mobilesData;
      });
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

  DateTime? get _cutoffDate {
    final now = DateTime.now();
    switch (_period) {
      case 'TODAY':
        return DateTime(now.year, now.month, now.day);
      case 'WEEK':
        final todayStart = DateTime(now.year, now.month, now.day);
        return todayStart.subtract(const Duration(days: 6));
      case 'MONTH':
        return DateTime(now.year, now.month, 1);
      case 'YEAR':
        return DateTime(now.year, 1, 1);
      default:
        return null;
    }
  }

  bool _inPeriod(dynamic iso) {
    if (iso == null) return false;
    final cutoff = _cutoffDate;
    if (cutoff == null) return true;
    final dt = DateTime.parse(iso.toString()).toLocal();
    return !dt.isBefore(cutoff);
  }

  List get _filteredSales =>
      _sales.where((s) => _inPeriod(s['sale_date'])).toList();

  List get _filteredBoughtMobiles =>
      _mobiles.where((m) => _inPeriod(m['created_at'])).toList();

  String _date(String iso) {
    final d = DateTime.parse(iso).toLocal();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day}/${d.month}/${d.year}  $h:$m $ap';
  }

  String get _periodLabel {
    switch (_period) {
      case 'TODAY':
        return "Today's Summary";
      case 'WEEK':
        return 'Last 7 Days Summary';
      case 'MONTH':
        return 'This Month Summary';
      case 'YEAR':
        return 'This Year Summary';
      default:
        return 'All-Time Summary';
    }
  }

  Widget _metricCard({
    required String label,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtext,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fSales = _filteredSales;
    final fBought = _filteredBoughtMobiles;

    double totalRevenue = 0;
    double totalNetPL = 0;
    double grossProfit = 0;
    double grossLoss = 0;
    int profitDeals = 0;
    int lossDeals = 0;

    final Map paymentCount = {'CASH': 0, 'BANK': 0, 'CARD': 0};
    final Map paymentAmount = {'CASH': 0.0, 'BANK': 0.0, 'CARD': 0.0};

    for (final s in fSales) {
      final sp = (s['sell_price'] as num).toDouble();
      final pl = (s['profit_loss'] as num).toDouble();
      totalRevenue += sp;
      totalNetPL += pl;

      if (pl >= 0) {
        grossProfit += pl;
        profitDeals++;
      } else {
        grossLoss += pl.abs();
        lossDeals++;
      }

      final mode = (s['payment_mode'] ?? 'CASH').toString().toUpperCase();
      paymentCount[mode] = (paymentCount[mode] ?? 0) + 1;
      paymentAmount[mode] = (paymentAmount[mode] ?? 0.0) + sp;
    }

    double totalBoughtAmount = 0;
    for (final m in fBought) {
      totalBoughtAmount += (m['purchase_price'] as num).toDouble();
    }

    int availableCount = 0;
    double currentStockValue = 0;
    for (final m in _mobiles) {
      if (m['status'] == 'AVAILABLE') {
        availableCount++;
        currentStockValue += (m['purchase_price'] as num).toDouble();
      }
    }

    final isNetProfit = totalNetPL >= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final p in [
                  ['TODAY', 'Today'],
                  ['WEEK', 'Weekly'],
                  ['MONTH', 'Monthly'],
                  ['YEAR', 'Yearly'],
                  ['ALL', 'All Time'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p[1]),
                      selected: _period == p[0],
                      onSelected: (_) => setState(() => _period = p[0]),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: kGradient,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _periodLabel,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${fSales.length} Sold  •  ${fBought.length} Bought',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isNetProfit ? 'Net Profit' : 'Net Loss',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    isNetProfit
                                        ? Icons.trending_up
                                        : Icons.trending_down,
                                    color: isNetProfit
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFFFCA5A5),
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FittedBox(
                                      alignment: Alignment.centerLeft,
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '${isNetProfit ? '+' : '-'}${rs(totalNetPL.abs())}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 30,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Total Sales',
                                              style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12)),
                                          const SizedBox(height: 2),
                                          Text(rs(totalRevenue),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      height: 28,
                                      width: 1,
                                      color: Colors.white24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Stock Purchased',
                                              style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12)),
                                          const SizedBox(height: 2),
                                          Text(rs(totalBoughtAmount),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GridView.count(
                          crossAxisCount:
                              MediaQuery.of(context).size.width > 700 ? 4 : 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.35,
                          children: [
                            _metricCard(
                              label: 'Gross Profit',
                              value: rs(grossProfit),
                              subtext: '$profitDeals profitable sales',
                              icon: Icons.arrow_upward,
                              color: const Color(0xFF059669),
                            ),
                            _metricCard(
                              label: 'Gross Loss',
                              value: rs(grossLoss),
                              subtext: '$lossDeals loss sales',
                              icon: Icons.arrow_downward,
                              color: const Color(0xFFDC2626),
                            ),
                            _metricCard(
                              label: 'Phones Sold',
                              value: '${fSales.length}',
                              subtext: 'Revenue: ${rs(totalRevenue)}',
                              icon: Icons.sell,
                              color: kPrimary,
                            ),
                            _metricCard(
                              label: 'In-Stock Value',
                              value: rs(currentStockValue),
                              subtext: '$availableCount available now',
                              icon: Icons.inventory_2,
                              color: const Color(0xFF0891B2),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text('Payment Breakdown',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                _paymentItem(
                                    'Cash',
                                    paymentCount['CASH'] ?? 0,
                                    paymentAmount['CASH'] ?? 0.0,
                                    Icons.payments,
                                    const Color(0xFF059669)),
                                _paymentItem(
                                    'Bank',
                                    paymentCount['BANK'] ?? 0,
                                    paymentAmount['BANK'] ?? 0.0,
                                    Icons.account_balance,
                                    kPrimary),
                                _paymentItem(
                                    'Card',
                                    paymentCount['CARD'] ?? 0,
                                    paymentAmount['CARD'] ?? 0.0,
                                    Icons.credit_card,
                                    const Color(0xFFEA580C)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sales in Selected Period',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('${fSales.length} items',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (fSales.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                children: [
                                  Icon(Icons.bar_chart,
                                      size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text('No sales recorded in this period',
                                      style: TextStyle(
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                          )
                        else
                          for (final s in fSales) ...[
                            _saleReportTile(s),
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

  Widget _paymentItem(
      String title, int count, double amount, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 6),
          Text('$title ($count)',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(rs(amount),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _saleReportTile(Map s) {
    final mob = s['mobiles'];
    final pl = (s['profit_loss'] as num).toDouble();
    final isProfit = pl >= 0;
    final c = isProfit ? const Color(0xFF059669) : const Color(0xFFDC2626);
    final cost = (mob?['purchase_price'] as num?)?.toDouble() ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: c.withValues(alpha: 0.12),
              child: Icon(isProfit ? Icons.trending_up : Icons.trending_down,
                  color: c, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mob == null ? 'Mobile' : '${mob['brand']} ${mob['model']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Buy: ${rs(cost)}  •  Sell: ${rs(s['sell_price'] as num)}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                  Text(
                    _date(s['sale_date']),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${isProfit ? '+' : '-'}${rs(pl.abs())}',
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}