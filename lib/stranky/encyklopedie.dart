import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
// Import spojení na main.dart kvůli převodu barvy hexToColor
import '../main.dart';

// ============================================================================
// 2. ZÁLOŽKA: ENCYKLOPEDIE
// ============================================================================
class EncyclopediaPage extends StatefulWidget {
  const EncyclopediaPage({super.key});
  @override
  State<EncyclopediaPage> createState() => _EncyclopediaPageState();
}

class _EncyclopediaPageState extends State<EncyclopediaPage> {
  final FirebaseFirestore db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'frutiqdb',
  );

  String _selectedCategory = 'Vše'; 

  String _formatAddress(Map<String, dynamic> loc) {
    final String displayName = loc['display_name'] ?? "";
    final parts = displayName.split(', ');
    if (parts.isEmpty) return "Neznámá lokalita";
    String city = parts[0];
    String district = "";
    for (var part in parts) {
      if (part.toLowerCase().contains("okres")) {
        district = part;
        break;
      }
    }
    return district.isNotEmpty ? "$city ($district)" : city;
  }

  void _showAddDialogFromEncyclopedia(String species, List<dynamic> varieties, int currentCount, String emoji, String colorHex) {
    String selectedVariety = varieties.isNotEmpty ? varieties[0].toString() : "";
    String selectedSize = 'Střední (do 5m)';
    final List<String> sizes = ['Malý (do 3m)', 'Střední (do 5m)', 'Velký (nad 5m)'];

    final TextEditingController searchController = TextEditingController();
    final TextEditingController countController = TextEditingController(text: '1');
    
    List<dynamic> searchResults = []; 
    Map<String, dynamic>? selectedLoc; 
    Timer? debounce; 

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 20, left: 25, right: 25,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Sledovat plodinu",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Text(
                  "$emoji $species",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 15),

              if (varieties.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: selectedVariety,
                  decoration: const InputDecoration(labelText: "Odrůda", border: OutlineInputBorder()),
                  items: varieties.map((v) => DropdownMenuItem(value: v.toString(), child: Text(v.toString()))).toList(),
                  onChanged: (val) => setDS(() => selectedVariety = val!),
                ),
              const SizedBox(height: 15),

              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Kusů", border: OutlineInputBorder(), prefixIcon: Icon(Icons.numbers)),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: selectedSize,
                      decoration: const InputDecoration(labelText: "Velikost", border: OutlineInputBorder()),
                      items: sizes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (val) => setDS(() => selectedSize = val!),
                      isExpanded: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),

              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: "Vyhledat lokalitu (obec)",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: (selectedLoc != null || searchController.text.isNotEmpty)
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setDS(() {
                              selectedLoc = null; 
                              searchController.clear();
                              searchResults = [];
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (v) {
                  if (debounce?.isActive ?? false) debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 600), () async {
                    if (v.length > 2 && selectedLoc == null) {
                      try {
                        final res = await http.get(
                          Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(v)}&format=json&limit=5&countrycodes=cz'),
                          headers: {'User-Agent': 'FrutiqApp/1.0'}, 
                        );
                        if (res.statusCode == 200) {
                          setDS(() => searchResults = json.decode(res.body));
                        }
                      } catch (e) {}
                    } else if (v.isEmpty) {
                      setDS(() => searchResults = []);
                    }
                  });
                },
              ),
              
              if (searchResults.isNotEmpty && selectedLoc == null)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: searchResults.map(
                          (loc) => ListTile(
                            dense: true,
                            title: Text(_formatAddress(loc)),
                            onTap: () => setDS(() {
                              selectedLoc = loc; 
                              searchController.text = _formatAddress(loc);
                              searchResults = []; 
                            }),
                          ),
                        ).toList(),
                  ),
                ),
              const SizedBox(height: 25),
              
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: selectedLoc == null
                      ? null 
                      : () async {
                          int count = int.tryParse(countController.text) ?? 1;
                          if (count < 1) count = 1;

                          await db.collection('userTrees').add({
                            'species': species,
                            'variety': selectedVariety,
                            'count': count,
                            'treeSize': selectedSize,
                            'locationName': searchController.text,
                            'lat': double.parse(selectedLoc!['lat']),
                            'lon': double.parse(selectedLoc!['lon']),
                            'ownerId': FirebaseAuth.instance.currentUser!.uid, 
                            'index': currentCount, 
                            'emoji': emoji, 
                            'color': colorHex, 
                          });
                          Navigator.pop(context); 
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Úspěšně přidáno ke sledování!")),
                          );
                        },
                  child: const Text("Uložit záznam", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAddPress(String species, List<dynamic> varieties, String emoji, String colorHex) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await db.collection('userTrees').where('ownerId', isEqualTo: user.uid).get();
    _showAddDialogFromEncyclopedia(species, varieties, snap.docs.length, emoji, colorHex);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encyklopedie', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.green)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('catalogTrees').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.menu_book_outlined, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("Katalog plodin je prázdný.", style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                ],
              ),
            );
          }

          Set<String> categoriesSet = {'Vše'};
          for (var d in docs) {
            final data = d.data() as Map<String, dynamic>;
            final String cat = data['kategorie'] ?? 'Ostatní';
            categoriesSet.add(cat);
          }
          List<String> categories = categoriesSet.toList();
          categories.sort(); 

          var filteredDocs = docs.where((d) {
            if (_selectedCategory == 'Vše') return true;
            final data = d.data() as Map<String, dynamic>;
            final String cat = data['kategorie'] ?? 'Ostatní';
            return cat == _selectedCategory;
          }).toList();

          return Column(
            children: [
              Container(
                height: 50,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final isSelected = cat == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(
                          cat,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.green.shade900 : (isDarkMode ? Colors.white : Colors.black),
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.green.withOpacity(0.3),
                        backgroundColor: isDarkMode ? Colors.white10 : Colors.grey.shade200,
                        side: BorderSide.none,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedCategory = cat);
                        },
                      ),
                    );
                  },
                ),
              ),

              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(child: Text("V této kategorii zatím nic není.", style: TextStyle(color: Colors.grey.shade500)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          final String species = filteredDocs[index].id;
                          final Map<String, dynamic> data = filteredDocs[index].data() as Map<String, dynamic>;
                          final List<dynamic> varieties = data['odrudy'] ?? [];

                          final String emoji = data['emoji'] ?? '🌱';
                          final String colorHex = data['color'] ?? '#4CAF50';
                          final Color themeColor = hexToColor(colorHex);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            elevation: 2,
                            shadowColor: Colors.black.withOpacity(0.1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(emoji, style: const TextStyle(fontSize: 32)),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              species,
                                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: themeColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (varieties.isNotEmpty) ...[
                                        const Divider(height: 24),
                                        const Text("Dostupné odrůdy:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8, runSpacing: 8,
                                          children: varieties.map(
                                                (v) => Chip(
                                                  label: Text(v.toString(), style: const TextStyle(fontSize: 12)),
                                                  backgroundColor: themeColor.withOpacity(0.1),
                                                  side: BorderSide.none, padding: EdgeInsets.zero,
                                                ),
                                              ).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const Divider(height: 1, thickness: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => _handleAddPress(species, varieties, emoji, colorHex),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: themeColor,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text("Sledovat plodinu", style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}