import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ------------------------- ثوابت -------------------------

class Mood {
  final int value;
  final String emoji;
  final String label;
  final Color color;
  const Mood(this.value, this.emoji, this.label, this.color);
}

const List<Mood> kMoods = [
  Mood(5, '😄', 'ممتاز', Color(0xFF2E8B57)),
  Mood(4, '🙂', 'زين', Color(0xFF7CB342)),
  Mood(3, '😐', 'عادي', Color(0xFFD4A017)),
  Mood(2, '😕', 'متضايق', Color(0xFFE07B39)),
  Mood(1, '😣', 'سيء', Color(0xFFC0504D)),
];

Mood moodOf(int v) => kMoods.firstWhere((m) => m.value == v, orElse: () => kMoods[2]);

const List<String> kMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];

const List<String> kDows = ['أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];

String two(int n) => n.toString().padLeft(2, '0');
String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
DateTime parseKey(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String prettyDate(DateTime d) =>
    '${kDows[d.weekday % 7]} ${d.day} ${kMonths[d.month - 1]} ${d.year}';

// ------------------------- التخزين -------------------------

class Entry {
  final int mood;
  final String note;
  final String savedAt;
  Entry(this.mood, this.note, this.savedAt);

  Map<String, dynamic> toJson() => {'mood': mood, 'note': note, 'savedAt': savedAt};

  static Entry fromJson(Map<String, dynamic> j) => Entry(
        (j['mood'] as num).toInt(),
        (j['note'] ?? '') as String,
        (j['savedAt'] ?? '') as String,
      );
}

class Store {
  static const _kEntries = 'entries_v1';
  static const _kHour = 'notif_hour';
  static const _kMinute = 'notif_minute';
  static const _kEnabled = 'notif_enabled';

  final SharedPreferences prefs;
  Map<String, Entry> entries = {};

  Store(this.prefs);

  static Future<Store> open() async {
    final p = await SharedPreferences.getInstance();
    final s = Store(p);
    s._load();
    return s;
  }

  void _load() {
    final raw = prefs.getString(_kEntries);
    if (raw == null || raw.isEmpty) return;
    try {
      final Map<String, dynamic> m = jsonDecode(raw) as Map<String, dynamic>;
      entries = m.map((k, v) => MapEntry(k, Entry.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      entries = {};
    }
  }

  Future<void> _persist() async {
    await prefs.setString(
        _kEntries, jsonEncode(entries.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<void> put(String key, Entry e) async {
    entries[key] = e;
    await _persist();
  }

  Future<void> remove(String key) async {
    entries.remove(key);
    await _persist();
  }

  int get hour => prefs.getInt(_kHour) ?? 23;
  int get minute => prefs.getInt(_kMinute) ?? 30;
  bool get enabled => prefs.getBool(_kEnabled) ?? true;

  Future<void> setTime(int h, int m) async {
    await prefs.setInt(_kHour, h);
    await prefs.setInt(_kMinute, m);
  }

  Future<void> setEnabled(bool v) async => prefs.setBool(_kEnabled, v);
}

// ------------------------- الإشعارات -------------------------

final FlutterLocalNotificationsPlugin notifier = FlutterLocalNotificationsPlugin();
const int kDailyId = 1001;

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notifier.initialize(const InitializationSettings(android: androidInit));
}

Future<void> requestPermissions() async {
  final android = notifier.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (android == null) return;
  await android.requestNotificationsPermission();
  await android.requestExactAlarmsPermission();
}

Future<void> scheduleDaily(int hour, int minute) async {
  await notifier.cancel(kDailyId);

  final now = tz.TZDateTime.now(tz.local);
  var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_mood',
      'تذكير المزاج اليومي',
      channelDescription: 'تذكير يومي لتسجيل الحالة المزاجية',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );

  try {
    await notifier.zonedSchedule(
      kDailyId,
      'كيف كان يومك؟',
      'سجّل حالتك المزاجية الآن',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  } catch (_) {
    await notifier.zonedSchedule(
      kDailyId,
      'كيف كان يومك؟',
      'سجّل حالتك المزاجية الآن',
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}

Future<void> cancelDaily() => notifier.cancel(kDailyId);

// ------------------------- التطبيق -------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  final store = await Store.open();
  if (store.enabled) {
    await scheduleDaily(store.hour, store.minute);
  }
  runApp(MoodApp(store: store));
}

class MoodApp extends StatelessWidget {
  final Store store;
  const MoodApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF3F6B5A);
    return MaterialApp(
      title: 'مزاجي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: HomePage(store: store),
    );
  }
}

class HomePage extends StatefulWidget {
  final Store store;
  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => requestPermissions());
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayTab(store: widget.store, onChanged: _refresh),
      CalendarTab(store: widget.store, onChanged: _refresh),
      HistoryTab(store: widget.store, onChanged: _refresh),
      SettingsTab(store: widget.store, onChanged: _refresh),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('مزاجي'),
        centerTitle: true,
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), label: 'اليوم'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'التقويم'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: 'السجل'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ------------------------- شاشة التسجيل -------------------------

class EntryEditor extends StatefulWidget {
  final Store store;
  final DateTime date;
  const EntryEditor({super.key, required this.store, required this.date});

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  int? _mood;
  late TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.store.entries[dayKey(widget.date)];
    _mood = e?.mood;
    _note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_mood == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اختر حالتك أول')));
      return;
    }
    await widget.store.put(
      dayKey(widget.date),
      Entry(_mood!, _note.text.trim(), DateTime.now().toIso8601String()),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    await widget.store.remove(dayKey(widget.date));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final exists = widget.store.entries.containsKey(dayKey(widget.date));
    return Scaffold(
      appBar: AppBar(title: Text(prettyDate(widget.date))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('كيف كان هذا اليوم؟', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          MoodPicker(selected: _mood, onSelect: (v) => setState(() => _mood = v)),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'ملاحظات',
              hintText: 'اكتب أي شي صار في يومك…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          if (exists) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _delete, child: const Text('حذف التسجيل')),
          ],
        ],
      ),
    );
  }
}

class MoodPicker extends StatelessWidget {
  final int? selected;
  final ValueChanged<int> onSelect;
  const MoodPicker({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: kMoods.map((m) {
        final on = selected == m.value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onSelect(m.value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: on ? m.color : Theme.of(context).dividerColor,
                      width: on ? 2 : 1),
                  color: on ? m.color.withOpacity(0.15) : null,
                ),
                child: Column(
                  children: [
                    Text(m.emoji, style: const TextStyle(fontSize: 26)),
                    const SizedBox(height: 4),
                    Text(m.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: on ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ------------------------- تبويب اليوم -------------------------

class TodayTab extends StatelessWidget {
  final Store store;
  final VoidCallback onChanged;
  const TodayTab({super.key, required this.store, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final e = store.entries[dayKey(today)];
    final missing = _missingDays(store, today);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(prettyDate(today),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                if (e == null)
                  const Text('ما سجّلت حالتك اليوم بعد.')
                else
                  Row(children: [
                    Text(moodOf(e.mood).emoji, style: const TextStyle(fontSize: 34)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(moodOf(e.mood).label,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (e.note.isNotEmpty) Text(e.note),
                      ],
                    )),
                  ]),
                const SizedBox(height: 14),
                FilledButton.icon(
                  icon: Icon(e == null ? Icons.add : Icons.edit),
                  label: Text(e == null ? 'سجّل حالتك الآن' : 'تعديل تسجيل اليوم'),
                  onPressed: () async {
                    final r = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => EntryEditor(store: store, date: today)),
                    );
                    if (r == true) onChanged();
                  },
                ),
              ],
            ),
          ),
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('أيام فاتتك',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('تقدر تسجّلها الحين بأثر رجعي',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: missing.map((d) {
                      return ActionChip(
                        label: Text('${d.day} ${kMonths[d.month - 1]}'),
                        avatar: const Icon(Icons.add, size: 16),
                        onPressed: () async {
                          final r = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => EntryEditor(store: store, date: d)),
                          );
                          if (r == true) onChanged();
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        StatsCard(store: store),
      ],
    );
  }

  List<DateTime> _missingDays(Store store, DateTime today) {
    final out = <DateTime>[];
    for (int i = 1; i <= 14; i++) {
      final d = today.subtract(Duration(days: i));
      if (!store.entries.containsKey(dayKey(d))) out.add(d);
      if (out.length >= 7) break;
    }
    return out;
  }
}

class StatsCard extends StatelessWidget {
  final Store store;
  const StatsCard({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final keys = store.entries.keys.toList()..sort();
    if (keys.isEmpty) return const SizedBox.shrink();

    final all = keys.map((k) => store.entries[k]!.mood).toList();
    final avg = all.reduce((a, b) => a + b) / all.length;

    final now = DateTime.now();
    final last30 = keys
        .where((k) => now.difference(parseKey(k)).inDays <= 30)
        .map((k) => store.entries[k]!.mood)
        .toList();
    final avg30 =
        last30.isEmpty ? null : last30.reduce((a, b) => a + b) / last30.length;

    int streak = 0;
    var d = DateTime(now.year, now.month, now.day);
    while (store.entries.containsKey(dayKey(d))) {
      streak++;
      d = d.subtract(const Duration(days: 1));
    }

    Widget box(String v, String label) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
            ]),
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            box('${keys.length}', 'أيام مسجلة'),
            box(avg.toStringAsFixed(2), 'المتوسط العام'),
          ]),
          Row(children: [
            box(avg30 == null ? '—' : avg30.toStringAsFixed(2), 'متوسط ٣٠ يوم'),
            box('$streak', 'أيام متتالية'),
          ]),
        ]),
      ),
    );
  }
}

// ------------------------- التقويم -------------------------

class CalendarTab extends StatefulWidget {
  final Store store;
  final VoidCallback onChanged;
  const CalendarTab({super.key, required this.store, required this.onChanged});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late DateTime _cursor;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _cursor = DateTime(n.year, n.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final year = _cursor.year, month = _cursor.month;
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // الأحد = 0
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final cells = <Widget>[];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(year, month, d);
      final e = widget.store.entries[dayKey(date)];
      final isFuture = date.isAfter(today);
      final isToday = dayKey(date) == dayKey(today);

      cells.add(InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isFuture
            ? null
            : () async {
                final r = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => EntryEditor(store: widget.store, date: date)),
                );
                if (r == true) {
                  widget.onChanged();
                  setState(() {});
                }
              },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isToday
                  ? Theme.of(context).colorScheme.primary
                  : (e != null ? moodOf(e.mood).color : Theme.of(context).dividerColor),
              width: isToday ? 2 : 1,
            ),
            color: e != null ? moodOf(e.mood).color.withOpacity(0.15) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$d',
                  style: TextStyle(
                      fontSize: 11,
                      color: isFuture ? Theme.of(context).disabledColor : null)),
              if (e != null) Text(moodOf(e.mood).emoji, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
                onPressed: () => setState(
                    () => _cursor = DateTime(_cursor.year, _cursor.month - 1, 1)),
                icon: const Icon(Icons.chevron_right)),
            Text('${kMonths[month - 1]} $year',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            IconButton(
                onPressed: () => setState(
                    () => _cursor = DateTime(_cursor.year, _cursor.month + 1, 1)),
                icon: const Icon(Icons.chevron_left)),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.4,
          children: kDows
              .map((d) => Center(
                  child: Text(d, style: const TextStyle(fontSize: 10))))
              .toList(),
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: kMoods
              .map((m) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: m.color, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(m.label, style: const TextStyle(fontSize: 11)),
                  ]))
              .toList(),
        ),
        const SizedBox(height: 8),
        const Text('اضغط أي يوم سابق لتسجيله أو تعديله.',
            style: TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ------------------------- السجل والتصدير -------------------------

class HistoryTab extends StatelessWidget {
  final Store store;
  final VoidCallback onChanged;
  const HistoryTab({super.key, required this.store, required this.onChanged});

  Future<void> _export(BuildContext context, bool csv) async {
    final keys = store.entries.keys.toList()..sort();
    if (keys.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ما فيه بيانات')));
      return;
    }

    String data;
    String name;
    if (csv) {
      String esc(String s) => '"${s.replaceAll('"', '""')}"';
      final b = StringBuffer('\uFEFFdate,mood_value,mood_label,note,saved_at\n');
      for (final k in keys) {
        final e = store.entries[k]!;
        b.writeln('$k,${e.mood},${esc(moodOf(e.mood).label)},${esc(e.note)},${esc(e.savedAt)}');
      }
      data = b.toString();
      name = 'mood-log.csv';
    } else {
      data = const JsonEncoder.withIndent('  ').convert(keys
          .map((k) => {
                'date': k,
                'mood_value': store.entries[k]!.mood,
                'mood_label': moodOf(store.entries[k]!.mood).label,
                'note': store.entries[k]!.note,
                'saved_at': store.entries[k]!.savedAt,
              })
          .toList());
      name = 'mood-log.json';
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(data);
    await Share.shareXFiles([XFile(file.path)], text: 'سجل الحالة المزاجية');
  }

  @override
  Widget build(BuildContext context) {
    final keys = store.entries.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('تصدير CSV'),
                    onPressed: () => _export(context, true))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton.icon(
                    icon: const Icon(Icons.data_object),
                    label: const Text('تصدير JSON'),
                    onPressed: () => _export(context, false))),
          ]),
        ),
        Expanded(
          child: keys.isEmpty
              ? const Center(child: Text('السجل فاضي.'))
              : ListView.separated(
                  itemCount: keys.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final k = keys[i];
                    final e = store.entries[k]!;
                    final m = moodOf(e.mood);
                    return ListTile(
                      leading: Text(m.emoji, style: const TextStyle(fontSize: 26)),
                      title: Text('${prettyDate(parseKey(k))} · ${m.label}',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: e.note.isEmpty ? null : Text(e.note),
                      onTap: () async {
                        final r = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  EntryEditor(store: store, date: parseKey(k))),
                        );
                        if (r == true) onChanged();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ------------------------- الإعدادات -------------------------

class SettingsTab extends StatefulWidget {
  final Store store;
  final VoidCallback onChanged;
  const SettingsTab({super.key, required this.store, required this.onChanged});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: const Text('التذكير اليومي'),
          subtitle: const Text('إشعار يومي داخل الجهاز، يشتغل بدون إنترنت'),
          value: s.enabled,
          onChanged: (v) async {
            await s.setEnabled(v);
            if (v) {
              await requestPermissions();
              await scheduleDaily(s.hour, s.minute);
            } else {
              await cancelDaily();
            }
            setState(() {});
          },
        ),
        ListTile(
          title: const Text('وقت التذكير'),
          subtitle: Text('${two(s.hour)}:${two(s.minute)}'),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
            );
            if (t == null) return;
            await s.setTime(t.hour, t.minute);
            if (s.enabled) await scheduleDaily(t.hour, t.minute);
            setState(() {});
          },
        ),
        const Divider(),
        ListTile(
          title: const Text('إذن الإشعارات والمنبهات الدقيقة'),
          subtitle: const Text('اضغط لو ما وصلك الإشعار'),
          trailing: const Icon(Icons.notifications_active_outlined),
          onTap: () async {
            await requestPermissions();
            if (s.enabled) await scheduleDaily(s.hour, s.minute);
            if (!mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('تم تحديث الجدولة')));
          },
        ),
        ListTile(
          title: const Text('تجربة إشعار الآن'),
          trailing: const Icon(Icons.play_arrow),
          onTap: () async {
            await notifier.show(
              999,
              'كيف كان يومك؟',
              'سجّل حالتك المزاجية الآن',
              const NotificationDetails(
                android: AndroidNotificationDetails('daily_mood', 'تذكير المزاج اليومي',
                    importance: Importance.max, priority: Priority.high),
              ),
            );
          },
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'البيانات محفوظة داخل جهازك فقط. للنسخ الاحتياطي استخدم التصدير من تبويب السجل.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
