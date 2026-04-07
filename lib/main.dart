import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:desktop_window/desktop_window.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// GLOBÁLNÍ PROMĚNNÉ A POMOCNÉ FUNKCE
// Tyto proměnné jsou dostupné z celé aplikace. ValueNotifier funguje jako
// takový "vysílač" - když se jeho hodnota změní, aplikace to hned pozná a překreslí se.
// ============================================================================
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<String> windUnitNotifier = ValueNotifier('km/h');

// Tato funkce vezme textový kód barvy (např. "#EF5350") a převede ho na formát,
// kterému rozumí Flutter (objekt typu Color).
Color hexToColor(String hexString) {
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff'); // Přidá plnou neprůhlednost (alpha kanál)
  buffer.write(hexString.replaceFirst('#', '')); // Odstraní křížek, pokud tam je
  return Color(int.parse(buffer.toString(), radix: 16));
}

// ============================================================================
// HLAVNÍ FUNKCE APLIKACE (BOD VSTUPU)
// Zde celá aplikace začíná, když na ni uživatel klikne v telefonu.
// ============================================================================
void main() async {
  // Zajišťuje, že všechny nástroje Flutteru jsou připravené, než spustíme zbytek
  WidgetsFlutterBinding.ensureInitialized();
  
  // Připojení naší aplikace k Firebase (databáze a přihlašování)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --- Načtení uživatelského nastavení z paměti telefonu ---
  // SharedPreferences je malé úložiště přímo v mobilu (nepotřebuje internet).
  final prefs = await SharedPreferences.getInstance();
  
  // Zjistíme, jestli měl uživatel minule zapnutý tmavý režim
  final isDark = prefs.getBool('isDarkMode') ?? false; 
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  
  // Zjistíme, jaké jednotky větru měl uživatel minule nastavené (výchozí jsou km/h)
  windUnitNotifier.value = prefs.getString('windUnit') ?? 'km/h';

  // Pokud aplikaci spouštíme na počítači, nastavíme velikost okna tak, aby připomínalo mobil
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await DesktopWindow.setWindowSize(const Size(375, 812));
    await DesktopWindow.setMinWindowSize(const Size(375, 812));
  }
  
  // Spustí samotné uživatelské rozhraní
  runApp(const MyApp());
}

// ============================================================================
// ZÁKLADNÍ NASTAVENÍ VZHLEDU APLIKACE (MyApp)
// ============================================================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder "poslouchá" naše globální proměnné.
    // Když se změní téma (světlé/tmavé), překreslí aplikaci.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return ValueListenableBuilder<String>(
          valueListenable: windUnitNotifier,
          builder: (_, windUnit, ___) {
            return MaterialApp(
              debugShowCheckedModeBanner: false, // Skryje červený nápis "DEBUG" vpravo nahoře
              themeMode: mode, // Aktuálně zvolený režim (světlý vs tmavý)
              
              // --- Jak vypadá aplikace ve světlém režimu ---
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.green, // Hlavní barva aplikace je zelená
                  brightness: Brightness.light,
                ),
                useMaterial3: true, // Moderní vzhled prvků (Google Material 3)
                scaffoldBackgroundColor: const Color(0xFFF4F6F2), // Lehce našedlé pozadí
              ),
              
              // --- Jak vypadá aplikace v tmavém režimu ---
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.green,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
                scaffoldBackgroundColor: const Color(0xFF121411), // Téměř černé pozadí
              ),
              
              // První obrazovka, na kterou uživatel narazí
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// HLÍDAČ PŘIHLÁŠENÍ (AuthGate)
// ============================================================================
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  
  @override
  Widget build(BuildContext context) {
    // StreamBuilder neustále hlídá, jestli je uživatel přihlášený k Firebase
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Pokud Firebase říká "Ano, je přihlášen", pustíme ho rovnou do aplikace (Dashboard)
        if (snapshot.hasData) return const DashboardScreen();
        // Pokud není, ukážeme mu přihlašovací obrazovku
        return const LoginScreen();
      },
    );
  }
}

// ============================================================================
// PŘIHLAŠOVACÍ A REGISTRAČNÍ OBRAZOVKA (LoginScreen)
// ============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Ovladače textových polí - pamatují si, co uživatel napsal
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedCountryCode = '+420'; // Výchozí předvolba pro Česko
  bool _isLogin = true; // Přepínač: True = Přihlašování, False = Registrace
  bool _isLoading = false; // Pokud se zrovna něco odesílá na server, ukážeme načítací kolečko
  bool _agreedToTerms = false; // Zda uživatel zaškrtl souhlas s podmínkami

  // Funkce, která se zavolá po kliknutí na hlavní tlačítko
  Future<void> _submit() async {
    setState(() => _isLoading = true); // Zapneme načítání
    
    // Připojení do naší konkrétní databáze v cloudu
    final db = FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'frutiqdb',
    );

    try {
      if (_isLogin) {
        // --- PROCES PŘIHLÁŠENÍ ---
        // Zkusíme uživatele přihlásit pomocí emailu a hesla
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

        // Zkontrolujeme, jestli má uživatel záznam v naší databázi (kolekce 'users')
        final userDoc = await db
            .collection('users')
            .doc(userCredential.user?.uid)
            .get();

        // Pokud záznam nemá (např. starší účet), tak mu ho teď vytvoříme
        if (!userDoc.exists) {
          await db.collection('users').doc(userCredential.user?.uid).set({
            'name': userCredential.user?.displayName ?? '',
            'phone': '',
            'email': _emailController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        // --- PROCES REGISTRACE ---
        // Vytvoříme nového uživatele ve Firebase Auth
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

        // Pokud vyplnil jméno, nastavíme mu ho do profilu
        if (_nameController.text.trim().isNotEmpty) {
          await userCredential.user?.updateDisplayName(
            _nameController.text.trim(),
          );
          await userCredential.user?.reload();
        }

        // Dáme dohromady předvolbu a číslo (např. "+420 123456789")
        String phoneToSave = '';
        if (_phoneController.text.trim().isNotEmpty) {
          phoneToSave = '$_selectedCountryCode ${_phoneController.text.trim()}';
        }

        // Uložíme všechny detaily o uživateli do naší databáze 'users'
        await db.collection('users').doc(userCredential.user?.uid).set({
          'name': _nameController.text.trim(),
          'phone': phoneToSave,
          'email': _emailController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'agreedToTerms': true,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      // Pokud se stane chyba (např. špatné heslo, existující email), ukážeme upozornění dole na obrazovce
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Chyba: ${e.toString()}")));
      }
    } finally {
      // Ať už to dopadlo jakkoliv, vypneme načítací kolečko
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Dialog (okno), které vyskočí, když uživatel klikne na "Podmínkami použití"
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
              // Logo a název
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

              // Pokud je uživatel v režimu REGISTRACE (ne přihlašování), ukážeme mu navíc políčka Jméno a Telefon
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

                // Pole pro telefon s rozbalovacím seznamem pro předvolbu země
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

              // Políčka pro Email a Heslo se ukazují vždy (při registraci i přihlášení)
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
                obscureText: true, // Skryje napsaný text (nahradí hvězdičkami/tečkami)
              ),

              // Checkbox se souhlasem s podmínkami - pouze při registraci
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
              
              // Hlavní potvrzovací tlačítko (Vstoupit / Vytvořit účet)
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
                  // Tlačítko je neklikatelné (null), pokud se zrovna něco načítá, 
                  // nebo pokud se uživatel registruje, ale nezaškrtl podmínky
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
              
              // Přepínání mezi přihlášením a registrací
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _agreedToTerms = false; // Při přepnutí vyresetujeme zaškrtávátko
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

// ============================================================================
// HLAVNÍ ROZCESTNÍK APLIKACE (S NAVIGAČNÍ LIŠTOU DOLE)
// ============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0; // Která záložka je zrovna otevřená (0 = první, Zahrada)

  // Přepínání záložek
  void _switchTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Seznam všech 4 hlavních obrazovek
    final List<Widget> pages = [
      // Zahrada má speciální funkci - když klikneš na "Přidat", pošle tě to na záložku 1 (Encyklopedie)
      OrchardPage(onNavigateToEncyclopedia: () => _switchTab(1)),
      const EncyclopediaPage(),
      const StatsPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      // IndexedStack zaručí, že když přepneš záložku a pak se vrátíš, stránka zůstane tak, jak jsi ji opustil
      body: IndexedStack(index: _selectedIndex, children: pages),
      
      // Spodní navigační lišta
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _switchTab, // Spustí se při kliknutí na ikonku
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
// Zde uživatel vidí seznam svých stromů, úkolů, počasí a může zaznamenávat postřiky.
// ============================================================================
class OrchardPage extends StatefulWidget {
  final VoidCallback onNavigateToEncyclopedia; // Funkce pro přeskok do encyklopedie
  const OrchardPage({super.key, required this.onNavigateToEncyclopedia});

  @override
  State<OrchardPage> createState() => _OrchardPageState();
}

class _OrchardPageState extends State<OrchardPage> {
  // Propojení na konkrétní tabulku databáze v cloudu
  final FirebaseFirestore db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'frutiqdb',
  );

  // --- Pomocné funkce pro formátování a výpočty ---
  
  // Převede rychlost větru podle toho, co si uživatel vybral v nastavení
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

  // Přiřadí emoji sluníčka/mráčku podle meteorologického kódu (WMO)
  String _getWeatherEmoji(int code) {
    if (code == 0) return '☀️'; // Čisto
    if (code <= 3) return '☁️'; // Oblačno
    if (code <= 67) return '🌧️'; // Déšť
    if (code <= 99) return '⛈️'; // Bouřky/Kroupy
    return '🌡️';
  }

  // Vypočítá odhad, kolik litrů postřiku bude potřeba (podle počtu stromů a velikosti)
  double _calculateSprayLiters(int count, String size) {
    double volumePerTree;
    if (size.contains('Malý')) {
      volumePerTree = 1.5;
    } else if (size.contains('Velký')) {
      volumePerTree = 5.0;
    } else {
      volumePerTree = 3.0; // Střední
    }
    return count * volumePerTree;
  }

  // Odstřihne přesnou adresu a nechá jen Město/Okres
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

  // --- STAHOVÁNÍ DAT Z INTERNETU ---
  
  // Funkce se ptá serveru Open-Meteo na aktuální počasí a předpověď na zítra
  // Přidáno: precipitation_sum pro úhrn srážek!
  Future<Map<String, dynamic>> _getWeatherForecast(double lat, double lon) async {
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&daily=temperature_2m_min,windspeed_10m_max,weathercode,precipitation_sum&timezone=auto',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body); // Převedeme textovou odpověď do tabulky dat
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
    } catch (e) {} // Pokud spadne internet, zachytí to chybu
    
    // Pokud selže načtení, pošleme aspoň nějaká "prázdná" data, aby aplikace nespadla
    return {
      'temp': 0.0, 'code': 0, 'wind': 0.0, 'min_tomorrow': 10.0,
      'max_wind_tomorrow': 0.0, 'code_tomorrow': 0, 'precipitation_today': 0.0,
    };
  }

  // Počítá "Sumu aktivních teplot" (SUT) od 1. ledna aktuálního roku (např. klíčové pro postřik broskvoní)
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
        
        // Jdeme hodinu po hodině. Pokud byla teplota nad 7°C, přičteme ji k celkové sumě
        for (int i = 0; i < temps.length; i++) {
          if (temps[i] != null && temps[i] > 7.0) {
            currentSut += (temps[i] as num).toDouble();
            // Poznamenáme si, kdy suma přesáhla hraničních 1200°C
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

  // --- OVLÁDÁNÍ UŽIVATELSKÉHO ROZHRANÍ ---

  // Funkce, která se postará o přeskupení položek (když táhneš prstem seznam)
  void _onReorder(int oldIdx, int newIdx, List<QueryDocumentSnapshot> docs) {
    if (newIdx > oldIdx) newIdx -= 1;
    final items = List<QueryDocumentSnapshot>.from(docs);
    final movedItem = items.removeAt(oldIdx);
    items.insert(newIdx, movedItem);
    
    // Batch commit znamená, že uložíme změnu pořadí (indexy) všech stromů do Firebase najednou (je to rychlejší)
    final batch = db.batch();
    for (int i = 0; i < items.length; i++) {
      batch.update(items[i].reference, {'index': i});
    }
    batch.commit();
  }

  // Vyskakovací okno pro potvrzení, zda opravdu chceme strom smazat
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
              db.collection('userTrees').doc(docId).delete(); // Smaže záznam v databázi
              Navigator.pop(context); // Zavře dialogové okno
            },
            child: const Text("Smazat", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Dialog na přidání nového záznamu o ošetření (datum, přípravek, počasí)
  void _showAddTreatmentDialog(String docId) {
    DateTime selectedDate = DateTime.now(); // Výchozí je dnešek
    final TextEditingController productCtrl = TextEditingController();
    final TextEditingController weatherCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        // StatefulBuilder nám umožňuje měnit data uvnitř otevřeného dialogu (např. vybrané datum)
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
                  // Výběr data
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      "Datum: ${selectedDate.day}. ${selectedDate.month}. ${selectedDate.year}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.calendar_today, color: Colors.green),
                    onTap: () async {
                      // Otevře systémový kalendář telefonu
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(DateTime.now().year - 2), // Lze jít 2 roky zpět
                        lastDate: DateTime.now(), // Nelze zadat datum v budoucnosti
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  // Textové pole: Název přípravku
                  TextField(
                    controller: productCtrl,
                    decoration: const InputDecoration(
                      labelText: "Použitý přípravek",
                      prefixIcon: Icon(Icons.vaccines_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  // Textové pole: Poznámka o počasí
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
                    if (productCtrl.text.isEmpty) return; // Zabránění uložení prázdného pole

                    // Uložíme do databáze jako pole (array) 'treatmentsList'
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

  // "Šuplík", který vyjede zespodu (BottomSheet) a zobrazí celou historii postřiků konkrétního stromu
  void _showTreatmentsDialog(String docId, List<Map<String, dynamic>> allTreatments, Color themeColor) {
    List<Map<String, dynamic>> localTreatments = List.from(allTreatments);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Šuplík může vyjet výš než do půlky obrazovky
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                // viewInsets.bottom zajišťuje, že když vyskočí klávesnice, okno se zvedne nad ní
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
                  
                  // Pokud je historie prázdná, zobrazí hlášku
                  if (localTreatments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20.0),
                      child: Text("Zatím nebylo zaznamenáno žádné ošetření."),
                    ),
                  
                  // Vypsání historie záznamů s možností smazání
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
                            // Ikonka koše pro smazání konkrétního záznamu v historii
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
                              onPressed: () async {
                                // Kompatibilita se starými záznamy (arrayRemove)
                                if (t['isOld'] == true) {
                                  await db.collection('userTrees').doc(docId).update({
                                    'sprayDates': FieldValue.arrayRemove([t['raw']]),
                                  });
                                } else {
                                  await db.collection('userTrees').doc(docId).update({
                                    'treatmentsList': FieldValue.arrayRemove([t['raw']]),
                                  });
                                }
                                // Aktualizujeme zobrazení po smazání
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
                  
                  // Tlačítko pro přidání nového záznamu přímo odsud
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
                        Navigator.pop(context); // Zavře šuplík
                        _showAddTreatmentDialog(docId); // Otevře dialog přidání
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

  // --- VYKRESLENÍ CELÉ STRÁNKY ZAHRADY ---
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
          // Tlačítko vpravo nahoře, které přepne uživatele do Encyklopedie
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
      
      // StreamBuilder naslouchá databázi Firebase
      // Kdykoliv tam něco přibude nebo ubyde, okamžitě to na obrazovce překreslí
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('userTrees')
            .where('ownerId', isEqualTo: user?.uid) // Filtruje jen stromy aktuálně přihlášeného uživatele
            .orderBy('index') // Řadí je podle toho, jak si je uživatel seřadil (drag & drop)
            .snapshots(),
        builder: (context, snapshot) {
          // Pokud data ještě nedorazila, zobrazíme kolečko načítání
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs;

          // Zahrada je prázdná (uživatel si ještě nic nepřidal)
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

          // Vykreslíme seznam karet stromů. "ReorderableListView" umožňuje tažení (Drag & Drop) položek.
          return ReorderableListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.only(top: 10, bottom: 80),
            onReorder: (oldIdx, newIdx) => _onReorder(oldIdx, newIdx, docs),
            buildDefaultDragHandles: false, // Vypneme původní "držátka", abychom si udělali vlastní
            itemBuilder: (context, index) {
              
              // Vytáhneme si data pro konkrétní jeden strom v seznamu
              final tree = docs[index].data() as Map<String, dynamic>;
              final String docId = docs[index].id;
              final String species = tree['species'] ?? '';
              final String variety = tree['variety'] ?? '';
              final int count = tree['count'] ?? 1;
              final String treeSize = tree['treeSize'] ?? 'Střední (do 5m)';

              // Výchozí hodnoty (kdyby náhodou chyběly v databázi)
              final String emoji = tree['emoji'] ?? '🌱';
              final String colorHex = tree['color'] ?? '#4CAF50';
              
              final Color themeColor = hexToColor(colorHex);
              final Color bgColor = isDarkMode ? const Color(0xFF1E211C) : themeColor.withOpacity(0.08);

              // Tady skládáme všechny ošetření dohromady (i staré způsoby ukládání dat s novými)
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

              // Seřadíme historii podle data (nejnovější nahoře)
              allTreatments.sort((a, b) => (b['date'] as Timestamp).compareTo(a['date'] as Timestamp));

              // Vykreslení konkrétní KARTY PRO JEDEN STROM
              return Container(
                key: ValueKey(docId), // Důležité pro přeskupování!
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
                        // Levý barevný proužek značící barvu plodiny
                        Container(width: 6, color: themeColor),
                        
                        // Obsah karty
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                
                                // HORNÍ ČÁST: Název, odrůda a ikonky akcí
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            species, // Název (např. Jabloň)
                                            style: TextStyle(
                                              fontSize: 20, fontWeight: FontWeight.w900, color: themeColor,
                                            ),
                                          ),
                                          Text(
                                            // Doplňující info: Odrůda • ks • velikost • lokalita
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
                                        Text(emoji, style: const TextStyle(fontSize: 26)), // Emoji plodiny
                                        const SizedBox(width: 8),
                                        // Ikonka koše (Smazat)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                                          onPressed: () => _confirmDelete(docId, species, variety),
                                        ),
                                        // Tzv. "držátko" na přesunutí (přetažení nahoru/dolů)
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: const Icon(Icons.drag_indicator, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                
                                // DYNAMICKÁ ČÁST: Počasí a rady
                                // FutureBuilder pošle dotaz na internet a počká na odpověď
                                FutureBuilder<List<dynamic>>(
                                  future: Future.wait([
                                    _calculateSUTData(tree['lat'], tree['lon']), // SUT výpočet
                                    _getWeatherForecast(tree['lat'], tree['lon']), // Předpověď počasí
                                  ]),
                                  builder: (context, snap) {
                                    // Během čekání ukážeme čárový nakládací progress bar
                                    if (!snap.hasData) return const LinearProgressIndicator(minHeight: 2);
                                    
                                    // Data dorazila, vybalíme si je
                                    final sutData = snap.data![0];
                                    final weather = snap.data![1];
                                    double sut = sutData['sut'];

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Zobrazení aktuálního počasí pro daný strom
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
                                        
                                        // ROZDĚLENÍ LOGIKY:
                                        // Pokud je to Broskvoň nebo Meruňka, ukážeme specialitu (SUT graf = Kadeřavost).
                                        // Pro ostatní ukážeme jen obecné rady podle měsíce.
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

                                        // Řádek, který ukazuje poslední datum a čas postřiku a tlačítko Historie
                                        _buildSprayRecordRow(docId, allTreatments, themeColor),

                                        const SizedBox(height: 16),
                                        // Sekce, která upozorňuje na blížící se kroupy, sníh, mrazy atd.
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
              );
            },
          );
        },
      ),
    );
  }

  // Poslední ošetření a možnost kliknout na Historii
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

  // Zobrazuje varování, pokud bude zítra klesat teplota pod bod mrazu nebo pokud bude vichřice.
  Widget _buildAlertSystem(Map<String, dynamic> weather, bool isDarkMode) {
    double minTemp = weather['min_tomorrow'];
    double maxWind = weather['max_wind_tomorrow'];
    int code = weather['code_tomorrow'];
    List<Map<String, dynamic>> activeAlerts = [];

    // Logika varování - přidává jednotlivá varování do seznamu
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
          // Pokud je nějaké varování, vypíšeme všechny ze seznamu pod sebe
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

  // Tuto "kartičku" vidí uživatel pro jablka, hrušky, atd. (vše kromě broskví)
  Widget _buildGeneralTreeAdvice(String species, int month, bool isDarkMode, int count, String treeSize) {
    String advice = "";
    String product = "";
    IconData icon = Icons.info_outline;
    bool isWarning = (month >= 3 && month <= 4); // Březen a Duben jsou kritické pro ošetření

    // Logika doporučení podle aktuálního měsíce
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

    // Barevné odlišení varování
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

  // Exkluzivně pro Broskvoně a Meruňky - Graf průběhu sumy aktivních teplot proti Kadeřavosti
  Widget _buildSutSection(double sut, DateTime? date1200, double windMs, int weatherCode, Color themeColor, String species, bool isDarkMode, int count, String treeSize) {
    String msg = "";
    Color msgBg = Colors.blue.withOpacity(0.1);
    Color msgText = Colors.blue;
    bool isRaining = weatherCode >= 51;
    bool isDanger = false;
    String product = "";

    // Do 1000 stupňů: Jen to sbírá
    if (sut < 1000) {
      msg = "⏳ Do postřiku zbývá ${(1000 - sut).toStringAsFixed(0)} sut.";
    } 
    // Okno ideálního postřiku (1000-1200) - dává pozor na silný vítr nebo déšť (kdy se nesmí stříkat)
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
    // Po překročení 1200 už je většinou na prevenci kadeřavosti pozdě (pupeny pukly)
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
        // Ukazatel toho, jak jsme blízko (od 0 do 1) k cílovým 1200.
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

// ============================================================================
// 2. ZÁLOŽKA: ENCYKLOPEDIE
// Zobrazuje všechny plodiny napojené přímo z databáze a umožňuje jejich sledování.
// ============================================================================
class EncyclopediaPage extends StatefulWidget {
  const EncyclopediaPage({super.key});
  @override
  State<EncyclopediaPage> createState() => _EncyclopediaPageState();
}

class _EncyclopediaPageState extends State<EncyclopediaPage> {
  // Propojení k naší databázi Frutiq
  final FirebaseFirestore db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'frutiqdb',
  );

  String _selectedCategory = 'Vše'; // Výchozí vybraná kategorie v menu

  // Upraví surový dlouhý text adresy z API a zkusí vzít jen Město a Okres (pokud najde)
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

  // --- VYSKAKOVACÍ ŠUPLÍK PRO ULOŽENÍ STROMU (Přidání k sobě) ---
  void _showAddDialogFromEncyclopedia(String species, List<dynamic> varieties, int currentCount, String emoji, String colorHex) {
    // Předvolené položky
    String selectedVariety = varieties.isNotEmpty ? varieties[0].toString() : "";
    String selectedSize = 'Střední (do 5m)';
    final List<String> sizes = ['Malý (do 3m)', 'Střední (do 5m)', 'Velký (nad 5m)'];

    final TextEditingController searchController = TextEditingController();
    final TextEditingController countController = TextEditingController(text: '1');
    
    List<dynamic> searchResults = []; // Tady se ukládají odpovědi z hledání města
    Map<String, dynamic>? selectedLoc; // Jakmile si město vybereš, uloží se sem GPS souřadnice
    Timer? debounce; // Zajistí, že se API nevolá na každý jednotlivý napsaný znak (počká 600 milisekund)

    // Otevření onoho okna zespodu obrazovky
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        // Opět - setDS zajistí překreslení uvnitř toho dialogu (např. když vyskočí ty vyhledané obce)
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

              // Vizuální vizitka vybraného stromu
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

              // Výběrčko Odrůdy
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
                  // Počet kusů
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Kusů", border: OutlineInputBorder(), prefixIcon: Icon(Icons.numbers)),
                    ),
                  ),
                  const SizedBox(width: 15),
                  // Velikost
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

              // HLEDÁNÍ LOKALITY PROSTŘEDNICTVÍM OSM NOMINATIM (Free mapová služba)
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
                              selectedLoc = null; // Zruší výběr města
                              searchController.clear();
                              searchResults = [];
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (v) {
                  // Když uživatel píše, počkáme půl vteřiny a pak se zeptáme internetu
                  if (debounce?.isActive ?? false) debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 600), () async {
                    if (v.length > 2 && selectedLoc == null) {
                      try {
                        final res = await http.get(
                          Uri.parse('https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(v)}&format=json&limit=5&countrycodes=cz'),
                          headers: {'User-Agent': 'FrutiqApp/1.0'}, // Identifikace pro API
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
              
              // Seznam našepnutých měst (vyskočí ihned po zjištění z API)
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
                              selectedLoc = loc; // Hotovo, uložili jsme GPS!
                              searchController.text = _formatAddress(loc);
                              searchResults = []; // Skryjeme seznam
                            }),
                          ),
                        ).toList(),
                  ),
                ),
              const SizedBox(height: 25),
              
              // HLAVNÍ TLAČÍTKO PRO ODESLÁNÍ DO TVÉ ZAHRADY
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
                      ? null // Nelze uložit, dokud nevybereš z mapy lokalitu
                      : () async {
                          int count = int.tryParse(countController.text) ?? 1;
                          if (count < 1) count = 1;

                          // Fyzické přidání do Firebase, sbíráme všechna data z formuláře
                          await db.collection('userTrees').add({
                            'species': species,
                            'variety': selectedVariety,
                            'count': count,
                            'treeSize': selectedSize,
                            'locationName': searchController.text,
                            'lat': double.parse(selectedLoc!['lat']),
                            'lon': double.parse(selectedLoc!['lon']),
                            'ownerId': FirebaseAuth.instance.currentUser!.uid, // Spáruje se to tvojí IDčkem účtu
                            'index': currentCount, // Aby se řadil hned na konec seznamu
                            'emoji': emoji, // Emoji se přesune z databáze katalogu sem
                            'color': colorHex, // Barva se přesune z databáze katalogu sem
                          });
                          Navigator.pop(context); // Zavře šuplík
                          // Potvrzovací toast
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

  // Přípravná funkce – před tím, než vůbec otevřeme ten šuplík, musíme spočítat, 
  // kolik stromů už máš, aby nový strom dostal správný pořadový index (na chvost seznamu).
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
      // StreamBuilder stahuje celou 'catalogTrees' a naslouchá případným změnám (kdybys přidal do DB nový strom)
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

          // --- LOGIKA KATEGORIÍ (Vršek stránky s těmi "bublinami") ---
          // Projdeme všechny stažené stromy a přečteme si, jaké existují kategorie
          Set<String> categoriesSet = {'Vše'};
          for (var d in docs) {
            final data = d.data() as Map<String, dynamic>;
            final String cat = data['kategorie'] ?? 'Ostatní';
            categoriesSet.add(cat);
          }
          List<String> categories = categoriesSet.toList();
          categories.sort(); // Seřadíme podle abecedy

          // Odfiltrujeme stromy k zobrazení podle toho, jaká je vybrána kategorie
          var filteredDocs = docs.where((d) {
            if (_selectedCategory == 'Vše') return true;
            final data = d.data() as Map<String, dynamic>;
            final String cat = data['kategorie'] ?? 'Ostatní';
            return cat == _selectedCategory;
          }).toList();

          return Column(
            children: [
              // Horizontálně rotovací lišta s Chip-tlačítky kategorií
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

              // Výpis stromů (Karet)
              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(child: Text("V této kategorii zatím nic není.", style: TextStyle(color: Colors.grey.shade500)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          // ID záznamu ve Firestore katalogu slouží rovnou jako název (např. 'Jabloň')
                          final String species = filteredDocs[index].id;
                          final Map<String, dynamic> data = filteredDocs[index].data() as Map<String, dynamic>;
                          final List<dynamic> varieties = data['odrudy'] ?? [];

                          // Defaultně tam prskneme '🌱' a zelenou barvu, pokud to náhodou nějaký starší záznam nemá vyplněné
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
                                      // Výpis odrůd do takových těch malých obdélníčků (Chip)
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
                                // Spodek kartičky - tlačítko Přidat
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      ElevatedButton.icon(
                                        // Zde voláme funkci, co otevře ten přidávací dialog a předá jí barvu a emoji!
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

// ============================================================================
// 3. ZÁLOŽKA: STATISTIKY
// Stránka plná dat a agregovaných statistik o tvojí zahradě
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
      // Opět se ptáme databáze na VŠECHNY tvoje stromy, z nich teď budeme počítat sumy.
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
          
          // Zde budeme průběžně sčítat data
          int totalPlants = 0; // Celkový fyzický počet všech rostlin na zahradě
          Set<String> uniqueLocations = {}; // Set zaručuje, že žádné město se tu nebude opakovat

          Map<String, int> speciesCount = {}; // Např. "Jabloň" -> 5 ks
          Map<String, String> speciesEmoji = {}; // Např. "Jabloň" -> '🍎'
          Map<String, String> speciesColorHex = {}; // Např. "Jabloň" -> '#EF5350'

          // Přečteme z databáze každý tvůj záznam a sečteme to
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
            // K aktuální hodnotě Jabloní v mapě přičteme tento počet
            speciesCount[species] = (speciesCount[species] ?? 0) + count;
          }

          // Seřadíme to, ať je to, čeho je nejvíc, úplně nahoře!
          var sortedSpecies = speciesCount.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          // Ta nejčastější plodina hned první v seznamu získá výsadní právo být v úvodu.
          String topSpecies = sortedSpecies.first.key;
          String topEmoji = speciesEmoji[topSpecies] ?? '🌱';

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              // Horní rámeček - "Zajímavost", jaký strom máš nejvíc zastoupen
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

              // Rychlá "dashboardová" čísla nahoře
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

              // Ten slavný nádherný rotující animovaný graf!
              SizedBox(
                height: 200,
                // TweenAnimationBuilder jednoduše animuje hodnotu od 0.0 do 1.0 po dobu 1.2 vteřiny
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic, // Graf se k cíli zpomalí (vypadá to profi)
                  builder: (context, value, child) {
                    return CustomPaint(
                      // Sem posíláme naši třídu (ten malíř _DonutChartPainter zespodu)
                      painter: _DonutChartPainter(
                        speciesCount: speciesCount,
                        totalCount: totalPlants,
                        colorMapper: (species) => hexToColor(speciesColorHex[species] ?? '#4CAF50'),
                        animationValue: value,
                        isDarkMode: isDarkMode,
                      ),
                      child: Center(
                        // Co je uvnitř toho "Doughnut" kroužku? Číslo.
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              (totalPlants * value).toInt().toString(), // I to číslo efektně načítá do finále
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

              // Výpis textových výsledků hned pod grafem (odshora dolů po jednotlivých druzích)
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

  // Funkce tvořící ten krásný barevný obdélníček s číslem
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
            tween: IntTween(begin: 0, end: int.parse(value)), // I toto číslo se do plného naanimuje jako počítadlo
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

// "Malíř" našeho grafu. Musíme si to napsat sami, protože ve Flutteru žádný vestavěný koláčový graf není.
class _DonutChartPainter extends CustomPainter {
  final Map<String, int> speciesCount;
  final int totalCount;
  final Color Function(String) colorMapper;
  final double animationValue; // Pohybuje se od 0.0 do 1.0 (podle toho se postupně vykresluje)
  final bool isDarkMode;

  _DonutChartPainter({
    required this.speciesCount, required this.totalCount, required this.colorMapper, required this.animationValue, required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double strokeWidth = 25.0; // Jak tlustá je hrana (kolečko) grafu
    
    // Obdélník uprostřed plátna, do kterého to nakreslíme
    Rect rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width - strokeWidth, height: size.height - strokeWidth,
    );

    // Kreslení "prázdného" podkreslení grafu, na který pak pojedou barvy
    Paint bgPaint = Paint()
      ..color = isDarkMode ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(rect.center, rect.width / 2, bgPaint);

    if (totalCount == 0) return;

    double startAngle = -math.pi / 2; // Matematika: -90 stupňů znamená "Nahoru na číslici 12 hodinách hodin"

    var sortedEntries = speciesCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // Smyčka, která postupně přikresluje jednotlivé úseče grafu za každý druh ovocného stromu
    for (var entry in sortedEntries) {
      // Úhel dané výseče se řídí i animací! Proto ten kroužek krásně postupně oběhne.
      double sweepAngle = (entry.value / totalCount) * 2 * math.pi * animationValue;

      Paint paint = Paint()
        ..color = colorMapper(entry.key)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round // Kulaté konce grafu
        ..strokeWidth = strokeWidth;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle; // Posuneme se po hodinách na konec výseče, aby další navázala.
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    // Překresli se VŽDY, když se změní číslo animace (tím pádem asi 60x za vteřinu, dokud animace nedoběhne)
    return oldDelegate.animationValue != animationValue;
  }
}

// ============================================================================
// 4. ZÁLOŽKA: NASTAVENÍ
// Stránka profilu - odhlašování, přepínání větru a tmavého režimu.
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
    _loadUserProfile(); // Jakmile na tuto obrazovku klikneš, požádáme databázi o tvoje jméno a telefon
  }

  // Funkce co se dotáže databáze na "Můj profil"
  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() => _email = user.email ?? "Host"); // E-mail si pamatuje rovnou FirebaseAuth služba

      try {
        // Dodatečné věci (jméno a telefon) jsme ukládali do naší Firestore databáze do složky "users"
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
          // PROFILOVÁ KARTA Nahoře
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

          // VÝBĚR JEDNOTEK VĚTRU
          ListTile(
            leading: const Icon(Icons.air, color: Colors.teal),
            title: const Text("Jednotky větru"),
            trailing: ValueListenableBuilder<String>(
              valueListenable: windUnitNotifier,
              builder: (context, currentUnit, _) {
                // Dropdown menu
                return DropdownButton<String>(
                  value: currentUnit,
                  underline: const SizedBox(),
                  onChanged: (val) async {
                    if (val != null) {
                      // Když se hodnota změní, uložíme to fyzicky do mobilu a pošleme tu informaci do "vysílačky", která to ihned překreslí i v Zahrádce v předpovědi počasí
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

          // PŘEPÍNAČ TMAVÉHO REŽIMU
          SwitchListTile(
            title: const Text("Tmavý režim"),
            secondary: Icon(isDarkMode ? Icons.dark_mode : Icons.light_mode, color: Colors.orange),
            value: isDarkMode,
            onChanged: (bool value) async {
              // Obdoba toho nad tím - uložím a rozešlu info po celé apce, aby zhasla/rožla světlo!
              themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isDarkMode', value);
            },
          ),

          const SizedBox(height: 20),
          
          // TLAČÍTKO ODHLÁSIT (Zavolá funkci FirebaseAuth pro odhlášení. Náš Hlídač "AuthGate" si toho ihned všimne a vyhodí tě zpátky na LoginScreen)
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