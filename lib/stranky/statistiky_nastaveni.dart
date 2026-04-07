import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'package:firebase_core/firebase_core.dart';

// Propojení k proměnným do main.dart
import '../main.dart';

// ============================================================================
// 3. ZÁLOŽKA: STATISTIKY
// ============================================================================
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final db = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'frutiqdb',
    );
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiky', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('userTrees').where('ownerId', isEqualTo: user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.park_outlined, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("Zatím tu nic není.\nPřidej svou první plodinu!", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          
          int totalPlants = 0; 
          Set<String> uniqueLocations = {}; 

          Map<String, int> speciesCount = {}; 
          Map<String, String> speciesEmoji = {}; 
          Map<String, String> speciesColorHex = {}; 

          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final species = data['species'] as String? ?? 'Neznámé';
            final location = data['locationName'] as String? ?? '';
            final int count = data['count'] ?? 1;

            final String emoji = data['emoji'] ?? '🌱';
            final String colorHex = data['color'] ?? '#4CAF50';

            speciesEmoji[species] = emoji;
            speciesColorHex[species] = colorHex;

            totalPlants += count;
            if (location.isNotEmpty) uniqueLocations.add(location);
            speciesCount[species] = (speciesCount[species] ?? 0) + count;
          }

          var sortedSpecies = speciesCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          String topSpecies = sortedSpecies.first.key;
          String topEmoji = speciesEmoji[topSpecies] ?? '🌱';

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.green.withOpacity(0.1) : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Tvou nejoblíbenější plodinou je $topSpecies $topEmoji. Tvoří ${(sortedSpecies.first.value / totalPlants * 100).toStringAsFixed(0)} % tvé zahrady.",
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.green.shade200 : Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),

              Row(
                children: [
                  Expanded(
                    child: _buildGradientStatCard(
                      "Plodin celkem", totalPlants.toString(), Icons.park, [Colors.green.shade400, Colors.green.shade700],
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildGradientStatCard(
                      "Různé lokality", uniqueLocations.length.toString(), Icons.location_on, [Colors.blue.shade400, Colors.blue.shade700],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 35),
              const Text("Zastoupení druhů", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 25),

              SizedBox(
                height: 200,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic, 
                  builder: (context, value, child) {
                    return CustomPaint(
                      painter: _DonutChartPainter(
                        speciesCount: speciesCount,
                        totalCount: totalPlants,
                        colorMapper: (species) => hexToColor(speciesColorHex[species] ?? '#4CAF50'),
                        animationValue: value,
                        isDarkMode: isDarkMode,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              (totalPlants * value).toInt().toString(), 
                              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900),
                            ),
                            Text(
                              "Kusů plodin",
                              style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 35),

              ...sortedSpecies.map((entry) {
                final species = entry.key;
                final count = entry.value;
                final percentage = count / totalPlants;
                final color = hexToColor(speciesColorHex[species] ?? '#4CAF50');
                final emoji = speciesEmoji[species] ?? '🌱';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12.0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      if (!isDarkMode) BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 12),
                      Text(emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(species, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                      Text("$count ks", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 45,
                        child: Text(
                          "${(percentage * 100).toStringAsFixed(0)}%",
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGradientStatCard(String title, String value, IconData icon, List<Color> gradientColors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: gradientColors.last.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 15),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: int.parse(value)), 
            duration: const Duration(milliseconds: 1500),
            builder: (context, val, child) {
              return Text(val.toString(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white));
            },
          ),
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

// "Malíř" našeho grafu
class _DonutChartPainter extends CustomPainter {
  final Map<String, int> speciesCount;
  final int totalCount;
  final Color Function(String) colorMapper;
  final double animationValue; 
  final bool isDarkMode;

  _DonutChartPainter({
    required this.speciesCount, required this.totalCount, required this.colorMapper, required this.animationValue, required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double strokeWidth = 25.0; 
    
    Rect rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width - strokeWidth, height: size.height - strokeWidth,
    );

    Paint bgPaint = Paint()
      ..color = isDarkMode ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(rect.center, rect.width / 2, bgPaint);

    if (totalCount == 0) return;

    double startAngle = -math.pi / 2; 

    var sortedEntries = speciesCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    for (var entry in sortedEntries) {
      double sweepAngle = (entry.value / totalCount) * 2 * math.pi * animationValue;

      Paint paint = Paint()
        ..color = colorMapper(entry.key)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round 
        ..strokeWidth = strokeWidth;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle; 
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

// ============================================================================
// 4. ZÁLOŽKA: NASTAVENÍ
// ============================================================================
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _name = '';
  String _phone = '';
  String _email = '';

  @override
  void initState() {
    super.initState();
    _loadUserProfile(); 
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _email = user.email ?? "Host"); 

      try {
        final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'frutiqdb');
        final doc = await db.collection('users').doc(user.uid).get();

        if (doc.exists && mounted) {
          setState(() {
            _name = doc.data()?['name'] ?? user.displayName ?? '';
            _phone = doc.data()?['phone'] ?? '';
          });
        }
      } catch (e) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final displayName = _name.isNotEmpty ? _name : _email;

    return Scaffold(
      appBar: AppBar(title: const Text("Nastavení")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: const Icon(Icons.person, color: Colors.green),
                ),
                const SizedBox(width: 15),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("ID: ${user?.uid.substring(0, 10)}...", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    if (_phone.isNotEmpty) Text("Tel: $_phone", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
          const Text("Preference aplikace", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(height: 10),

          ListTile(
            leading: const Icon(Icons.air, color: Colors.teal),
            title: const Text("Jednotky větru"),
            trailing: ValueListenableBuilder<String>(
              valueListenable: windUnitNotifier,
              builder: (context, currentUnit, _) {
                return DropdownButton<String>(
                  value: currentUnit,
                  underline: const SizedBox(),
                  onChanged: (val) async {
                    if (val != null) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('windUnit', val);
                      windUnitNotifier.value = val;
                    }
                  },
                  items: ['km/h', 'm/s', 'uzly'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                );
              },
            ),
          ),

          const Divider(),

          SwitchListTile(
            title: const Text("Tmavý režim"),
            secondary: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode, color: Colors.orange),
            value: isDarkMode,
            onChanged: (bool value) async {
              themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isDarkMode', value);
            },
          ),

          const SizedBox(height: 20),
          
          TextButton.icon(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text("Odhlásit se", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}