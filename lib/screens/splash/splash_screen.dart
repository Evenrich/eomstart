import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:micro_mobility_app/config/config.dart';
import 'package:micro_mobility_app/providers/shift_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    // Запускаем инициализацию после первого рендера — context будет валиден
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    try {
      debugPrint('🔍 [Splash] Checking authentication tokens...');

      // 1. Проверяем наличие JWT-токена
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) {
        debugPrint('❌ [Splash] No token found → redirect to /login');
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      // 2. Проверяем наличие интернета
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = connectivityResult.any((result) => result != ConnectivityResult.none);

      if (hasInternet) {
        debugPrint('🌐 [Splash] Internet available. Validating token online...');
        try {
          final response = await http.get(
            Uri.parse(AppConfig.profileUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          );

          if (response.statusCode == 200) {
            final userData = jsonDecode(response.body) as Map<String, dynamic>;
            final status = userData['status'] as String?;
            final isActive = userData['is_active'] as bool?;

            if (status == 'active' && isActive == true) {
              debugPrint('✅ [Splash] User is active → redirect to /dashboard');
              if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
              return;
            } else {
              debugPrint('⏳ [Splash] User pending approval → redirect to /pending');
              if (mounted) Navigator.pushReplacementNamed(context, '/pending');
              return;
            }
          } else {
            debugPrint('⚠️ [Splash] Profile request failed (status ${response.statusCode})');
          }
        } catch (e) {
          debugPrint('⚠️ [Splash] Network error during profile check: $e');
        }
      }

      // 3. Offline fallback: пробуем загрузить данные из кэша
      debugPrint('📴 [Splash] No internet or online check failed. Trying offline cache...');
      final shiftProvider = Provider.of<ShiftProvider>(context, listen: false);
      await shiftProvider.loadShifts(); // Этот метод должен безопасно работать без сети

      if (shiftProvider.currentUsername != null) {
        debugPrint('✅ [Splash] Offline cache hit → redirect to /dashboard');
        if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
        return;
      }

      // 4. Если ничего не сработало — на логин
      debugPrint('❌ [Splash] No valid session → redirect to /login');
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    } catch (e, stack) {
      debugPrint('💥 [Splash] Critical error: $e\nStack: $stack');
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[700],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.electric_scooter,
              color: Colors.white,
              size: 80,
            ),
            const SizedBox(height: 20),
            Text(
              'Оператор микромобильности',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
