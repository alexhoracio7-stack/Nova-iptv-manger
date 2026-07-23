import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await AppDb.instance.database;
  runApp(const NovaIptvApp());
}

const kPrimary = Color(0xFF6D5DFC);
const kCyan = Color(0xFF25D9E8);
const kGreen = Color(0xFF28D79F);
const kOrange = Color(0xFFFFB44C);
const kRed = Color(0xFFFF5C7A);
const kBg = Color(0xFF070B17);
const kPanel = Color(0xFF11182A);
const kPanelSoft = Color(0xFF171F34);

class NovaIptvApp extends StatelessWidget {
  const NovaIptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kPrimary,
      brightness: Brightness.dark,
      surface: kPanel,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nova IPTV Manager',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBg,
        fontFamily: 'Roboto',
        cardTheme: CardThemeData(
          color: kPanel,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kPanelSoft,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF26304A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: kCyan, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0C1220),
          indicatorColor: kPrimary.withValues(alpha: .22),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? Colors.white : Colors.white60,
            );
          }),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dbPath = join(await getDatabasesPath(), 'nova_iptv_manager.db');
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE clients(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            plan TEXT,
            creditCost REAL NOT NULL,
            advertisingCost REAL NOT NULL,
            includeAdvertising INTEGER NOT NULL,
            includeIva INTEGER NOT NULL,
            ivaPercent REAL NOT NULL,
            margin REAL NOT NULL,
            price REAL NOT NULL,
            dueDate TEXT NOT NULL,
            status TEXT NOT NULL,
            notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            clientId INTEGER,
            amount REAL NOT NULL,
            paymentDate TEXT NOT NULL,
            method TEXT,
            notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            description TEXT NOT NULL,
            amount REAL NOT NULL,
            expenseDate TEXT NOT NULL,
            notes TEXT
          )
        ''');
      },
    );
  }

  Future<List<Map<String, Object?>>> clients() async {
    final db = await database;
    return db.query('clients', orderBy: 'dueDate ASC');
  }

  Future<List<Map<String, Object?>>> payments() async {
    final db = await database;
    return db.rawQuery('''
      SELECT payments.*, clients.name AS clientName
      FROM payments LEFT JOIN clients ON clients.id = payments.clientId
      ORDER BY paymentDate DESC
    ''');
  }

  Future<List<Map<String, Object?>>> expenses() async {
    final db = await database;
    return db.query('expenses', orderBy: 'expenseDate DESC');
  }

  Future<void> saveClient(Map<String, Object?> data, {int? id}) async {
    final db = await database;
    if (id == null) {
      await db.insert('clients', data);
    } else {
      await db.update('clients', data, where: 'id=?', whereArgs: [id]);
    }
  }

  Future<void> deleteClient(int id) async {
    final db = await database;
    await db.delete('clients', where: 'id=?', whereArgs: [id]);
  }

  Future<void> addPayment(Map<String, Object?> data) async {
    final db = await database;
    await db.insert('payments', data);
  }

  Future<void> addExpense(Map<String, Object?> data) async {
    final db = await database;
    await db.insert('expenses', data);
  }

  Future<double> sum(String table, String column) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COALESCE(SUM($column), 0) total FROM $table');
    return (result.first['total'] as num).toDouble();
  }
}

String money(num value) => NumberFormat.currency(symbol: r'$', decimalDigits: 0).format(value);
String shortDate(DateTime date) => DateFormat('dd MMM', 'es').format(date);
DateTime dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

double calculatePrice({
  required double credit,
  required double advertising,
  required bool includeAdvertising,
  required bool includeIva,
  required double iva,
  required double margin,
}) {
  final subtotal = credit + margin + (includeAdvertising ? advertising : 0);
  return subtotal + (includeIva ? subtotal * iva / 100 : 0);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  int refreshKey = 0;

  void refresh() => setState(() => refreshKey++);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(key: ValueKey('dashboard-$refreshKey'), onChanged: refresh),
      ClientsPage(key: ValueKey('clients-$refreshKey'), onChanged: refresh),
      PaymentsPage(key: ValueKey('payments-$refreshKey'), onChanged: refresh),
      ExpensesPage(key: ValueKey('expenses-$refreshKey'), onChanged: refresh),
      RemindersPage(key: ValueKey('reminders-$refreshKey')),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Panel'),
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt), label: 'Clientes'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Cobros'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Gastos'),
          NavigationDestination(icon: Icon(Icons.notifications_none_rounded), selectedIcon: Icon(Icons.notifications_rounded), label: 'Avisos'),
        ],
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? action;

  const ScreenHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow.toUpperCase(), style: const TextStyle(color: kCyan, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
                const SizedBox(height: 6),
                Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.8)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white60, height: 1.35)),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class GlowIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const GlowIcon(this.icon, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: .35)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .12), blurRadius: 20)],
        ),
        child: Icon(icon, color: color),
      );
}

class DashboardPage extends StatefulWidget {
  final VoidCallback onChanged;
  const DashboardPage({super.key, required this.onChanged});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Future<Map<String, Object>> load() async {
    final clients = await AppDb.instance.clients();
    final income = await AppDb.instance.sum('payments', 'amount');
    final expenses = await AppDb.instance.sum('expenses', 'amount');
    final today = dayOnly(DateTime.now());
    final dueSoon = clients.where((c) {
      final due = dayOnly(DateTime.parse(c['dueDate'] as String));
      final days = due.difference(today).inDays;
      return days >= 0 && days <= 7;
    }).length;
    final overdue = clients.where((c) {
      final due = dayOnly(DateTime.parse(c['dueDate'] as String));
      return due.isBefore(today) && c['status'] == 'Activo';
    }).length;
    return {
      'clients': clients,
      'income': income,
      'expenses': expenses,
      'dueSoon': dueSoon,
      'overdue': overdue,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object>>(
      future: load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final clients = data['clients'] as List<Map<String, Object?>>;
        final income = data['income'] as double;
        final expenses = data['expenses'] as double;
        final profit = income - expenses;
        final next = clients.take(4).toList();

        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ScreenHeader(
                eyebrow: 'Centro de control',
                title: 'Nova IPTV',
                subtitle: DateFormat("EEEE, d 'de' MMMM", 'es').format(DateTime.now()),
                action: const GlowIcon(Icons.bolt_rounded, kCyan),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ProfitHero(income: income, expenses: expenses, profit: profit),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 126,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    MetricTile(label: 'Clientes', value: '${clients.length}', icon: Icons.groups_rounded, color: kPrimary),
                    MetricTile(label: 'Por vencer', value: '${data['dueSoon']}', icon: Icons.schedule_rounded, color: kOrange),
                    MetricTile(label: 'Vencidos', value: '${data['overdue']}', icon: Icons.error_outline_rounded, color: kRed),
                  ],
                ),
              ),
              SectionTitle(title: 'Próximos vencimientos', actionText: '${clients.length} clientes'),
              if (next.isEmpty)
                const EmptyCard(icon: Icons.person_add_alt_1_rounded, title: 'Agrega tu primer cliente', subtitle: 'Empieza a controlar vencimientos, cobros y ganancias.')
              else
                ...next.map((client) => ClientCompactCard(client: client)),
              const SizedBox(height: 100),
            ],
          ),
        );
      },
    );
  }
}

class ProfitHero extends StatelessWidget {
  final double income;
  final double expenses;
  final double profit;
  const ProfitHero({super.key, required this.income, required this.expenses, required this.profit});

  @override
  Widget build(BuildContext context) {
    final positive = profit >= 0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF6D5DFC), Color(0xFF2B83F6), Color(0xFF13B7C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: .25), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_graph_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('BALANCE GENERAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 18),
          Text(money(profit), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1.4)),
          Text(positive ? 'Utilidad acumulada' : 'Balance negativo', style: TextStyle(color: Colors.white.withValues(alpha: .75))),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: HeroStat(label: 'Ingresos', value: money(income), icon: Icons.south_west_rounded)),
              Container(width: 1, height: 42, color: Colors.white24),
              Expanded(child: HeroStat(label: 'Gastos', value: money(expenses), icon: Icons.north_east_rounded)),
            ],
          ),
        ],
      ),
    );
  }
}

class HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const HeroStat({super.key, required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18)),
          const SizedBox(width: 10),
          Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)), Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))])),
        ]),
      );
}

class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const MetricTile({super.key, required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 154,
        margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF202A43)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GlowIcon(icon, color),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? actionText;
  const SectionTitle({super.key, required this.title, this.actionText});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          if (actionText != null) Text(actionText!, style: const TextStyle(color: kCyan, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

class ClientCompactCard extends StatelessWidget {
  final Map<String, Object?> client;
  const ClientCompactCard({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    final due = dayOnly(DateTime.parse(client['dueDate'] as String));
    final days = due.difference(dayOnly(DateTime.now())).inDays;
    final color = days < 0 ? kRed : days <= 7 ? kOrange : kGreen;
    final status = days < 0 ? 'Vencido' : days == 0 ? 'Vence hoy' : 'Faltan $days días';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF202A43))),
      child: Row(children: [
        AvatarName(name: client['name'] as String),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(client['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('${client['plan']} · ${money(client['price'] as num)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(shortDate(due), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          StatusPill(text: status, color: color),
        ]),
      ]),
    );
  }
}

class AvatarName extends StatelessWidget {
  final String name;
  const AvatarName({super.key, required this.name});
  @override
  Widget build(BuildContext context) {
    final colors = [kPrimary, kCyan, kGreen, kOrange];
    final color = colors[name.codeUnitAt(0) % colors.length];
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: .55)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill({super.key, required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: .4))),
        child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

class EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyCard({super.key, required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF202A43))),
        child: Column(children: [GlowIcon(icon, kCyan), const SizedBox(height: 15), Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), const SizedBox(height: 6), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))]),
      );
}

class ClientsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const ClientsPage({super.key, required this.onChanged});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final search = TextEditingController();
  String filter = 'Todos';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AppDb.instance.clients(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final today = dayOnly(DateTime.now());
        final query = search.text.trim().toLowerCase();
        final items = snapshot.data!.where((client) {
          final due = dayOnly(DateTime.parse(client['dueDate'] as String));
          final matchesQuery = (client['name'] as String).toLowerCase().contains(query) || (client['plan'] as String).toLowerCase().contains(query);
          final matchesFilter = filter == 'Todos' || (filter == 'Activos' && !due.isBefore(today)) || (filter == 'Vencidos' && due.isBefore(today));
          return matchesQuery && matchesFilter;
        }).toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientForm()));
              setState(() {});
              widget.onChanged();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nuevo cliente', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          body: ListView(children: [
            const ScreenHeader(eyebrow: 'Base de datos', title: 'Clientes', subtitle: 'Organiza tus cuentas y vencimientos.'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar cliente o plan...'),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: ['Todos', 'Activos', 'Vencidos'].map((value) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(value), selected: filter == value, onSelected: (_) => setState(() => filter = value)),
              )).toList()),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const EmptyCard(icon: Icons.manage_search_rounded, title: 'No encontramos clientes', subtitle: 'Prueba otro filtro o registra un cliente nuevo.')
            else
              ...items.map((client) => ClientDetailedCard(
                client: client,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ClientForm(existing: client)));
                  setState(() {});
                  widget.onChanged();
                },
              )),
            const SizedBox(height: 110),
          ]),
        );
      },
    );
  }
}

class ClientDetailedCard extends StatelessWidget {
  final Map<String, Object?> client;
  final VoidCallback onTap;
  const ClientDetailedCard({super.key, required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final due = dayOnly(DateTime.parse(client['dueDate'] as String));
    final days = due.difference(dayOnly(DateTime.now())).inDays;
    final color = days < 0 ? kRed : days <= 7 ? kOrange : kGreen;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF202A43))),
        child: Column(children: [
          Row(children: [
            AvatarName(name: client['name'] as String),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(client['name'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              Text(client['plan'] as String, style: const TextStyle(color: Colors.white60)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ]),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFF242E48)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: SmallInfo(label: 'Cobro', value: money(client['price'] as num), icon: Icons.payments_outlined)),
            Expanded(child: SmallInfo(label: 'Vence', value: shortDate(due), icon: Icons.event_outlined)),
            StatusPill(text: days < 0 ? 'Vencido' : days == 0 ? 'Hoy' : '$days días', color: color),
          ]),
        ]),
      ),
    );
  }
}

class SmallInfo extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const SmallInfo({super.key, required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: Colors.white38),
    const SizedBox(width: 7),
    Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)), Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))])),
  ]);
}

class ClientForm extends StatefulWidget {
  final Map<String, Object?>? existing;
  const ClientForm({super.key, this.existing});

  @override
  State<ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<ClientForm> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController plan;
  late final TextEditingController credit;
  late final TextEditingController advertising;
  late final TextEditingController margin;
  late final TextEditingController iva;
  late final TextEditingController notes;
  bool includeAdvertising = true;
  bool includeIva = true;
  DateTime dueDate = DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    name = TextEditingController(text: e?['name']?.toString() ?? '');
    phone = TextEditingController(text: e?['phone']?.toString() ?? '');
    plan = TextEditingController(text: e?['plan']?.toString() ?? 'Plan mensual');
    credit = TextEditingController(text: e?['creditCost']?.toString() ?? '0');
    advertising = TextEditingController(text: e?['advertisingCost']?.toString() ?? '0');
    margin = TextEditingController(text: e?['margin']?.toString() ?? '0');
    iva = TextEditingController(text: e?['ivaPercent']?.toString() ?? '19');
    notes = TextEditingController(text: e?['notes']?.toString() ?? '');
    includeAdvertising = (e?['includeAdvertising'] as int? ?? 1) == 1;
    includeIva = (e?['includeIva'] as int? ?? 1) == 1;
    if (e != null) dueDate = DateTime.parse(e['dueDate'] as String);
  }

  double valueOf(TextEditingController controller) => double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
  double get price => calculatePrice(
    credit: valueOf(credit),
    advertising: valueOf(advertising),
    includeAdvertising: includeAdvertising,
    includeIva: includeIva,
    iva: valueOf(iva),
    margin: valueOf(margin),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        title: Text(widget.existing == null ? 'Nuevo cliente' : 'Editar cliente', style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          children: [
            FormSection(title: 'Información del cliente', icon: Icons.person_outline_rounded, children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nombre completo'), validator: (value) => value == null || value.trim().isEmpty ? 'Escribe el nombre' : null),
              const SizedBox(height: 12),
              TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'WhatsApp con código de país')),
              const SizedBox(height: 12),
              TextFormField(controller: plan, decoration: const InputDecoration(labelText: 'Plan o servicio')),
            ]),
            const SizedBox(height: 16),
            FormSection(title: 'Precio inteligente', icon: Icons.calculate_outlined, children: [
              Row(children: [
                Expanded(child: NumberField(controller: credit, label: 'Crédito IPTV', onChanged: () => setState(() {}))),
                const SizedBox(width: 10),
                Expanded(child: NumberField(controller: margin, label: 'Ganancia', onChanged: () => setState(() {}))),
              ]),
              const SizedBox(height: 12),
              NumberField(controller: advertising, label: 'Publicidad', onChanged: () => setState(() {})),
              const SizedBox(height: 8),
              ModernSwitch(title: 'Incluir publicidad', value: includeAdvertising, onChanged: (value) => setState(() => includeAdvertising = value)),
              ModernSwitch(title: 'Aplicar IVA', value: includeIva, onChanged: (value) => setState(() => includeIva = value)),
              if (includeIva) ...[
                const SizedBox(height: 8),
                NumberField(controller: iva, label: 'IVA %', onChanged: () => setState(() {})),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [kPrimary.withValues(alpha: .28), kCyan.withValues(alpha: .12)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kCyan.withValues(alpha: .32)),
                ),
                child: Row(children: [
                  const GlowIcon(Icons.auto_awesome_rounded, kCyan),
                  const SizedBox(width: 14),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('PRECIO SUGERIDO', style: TextStyle(color: kCyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)), Text('Crédito + extras + impuestos', style: TextStyle(color: Colors.white54, fontSize: 11))])),
                  Text(money(price), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            FormSection(title: 'Vencimiento y notas', icon: Icons.event_available_outlined, children: [
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () async {
                  final picked = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime(2100), initialDate: dueDate);
                  if (picked != null) setState(() => dueDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: kPanelSoft, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF26304A))),
                  child: Row(children: [const Icon(Icons.calendar_month_rounded, color: kCyan), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Fecha de vencimiento', style: TextStyle(color: Colors.white54, fontSize: 11)), Text(DateFormat('dd MMMM yyyy', 'es').format(dueDate), style: const TextStyle(fontWeight: FontWeight.w800))])), const Icon(Icons.chevron_right_rounded)]),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas internas')),
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kPrimary, minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await AppDb.instance.saveClient({
                  'name': name.text.trim(),
                  'phone': phone.text.trim(),
                  'plan': plan.text.trim(),
                  'creditCost': valueOf(credit),
                  'advertisingCost': valueOf(advertising),
                  'includeAdvertising': includeAdvertising ? 1 : 0,
                  'includeIva': includeIva ? 1 : 0,
                  'ivaPercent': valueOf(iva),
                  'margin': valueOf(margin),
                  'price': price,
                  'dueDate': dueDate.toIso8601String(),
                  'status': 'Activo',
                  'notes': notes.text.trim(),
                }, id: widget.existing?['id'] as int?);
                if (mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Guardar cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async {
                  await AppDb.instance.deleteClient(widget.existing!['id'] as int);
                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline_rounded, color: kRed),
                label: const Text('Eliminar cliente', style: TextStyle(color: kRed)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FormSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const FormSection({super.key, required this.title, required this.icon, required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF202A43))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [GlowIcon(icon, kPrimary), const SizedBox(width: 12), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))]),
          const SizedBox(height: 18),
          ...children,
        ]),
      );
}

class NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  const NumberField({super.key, required this.controller, required this.label, required this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label, prefixText: r'$ '), onChanged: (_) => onChanged());
}

class ModernSwitch extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const ModernSwitch({super.key, required this.title, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), value: value, activeColor: kCyan, onChanged: onChanged);
}

class PaymentsPage extends StatefulWidget {
  final VoidCallback onChanged;
  const PaymentsPage({super.key, required this.onChanged});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AppDb.instance.clients(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final clients = snapshot.data!;
        return ListView(children: [
          const ScreenHeader(eyebrow: 'Ingresos', title: 'Registrar cobro', subtitle: 'Cobra y renueva el servicio en un toque.'),
          if (clients.isEmpty)
            const EmptyCard(icon: Icons.person_add_alt_1_rounded, title: 'No hay clientes', subtitle: 'Registra un cliente antes de añadir pagos.')
          else
            ...clients.map((client) => PaymentClientCard(client: client, onPaid: () { setState(() {}); widget.onChanged(); })),
          const SectionTitle(title: 'Últimos movimientos'),
          FutureBuilder<List<Map<String, Object?>>>(
            future: AppDb.instance.payments(),
            builder: (context, paymentsSnapshot) {
              if (!paymentsSnapshot.hasData) return const SizedBox();
              final payments = paymentsSnapshot.data!.take(8).toList();
              if (payments.isEmpty) return const EmptyCard(icon: Icons.receipt_long_rounded, title: 'Sin cobros registrados', subtitle: 'Tus movimientos aparecerán aquí.');
              return Column(children: payments.map((p) => MovementTile(icon: Icons.south_west_rounded, color: kGreen, title: p['clientName']?.toString() ?? 'Cliente', subtitle: shortDate(DateTime.parse(p['paymentDate'] as String)), value: '+${money(p['amount'] as num)}')).toList());
            },
          ),
          const SizedBox(height: 100),
        ]);
      },
    );
  }
}

class PaymentClientCard extends StatelessWidget {
  final Map<String, Object?> client;
  final VoidCallback onPaid;
  const PaymentClientCard({super.key, required this.client, required this.onPaid});

  Future<void> registerPayment(BuildContext context) async {
    final amount = TextEditingController(text: (client['price'] as num).toString());
    final days = TextEditingController(text: '30');
    final result = await showModalBottomSheet<Map<String, double>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 44, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
          Text('Cobro a ${client['name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Registra el pago y extiende el vencimiento.', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 20),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Monto recibido', prefixText: r'$ ')),
          const SizedBox(height: 12),
          TextField(controller: days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Días de renovación')),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kPrimary, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
            onPressed: () => Navigator.pop(context, {'amount': double.tryParse(amount.text.replaceAll(',', '.')) ?? 0, 'days': double.tryParse(days.text) ?? 30}),
            icon: const Icon(Icons.verified_rounded),
            label: const Text('Confirmar pago', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    );
    if (result == null || result['amount']! <= 0) return;
    await AppDb.instance.addPayment({'clientId': client['id'], 'amount': result['amount'], 'paymentDate': DateTime.now().toIso8601String(), 'method': 'Aplicación', 'notes': ''});
    final current = DateTime.parse(client['dueDate'] as String);
    final base = current.isAfter(DateTime.now()) ? current : DateTime.now();
    final updated = Map<String, Object?>.from(client)..['dueDate'] = base.add(Duration(days: result['days']!.round())).toIso8601String();
    updated.remove('id');
    updated.remove('clientName');
    await AppDb.instance.saveClient(updated, id: client['id'] as int);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago registrado y servicio renovado.')));
    onPaid();
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF202A43))),
        child: Row(children: [
          AvatarName(name: client['name'] as String),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(client['name'] as String, style: const TextStyle(fontWeight: FontWeight.w900)), Text('${money(client['price'] as num)} · ${client['plan']}', style: const TextStyle(color: Colors.white60, fontSize: 12))])),
          IconButton.filled(onPressed: () => registerPayment(context), style: IconButton.styleFrom(backgroundColor: kGreen.withValues(alpha: .16), foregroundColor: kGreen), icon: const Icon(Icons.add_card_rounded)),
        ]),
      );
}

class MovementTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String value;
  const MovementTile({super.key, required this.icon, required this.color, required this.title, required this.subtitle, required this.value});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 9),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF202A43))),
        child: Row(children: [GlowIcon(icon, color), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(color: Colors.white45, fontSize: 11))])), Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900))]),
      );
}

class ExpensesPage extends StatefulWidget {
  final VoidCallback onChanged;
  const ExpensesPage({super.key, required this.onChanged});
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  Future<void> addExpense() async {
    final description = TextEditingController();
    final amount = TextEditingController();
    String category = 'Créditos IPTV';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPanel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 44, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
          const Text('Nuevo gasto', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: ['Créditos IPTV', 'Publicidad', 'Internet', 'Herramientas', 'Impuestos', 'Otros'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setSheetState(() => category = value!),
          ),
          const SizedBox(height: 12),
          TextField(controller: description, decoration: const InputDecoration(labelText: 'Descripción')),
          const SizedBox(height: 12),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Monto', prefixText: r'$ ')),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kPrimary, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
            onPressed: () async {
              final value = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
              if (description.text.trim().isEmpty || value <= 0) return;
              await AppDb.instance.addExpense({'category': category, 'description': description.text.trim(), 'amount': value, 'expenseDate': DateTime.now().toIso8601String(), 'notes': ''});
              if (context.mounted) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.save_rounded),
            label: const Text('Guardar gasto', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      )),
    );
    if (saved == true) { setState(() {}); widget.onChanged(); }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AppDb.instance.expenses(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        final total = items.fold<double>(0, (sum, item) => sum + (item['amount'] as num).toDouble());
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(backgroundColor: kPrimary, foregroundColor: Colors.white, onPressed: addExpense, icon: const Icon(Icons.add_rounded), label: const Text('Nuevo gasto', style: TextStyle(fontWeight: FontWeight.w800))),
          body: ListView(children: [
            const ScreenHeader(eyebrow: 'Control financiero', title: 'Gastos', subtitle: 'Registra cada salida de dinero.'),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [kRed.withValues(alpha: .28), kOrange.withValues(alpha: .12)]), borderRadius: BorderRadius.circular(26), border: Border.all(color: kRed.withValues(alpha: .25))),
              child: Row(children: [const GlowIcon(Icons.trending_down_rounded, kRed), const SizedBox(width: 14), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GASTOS ACUMULADOS', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.1)), Text('Mantén tus costos bajo control', style: TextStyle(color: Colors.white70, fontSize: 12))])), Text(money(total), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900))]),
            ),
            if (items.isEmpty)
              const EmptyCard(icon: Icons.savings_outlined, title: 'Sin gastos registrados', subtitle: 'Añade créditos, publicidad, herramientas e impuestos.')
            else
              ...items.map((item) => MovementTile(icon: Icons.north_east_rounded, color: kRed, title: item['description'] as String, subtitle: '${item['category']} · ${shortDate(DateTime.parse(item['expenseDate'] as String))}', value: '-${money(item['amount'] as num)}')),
            const SizedBox(height: 110),
          ]),
        );
      },
    );
  }
}

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  Future<void> openWhatsApp(BuildContext context, Map<String, Object?> client) async {
    final due = dayOnly(DateTime.parse(client['dueDate'] as String));
    final days = due.difference(dayOnly(DateTime.now())).inDays;
    final timing = days < 0 ? 'venció hace ${days.abs()} día(s)' : days == 0 ? 'vence hoy' : 'vence en $days día(s)';
    final message = 'Hola ${client['name']}, te recordamos que tu servicio $timing. El valor de renovación es ${money(client['price'] as num)}. Contáctanos para renovar. Gracias.';
    final phone = (client['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este cliente no tiene teléfono.')));
      return;
    }
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: AppDb.instance.clients(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final today = dayOnly(DateTime.now());
        final clients = snapshot.data!.where((client) {
          final days = dayOnly(DateTime.parse(client['dueDate'] as String)).difference(today).inDays;
          return days <= 7;
        }).toList();
        return ListView(children: [
          const ScreenHeader(eyebrow: 'Comunicación', title: 'Recordatorios', subtitle: 'Avisa a tiempo y reduce cuentas vencidas.'),
          if (clients.isEmpty)
            const EmptyCard(icon: Icons.notifications_active_outlined, title: 'Todo está al día', subtitle: 'No hay clientes próximos a vencer.')
          else
            ...clients.map((client) {
              final due = dayOnly(DateTime.parse(client['dueDate'] as String));
              final days = due.difference(today).inDays;
              final color = days < 0 ? kRed : kOrange;
              return Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(24), border: Border.all(color: color.withValues(alpha: .3))),
                child: Column(children: [
                  Row(children: [AvatarName(name: client['name'] as String), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(client['name'] as String, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), Text('${money(client['price'] as num)} · ${shortDate(due)}', style: const TextStyle(color: Colors.white60))])), StatusPill(text: days < 0 ? '${days.abs()} días tarde' : days == 0 ? 'Hoy' : '$days días', color: color)]),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1FA855), minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () => openWhatsApp(context, client),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Enviar por WhatsApp', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ]),
              );
            }),
          const SizedBox(height: 100),
        ]);
      },
    );
  }
}
