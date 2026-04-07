import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../main.dart';
import 'package:firebase_core/firebase_core.dart';

class TreeDetailPage extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> treeData;

  const TreeDetailPage({super.key, required this.docId, required this.treeData});

  @override
  State<TreeDetailPage> createState() => _TreeDetailPageState();
}

class _TreeDetailPageState extends State<TreeDetailPage> {
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;
  bool _isUploading = false;
  String? _imageUrl; 

  @override
  void initState() {
    super.initState();
    _notesController.text = widget.treeData['notes'] ?? '';
    _imageUrl = widget.treeData['imageUrl']; 
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery, 
      maxWidth: 1024, 
      imageQuality: 80,
    );

    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('stromy_fotky')
          .child(user!.uid)
          .child('${widget.docId}.jpg');

      await storageRef.putFile(File(image.path));
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'frutiqdb',
      ).collection('userTrees').doc(widget.docId).update({
        'imageUrl': downloadUrl,
      });

      setState(() {
        _imageUrl = downloadUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Fotka byla úspěšně nahrána")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Chyba při nahrávání: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveNotes() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'frutiqdb',
      ).collection('userTrees').doc(widget.docId).update({
        'notes': _notesController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Poznámky uloženy")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Chyba při ukládání: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String species = widget.treeData['species'] ?? 'Neznámé';
    final String variety = widget.treeData['variety'] ?? '';
    final String emoji = widget.treeData['emoji'] ?? '🌱';
    final Color themeColor = hexToColor(widget.treeData['color'] ?? '#4CAF50');
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Příprava seznamu ošetření z databáze
    final List<dynamic> oldDates = widget.treeData['sprayDates'] ?? [];
    final List<dynamic> newTreatments = widget.treeData['treatmentsList'] ?? [];
    List<Map<String, dynamic>> allTreatments = [];
    
    if (widget.treeData.containsKey('lastSprayed') && widget.treeData['lastSprayed'] != null) {
      allTreatments.add({'date': widget.treeData['lastSprayed'], 'product': 'Nezadáno'});
    }
    for (var d in oldDates) {
      if (d is Timestamp) allTreatments.add({'date': d, 'product': 'Nezadáno'});
    }
    for (var t in newTreatments) {
      if (t is Map<String, dynamic>) {
        allTreatments.add({'date': t['date'] as Timestamp, 'product': t['product'] ?? 'Nezadáno'});
      }
    }
    // Seřadíme od nejnovějšího po nejstarší
    allTreatments.sort((a, b) => (b['date'] as Timestamp).compareTo(a['date'] as Timestamp));

    return Scaffold(
      appBar: AppBar(
        title: Text(species, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // FOTKA NEBO EMOJI
            Center(
              child: GestureDetector(
                onTap: _isUploading ? null : _pickAndUploadImage,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                        image: _imageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(_imageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _imageUrl == null
                          ? Center(child: Text(emoji, style: const TextStyle(fontSize: 60)))
                          : null,
                    ),
                    if (_isUploading)
                      const CircularProgressIndicator()
                    else
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          backgroundColor: themeColor,
                          radius: 18,
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                variety,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: themeColor),
              ),
            ),
            Center(
              child: Text(
                "${widget.treeData['locationName']} • ${widget.treeData['count']} ks",
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            
            const SizedBox(height: 40),
            
            // POZNÁMKY
            const Text("📝 Poznámky pěstitele", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: "Sem si pište zkušenosti s úrodou, škůdci nebo růstem...",
                fillColor: isDarkMode ? Colors.white10 : Colors.white,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveNotes,
                icon: _isSaving 
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : const Icon(Icons.save),
                label: const Text("Uložit poznámky"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            
            // ČASOVÁ OSA OŠETŘENÍ (Která omylem zmizela)
            const Text("📅 Časová osa ošetření", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            if (allTreatments.isEmpty)
              const Text("Zatím žádné záznamy o ošetření.", style: TextStyle(color: Colors.grey))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: allTreatments.length,
                itemBuilder: (context, index) {
                  final t = allTreatments[index];
                  final DateTime d = (t['date'] as Timestamp).toDate();
                  return Row(
                    children: [
                      Column(
                        children: [
                          Container(width: 2, height: 20, color: index == 0 ? Colors.transparent : Colors.grey.shade300),
                          Icon(Icons.circle, size: 12, color: themeColor),
                          Container(width: 2, height: 20, color: index == allTreatments.length - 1 ? Colors.transparent : Colors.grey.shade300),
                        ],
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          "${d.day}. ${d.month}. ${d.year} — ${t['product']}",
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}