import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:desktop_window/desktop_window.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart'; // <--- NOVÝ IMPORT FONTŮ

// Importy našich nových rozdělených stránek
import 'stranky/prihlasovaci_stranka.dart';
import 'stranky/dashboard.dart';

// ============================================================================
// GLOBÁLNÍ PROMĚNNÉ A POMOCNÉ FUNKCE
// ============================================================================
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<String> windUnitNotifier = ValueNotifier('km/h');

// Převede hexadecimální kód barvy na Flutter Color
Color hexToColor(String hexString) {
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}

// ============================================================================
// HLAVNÍ FUNKCE APLIKACE (BOD VSTUPU)
// ============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();
  
  final isDark = prefs.getBool('isDarkMode') ?? false; 
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  
  windUnitNotifier.value = prefs.getString('windUnit') ?? 'km/h';

  // Kód pro změnu okna se spustí JEN, když nejsme na webu
  if (!kIsWeb) {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await DesktopWindow.setWindowSize(const Size(375, 812));
      await DesktopWindow.setMinWindowSize(const Size(375, 812));
    }
  }
  
  runApp(const MyApp());
}

// ============================================================================
// ZÁKLADNÍ NASTAVENÍ VZHLEDU APLIKACE
// ============================================================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return ValueListenableBuilder<String>(
          valueListenable: windUnitNotifier,
          builder: (_, windUnit, ___) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              themeMode: mode, 
              
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.green, 
                  brightness: Brightness.light,
                ),
                useMaterial3: true, 
                scaffoldBackgroundColor: const Color(0xFFF4F6F2), 
                
                // TADY APLIKUJEME MODERNÍ FONT 'POPPINS' PRO SVĚTLÝ REŽIM
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
              
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.green,
                  brightness: Brightness.dark,
                ),
                useMaterial3: true,
                scaffoldBackgroundColor: const Color(0xFF121411), 
                
                // TADY APLIKUJEME MODERNÍ FONT 'POPPINS' PRO TMAVÝ REŽIM
                fontFamily: GoogleFonts.poppins().fontFamily,
              ),
              
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// HLÍDAČ PŘIHLÁŠENÍ
// ============================================================================
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) return const DashboardScreen();
        return const LoginScreen();
      },
    );
  }
}