import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedCountryCode = '+420'; 
  bool _isLogin = true; 
  bool _isLoading = false; 
  bool _agreedToTerms = false; 

  Future<void> _submit() async {
    setState(() => _isLoading = true); 
    
    final db = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'frutiqdb',
    );

    try {
      if (_isLogin) {
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

        final userDoc = await db
            .collection('users')
            .doc(userCredential.user?.uid)
            .get();

        if (!userDoc.exists) {
          await db.collection('users').doc(userCredential.user?.uid).set({
            'name': userCredential.user?.displayName ?? '',
            'phone': '',
            'email': _emailController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

        if (_nameController.text.trim().isNotEmpty) {
          await userCredential.user?.updateDisplayName(
            _nameController.text.trim(),
          );
          await userCredential.user?.reload();
        }

        String phoneToSave = '';
        if (_phoneController.text.trim().isNotEmpty) {
          phoneToSave = '$_selectedCountryCode ${_phoneController.text.trim()}';
        }

        await db.collection('users').doc(userCredential.user?.uid).set({
          'name': _nameController.text.trim(),
          'phone': phoneToSave,
          'email': _emailController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'agreedToTerms': true,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Chyba: ${e.toString()}")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Podmínky použití",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Zde bude brzy kompletní právní text vašich podmínek použití a zásad ochrany osobních údajů.\n\n"
                "1. Uživatel souhlasí s tím, že aplikace Frutiq slouží k osobní evidenci rostlin a stromů.\n\n"
                "2. Osobní údaje (e-mail, telefon) jsou bezpečně uloženy v databázi a nejsou předávány třetím stranám.\n",
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                label: const Text("Otevřít plné znění v PDF"),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Otevírání PDF zatím není aktivní."),
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Zavřít",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("🍑", style: TextStyle(fontSize: 80)),
              const Text(
                "Frutiq",
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.green,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                "Vaše digitální zahrada v kapse",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blueGrey.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 40),

              if (!_isLogin) ...[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Vaše jméno nebo přezdívka',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Telefonní číslo',
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    prefixIcon: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCountryCode,
                          icon: const Icon(Icons.arrow_drop_down, size: 20),
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedCountryCode = newValue;
                              });
                            }
                          },
                          items: <String>['+420', '+421', '+49', '+43', '+48']
                              .map<DropdownMenuItem<String>>((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              })
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
              ],

              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Heslo',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                obscureText: true, 
              ),

              if (!_isLogin) ...[
                const SizedBox(height: 15),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _agreedToTerms,
                        activeColor: Colors.green,
                        onChanged: (bool? value) {
                          setState(() {
                            _agreedToTerms = value ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _showTermsDialog,
                        child: RichText(
                          text: TextSpan(
                            text: "Souhlasím s ",
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.grey.shade400
                                      : Colors.blueGrey.shade700,
                              fontFamily: 'Roboto',
                            ),
                            children: const [
                              TextSpan(
                                text: "podmínkami použití",
                                style: TextStyle(
                                  color: Colors.green,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(text: " a "),
                              TextSpan(
                                text: "zpracováním osobních údajů.",
                                style: TextStyle(
                                  color: Colors.green,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 25),
              
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.green.shade200,
                  ),
                  onPressed: _isLoading || (!_isLogin && !_agreedToTerms)
                      ? null
                      : _submit,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isLogin ? "Vstoupit do aplikace" : "Vytvořit účet",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _agreedToTerms = false; 
                  });
                },
                child: Text(_isLogin ? "Registrace" : "Přihlášení"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}