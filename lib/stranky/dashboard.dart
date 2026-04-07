import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
// Důležité: Importujeme `main.dart` kvůli globálním proměnným a `hexToColor`
import '../main.dart';
import 'encyklopedie.dart';
import 'statistiky_nastaveni.dart';
import 'detail_stromu.dart'; // <-- NOVÝ IMPORT DENÍKU

// ============================================================================
// HLAVNÍ ROZCESTNÍK APLIKACE (S NAVIGAČNÍ LIŠTOU DOLE)
// ============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0; 

  void _switchTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      OrchardPage(onNavigateToEncyclopedia: () => _switchTab(1)),
      const EncyclopediaPage(),
      const StatsPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _switchTab, 
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.park_outlined),
            selectedIcon: Icon(Icons.park),
            label: 'Moje plodiny',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Encyklopedie',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Statistiky',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Nastavení',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 1. ZÁLOŽKA: MOJE PLODINY / ZAHRADA
// ============================================================================
class OrchardPage extends StatefulWidget {
  final VoidCallback onNavigateToEncyclopedia; 
  const OrchardPage({super.key, required this.onNavigateToEncyclopedia});

  @override
  State<OrchardPage> createState() => _OrchardPageState();
}

class _OrchardPageState extends State<OrchardPage> {
  final FirebaseFirestore db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'frutiqdb',
  );

  String _formatWindSync(double windKmH) {
    final unit = windUnitNotifier.value;
    switch (unit) {
      case 'm/s':
        return "${(windKmH / 3.6).toStringAsFixed(1)} m/s";
      case 'uzly':
        return "${(windKmH * 0.539957).toStringAsFixed(1)} kt";
      default:
        return "${windKmH.toStringAsFixed(1)} km/h";
    }
  }

  String _getWeatherEmoji(int code) {
    if (code == 0) return '☀️'; 
    if (code <= 3) return '☁️'; 
    if (code <= 67) return '🌧️'; 
    if (code <= 99) return '⛈️'; 
    return '🌡️';
  }

  double _calculateSprayLiters(int count, String size) {
    double volumePerTree;
    if (size.contains('Malý')) {
      volumePerTree = 1.5;
    } else if (size.contains('Velký')) {
      volumePerTree = 5.0;
    } else {
      volumePerTree = 3.0; 
    }
    return count * volumePerTree;
  }

  Future<Map<String, dynamic>> _getWeatherForecast(double lat, double lon) async {
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&daily=temperature_2m_min,windspeed_10m_max,weathercode,precipitation_sum&timezone=auto',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body); 
        return {
          'temp': data['current_weather']['temperature'],
          'code': data['current_weather']['weathercode'],
          'wind': data['current_weather']['windspeed'],
          'min_tomorrow': (data['daily']['temperature_2m_min'][1] as num).toDouble(),
          'max_wind_tomorrow': (data['daily']['windspeed_10m_max'][1] as num).toDouble(),
          'code_tomorrow': data['daily']['weathercode'][1],
          'precipitation_today': (data['daily']['precipitation_sum'][0] as num).toDouble(),
        };
      }
    } catch (e) {} 
    
    return {
      'temp': 0.0, 'code': 0, 'wind': 0.0, 'min_tomorrow': 10.0,
      'max_wind_tomorrow': 0.0, 'code_tomorrow': 0, 'precipitation_today': 0.0,
    };
  }

  Future<Map<String, dynamic>> _calculateSUTData(double lat, double lon) async {
    final now = DateTime.now();
    final startDate = "${now.year}-01-01";
    final endDate = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    
    final url = Uri.parse(
      'https://archive-api.open-meteo.com/v1/archive?latitude=$lat&longitude=$lon&start_date=$startDate&end_date=$endDate&hourly=temperature_2m',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> temps = data['hourly']['temperature_2m'];
        final List<dynamic> times = data['hourly']['time'];
        
        double currentSut = 0.0;
        DateTime? date1200;
        
        for (int i = 0; i < temps.length; i++) {
          if (temps[i] != null && temps[i] > 7.0) {
            currentSut += (temps[i] as num).toDouble();
            if (currentSut >= 1200 && date1200 == null) {
              date1200 = DateTime.parse(times[i]);
            }
          }
        }
        return {'sut': currentSut, 'date1200': date1200};
      }
    } catch (e) {}
    return {'sut': 0.0, 'date1200': null};
  }

  void _onReorder(int oldIdx, int newIdx, List<QueryDocumentSnapshot> docs) {
    if (newIdx > oldIdx) newIdx -= 1;
    final items = List<QueryDocumentSnapshot>.from(docs);
    final movedItem = items.removeAt(oldIdx);
    items.insert(newIdx, movedItem);
    
    final batch = db.batch();
    for (int i = 0; i < items.length; i++) {
      batch.update(items[i].reference, {'index': i});
    }
    batch.commit();
  }

  void _confirmDelete(String docId, String species, String variety) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Smazat položku?"),
        content: Text("Opravdu smazat záznam: $species ($variety)?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Zrušit"),
          ),
          TextButton(
            onPressed: () {
              db.collection('userTrees').doc(docId).delete(); 
              Navigator.pop(context); 
            },
            child: const Text("Smazat", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddTreatmentDialog(String docId) {
    DateTime selectedDate = DateTime.now(); 
    final TextEditingController productCtrl = TextEditingController();
    final TextEditingController weatherCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                "Nový záznam o ošetření",
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Datum: ${selectedDate.day}. ${selectedDate.month}. ${selectedDate.year}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.calendar_today, color: Colors.green),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(DateTime.now().year - 2), 
                        lastDate: DateTime.now(), 
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: productCtrl,
                    decoration: const InputDecoration(
                      labelText: "Použitý přípravek",
                      prefixIcon: Icon(Icons.vaccines_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: weatherCtrl,
                    decoration: const InputDecoration(
                      labelText: "Počasí (např. 18°C, slunečno)",
                      prefixIcon: Icon(Icons.wb_sunny_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Zrušit", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (productCtrl.text.isEmpty) return; 

                    await db.collection('userTrees').doc(docId).update({
                      'treatmentsList': FieldValue.arrayUnion([
                        {
                          'date': Timestamp.fromDate(selectedDate),
                          'product': productCtrl.text.trim(),
                          'weather': weatherCtrl.text.trim(),
                        },
                      ]),
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text("Uložit záznam"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTreatmentsDialog(String docId, List<Map<String, dynamic>> allTreatments, Color themeColor) {
    List<Map<String, dynamic>> localTreatments = List.from(allTreatments);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20, left: 20, right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Historie ošetření",
                    style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: themeColor,
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  if (localTreatments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20.0),
                      child: Text("Zatím nebylo zaznamenáno žádné ošetření."),
                    ),
                  
                  if (localTreatments.isNotEmpty)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: localTreatments.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final t = localTreatments[i];
                          final d = (t['date'] as Timestamp).toDate();
                          
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.check_circle, color: themeColor),
                            title: Text(
                              "${d.day}. ${d.month}. ${d.year} — ${t['product']}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(
                              "Počasí: ${t['weather']}",
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
                              onPressed: () async {
                                if (t['isOld'] == true) {
                                  await db.collection('userTrees').doc(docId).update({
                                    'sprayDates': FieldValue.arrayRemove([t['raw']]),
                                  });
                                } else {
                                  await db.collection('userTrees').doc(docId).update({
                                    'treatmentsList': FieldValue.arrayRemove([t['raw']]),
                                  });
                                }
                                setModalState(() {
                                  localTreatments.removeAt(i);
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 20),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text(
                        "Přidat nové ošetření",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        Navigator.pop(context); 
                        _showAddTreatmentDialog(docId); 
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Frutiq - Zahrada',
          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: widget.onNavigateToEncyclopedia,
            icon: const Icon(Icons.add_circle_outline, color: Colors.green),
            label: const Text(
              "Přidat plodinu",
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('userTrees')
            .where('ownerId', isEqualTo: user?.uid) 
            .orderBy('index') 
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.park_outlined, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text(
                    "Zatím tu nic není.\nPřejděte do Encyklopedie a přidejte si první plodinu!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.only(top: 10, bottom: 80),
            onReorder: (oldIdx, newIdx) => _onReorder(oldIdx, newIdx, docs),
            buildDefaultDragHandles: false, 
            itemBuilder: (context, index) {
              
              final tree = docs[index].data() as Map<String, dynamic>;
              final String docId = docs[index].id;
              final String species = tree['species'] ?? '';
              final String variety = tree['variety'] ?? '';
              final int count = tree['count'] ?? 1;
              final String treeSize = tree['treeSize'] ?? 'Střední (do 5m)';

              final String emoji = tree['emoji'] ?? '🌱';
              final String colorHex = tree['color'] ?? '#4CAF50';
              
              final Color themeColor = hexToColor(colorHex);
              final Color bgColor = isDarkMode ? const Color(0xFF1E211C) : themeColor.withOpacity(0.08);

              final List<dynamic> oldDates = tree['sprayDates'] ?? [];
              final List<dynamic> newTreatments = tree['treatmentsList'] ?? [];
              List<Map<String, dynamic>> allTreatments = [];

              if (tree.containsKey('lastSprayed') && tree['lastSprayed'] != null) {
                allTreatments.add({
                  'date': tree['lastSprayed'], 'product': 'Nezadáno', 'weather': 'Nezadáno',
                  'isOld': true, 'raw': tree['lastSprayed'],
                });
              }

              for (var d in oldDates) {
                if (d is Timestamp) {
                  if (!allTreatments.any((t) => t['date'] == d)) {
                    allTreatments.add({
                      'date': d, 'product': 'Nezadáno', 'weather': 'Nezadáno',
                      'isOld': true, 'raw': d,
                    });
                  }
                }
              }

              for (var t in newTreatments) {
                if (t is Map<String, dynamic>) {
                  allTreatments.add({
                    'date': t['date'] as Timestamp, 'product': t['product'] ?? 'Nezadáno',
                    'weather': t['weather'] ?? 'Nezadáno', 'isOld': false, 'raw': t,
                  });
                }
              }

              allTreatments.sort((a, b) => (b['date'] as Timestamp).compareTo(a['date'] as Timestamp));

              // TADY JE TA ZMĚNA: Přidán GestureDetector a přesunutí ValueKey
              return GestureDetector(
                key: ValueKey(docId), // ReorderableListView potřebuje klíč tady nahoře
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TreeDetailPage(docId: docId, treeData: tree),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: themeColor.withOpacity(0.15), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(width: 6, color: themeColor),
                          
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              species, 
                                              style: TextStyle(
                                                fontSize: 20, fontWeight: FontWeight.w900, color: themeColor,
                                              ),
                                            ),
                                            Text(
                                              "$variety • $count ks ($treeSize) • ${tree['locationName']}",
                                              style: TextStyle(
                                                color: Colors.blueGrey.shade300, fontSize: 12, fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(emoji, style: const TextStyle(fontSize: 26)), 
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                                            onPressed: () => _confirmDelete(docId, species, variety),
                                          ),
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: const Icon(Icons.drag_indicator, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  FutureBuilder<List<dynamic>>(
                                    future: Future.wait([
                                      _calculateSUTData(tree['lat'], tree['lon']), 
                                      _getWeatherForecast(tree['lat'], tree['lon']), 
                                    ]),
                                    builder: (context, snap) {
                                      if (!snap.hasData) return const LinearProgressIndicator(minHeight: 2);
                                      
                                      final sutData = snap.data![0];
                                      final weather = snap.data![1];
                                      double sut = sutData['sut'];

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(_getWeatherEmoji(weather['code'])),
                                              const SizedBox(width: 5),
                                              ValueListenableBuilder<String>(
                                                valueListenable: windUnitNotifier,
                                                builder: (context, windUnit, child) {
                                                  return Text(
                                                    "${weather['temp']}°C • ${_formatWindSync((weather['wind'] as num).toDouble())} • 💧 ${weather['precipitation_today']} mm",
                                                    style: TextStyle(
                                                      fontSize: 12, color: Colors.blueGrey.shade700, fontWeight: FontWeight.bold,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                          const Divider(height: 24, thickness: 0.5),
                                          
                                          if (species == 'Broskvoň' || species == 'Meruňka') ...[
                                            _buildSutSection(
                                              sut, sutData['date1200'], weather['wind'] / 3.6, weather['code'],
                                              themeColor, species, isDarkMode, count, treeSize,
                                            ),
                                          ] else ...[
                                            _buildGeneralTreeAdvice(
                                              species, DateTime.now().month, isDarkMode, count, treeSize,
                                            ),
                                          ],

                                          _buildSprayRecordRow(docId, allTreatments, themeColor),

                                          const SizedBox(height: 16),
                                          _buildAlertSystem(weather, isDarkMode),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSprayRecordRow(String docId, List<Map<String, dynamic>> allTreatments, Color themeColor) {
    Map<String, dynamic>? lastTreatment = allTreatments.isNotEmpty ? allTreatments.first : null;
    String dateStr = "Nezaznamenáno";
    String productStr = "";

    if (lastTreatment != null) {
      DateTime date = (lastTreatment['date'] as Timestamp).toDate();
      dateStr = "${date.day}. ${date.month}. ${date.year}";
      productStr = lastTreatment['product'] != 'Nezadáno' ? " (${lastTreatment['product']})" : "";
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(Icons.vaccines_outlined, size: 16, color: Colors.blueGrey.shade400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Posl. ošetření: $dateStr$productStr",
                    style: TextStyle(
                      fontSize: 11, color: Colors.blueGrey.shade600, fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _showTreatmentsDialog(docId, allTreatments, themeColor),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Historie",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: themeColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertSystem(Map<String, dynamic> weather, bool isDarkMode) {
    double minTemp = weather['min_tomorrow'];
    double maxWind = weather['max_wind_tomorrow'];
    int code = weather['code_tomorrow'];
    List<Map<String, dynamic>> activeAlerts = [];

    if (minTemp <= 0) activeAlerts.add({'msg': 'MRAZÍK ($minTemp°C)', 'icon': Icons.ac_unit, 'color': Colors.blue});
    if (code >= 95) activeAlerts.add({'msg': 'SILNÉ BOUŘKY / KROUPY', 'icon': Icons.thunderstorm, 'color': Colors.purple});
    else if (code >= 71) activeAlerts.add({'msg': 'SNĚŽENÍ', 'icon': Icons.cloudy_snowing, 'color': Colors.blueGrey});
    else if (code >= 51) activeAlerts.add({'msg': 'VYDATNÝ DÉŠŤ', 'icon': Icons.umbrella, 'color': Colors.blue});
    if (maxWind > 45) activeAlerts.add({'msg': 'VICHŘICE (${maxWind.toStringAsFixed(0)} km/h)', 'icon': Icons.air, 'color': Colors.orange});
    else if (maxWind > 30) activeAlerts.add({'msg': 'SILNÝ VÍTR (${maxWind.toStringAsFixed(0)} km/h)', 'icon': Icons.wind_power, 'color': Colors.blueGrey});

    bool hasAlerts = activeAlerts.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasAlerts ? Colors.red.withOpacity(isDarkMode ? 0.1 : 0.05) : Colors.green.withOpacity(isDarkMode ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: hasAlerts ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasAlerts ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: hasAlerts ? Colors.red : Colors.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                hasAlerts ? "VAROVÁNÍ NA ZÍTRA" : "ZÍTRA BUDE KLID",
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w900, color: hasAlerts ? Colors.red : Colors.green,
                ),
              ),
            ],
          ),
          if (hasAlerts) ...[
            const SizedBox(height: 10),
            ...activeAlerts.map(
              (alert) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(alert['icon'], size: 14, color: alert['color']),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        alert['msg'],
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.red.shade200 : Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).toList(),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              "Předpověď nehlásí žádné extrémní jevy.",
              style: TextStyle(
                fontSize: 11, color: isDarkMode ? Colors.green.shade200 : Colors.green.shade900,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneralTreeAdvice(String species, int month, bool isDarkMode, int count, String treeSize) {
    String advice = "";
    String product = "";
    IconData icon = Icons.info_outline;
    bool isWarning = (month >= 3 && month <= 4); 

    if (month >= 3 && month <= 4) {
      if (species == 'Jabloň' || species == 'Hrušeň') {
        advice = "Období rašení: Sledujte výskyt květopasa. Při deštích hrozí strupovitost.";
        product = "Doporučeno: Bellis - boskalid, pyraklostrobin";
        icon = Icons.warning_amber_rounded;
      } else if (species.contains('řešeň') || species == 'Slivoň') {
        advice = "Před květem: Riziko moniliového úžehu při vlhku. Kontrolujte mšice.";
        product = "Doporučeno: Signum -  boskalid, pyraklostrobin";
        icon = Icons.warning_amber_rounded;
      } else {
        advice = "Začátek sezóny: Sledujte vlhkost půdy a chraňte mladé výhonky před nočním mrazem.";
      }
    } else if (month >= 5 && month <= 6) {
      advice = "Vegetační růst: Dbejte na pravidelnou zálivku a kontrolujte škůdce.";
      if (species == 'Jabloň' || species == 'Hrušeň' || species.contains('řešeň') || species == 'Slivoň') {
        product = "Doporučeno (na mšice): Sanium Ultra, Mospilan 20 SP";
      }
      icon = Icons.water_drop_outlined;
    } else {
      advice = "Pravidelná kontrola: Udržujte okolí plodiny v čistotě a sledujte její kondici.";
      icon = Icons.content_cut;
    }

    if (product.isNotEmpty) {
      double totalLiters = _calculateSprayLiters(count, treeSize);
      product += " • Odhad: ${totalLiters.toStringAsFixed(1)} l postřiku"; 
    }

    Color bgColor = isWarning ? Colors.orange.withOpacity(0.1) : (isDarkMode ? Colors.white10 : Colors.white54);
    Color borderColor = isWarning ? Colors.orange.withOpacity(0.5) : Colors.black.withOpacity(0.05);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: isWarning ? Colors.orange : Colors.blueGrey, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  advice,
                  style: TextStyle(
                    fontSize: 11, fontWeight: isWarning ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          if (product.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              product,
              style: TextStyle(
                fontSize: 10, color: isDarkMode ? Colors.orange.shade200 : Colors.green.shade700, fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSutSection(double sut, DateTime? date1200, double windMs, int weatherCode, Color themeColor, String species, bool isDarkMode, int count, String treeSize) {
    String msg = "";
    Color msgBg = Colors.blue.withOpacity(0.1);
    Color msgText = Colors.blue;
    bool isRaining = weatherCode >= 51;
    bool isDanger = false;
    String product = "";

    if (sut < 1000) {
      msg = "⏳ Do postřiku zbývá ${(1000 - sut).toStringAsFixed(0)} sut.";
    } 
    else if (sut <= 1200) {
      isDanger = true;
      if (windMs > 5.0 || isRaining) {
        msg = "⚠️ ČAS NA POSTŘIK (špatné počasí)";
        msgBg = Colors.orange.withOpacity(0.1);
        msgText = Colors.orange;
      } else {
        msg = "💦 IDEÁLNÍ ČAS NA POSTŘIK!";
        msgBg = Colors.red.withOpacity(0.1);
        msgText = Colors.red;
      }

      if (species == 'Broskvoň' || species == 'Meruňka') {
        double totalLiters = _calculateSprayLiters(count, treeSize);
        product = "Doporučeno: Champion 50 WG • Odhad: ${totalLiters.toStringAsFixed(1)} l postřiku"; 
      }
    } 
    else {
      msg = "🕙 Ideální období na postřik již proběhlo.";
      msgBg = Colors.green.withOpacity(0.1);
      msgText = Colors.green;
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Suma teplot (SAT7):",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            Text(
              "${sut.toStringAsFixed(0)} °C",
              style: TextStyle(
                color: themeColor, fontWeight: FontWeight.w900, fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: (sut / 1200).clamp(0, 1),
            minHeight: 4,
            color: themeColor,
            backgroundColor: themeColor.withOpacity(0.1),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: msgBg,
            borderRadius: BorderRadius.circular(12),
            border: isDanger ? Border.all(color: msgText.withOpacity(0.2)) : null,
          ),
          child: Column(
            children: [
              Text(
                msg,
                style: TextStyle(fontWeight: FontWeight.w900, color: msgText, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              if (product.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  product,
                  style: TextStyle(
                    fontSize: 10, color: isDarkMode ? Colors.orange.shade200 : Colors.green.shade900, fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}