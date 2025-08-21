import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:micro_mobility_app/config.dart';
import 'package:micro_mobility_app/services/api_service.dart';
import 'package:micro_mobility_app/models/location.dart';
import 'package:micro_mobility_app/services/websocket_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:micro_mobility_app/utils/map_app_constants.dart'
    show AppConstants;

class MapAndZoneScreen extends StatefulWidget {
  const MapAndZoneScreen({super.key});

  @override
  State<MapAndZoneScreen> createState() => _MapAndZoneScreenState();
}

class _MapAndZoneScreenState extends State<MapAndZoneScreen>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Управление'),
          centerTitle: true,
          bottom: TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.map), text: 'Карты'),
              Tab(icon: Icon(Icons.grid_3x3), text: 'Зоны'),
              Tab(icon: Icon(Icons.location_on), text: 'Онлайн'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            MapUploadTab(),
            ZoneManagementTab(),
            EmployeeMapTab(),
          ],
        ),
      ),
    );
  }
}

// === ВКЛАДКА 1: Загрузка карт ===
class MapUploadTab extends StatefulWidget {
  const MapUploadTab({super.key});

  @override
  State<MapUploadTab> createState() => _MapUploadTabState();
}

class _MapUploadTabState extends State<MapUploadTab> {
  File? _uploadedGeoJson;
  bool _isLoading = false;
  bool _isUploading = false;
  List<dynamic> _uploadedMaps = [];
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUploadedMaps();
  }

  Future<void> _loadUploadedMaps() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final response = await http.get(
        Uri.parse(AppConfig.adminMapsUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is List) {
          if (mounted) {
            setState(() {
              _uploadedMaps = body;
            });
          }
        }
      } else {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickGeoJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['geojson', 'json'],
      );

      if (result == null) return;

      final pickedFile = File(result.files.single.path!);
      final fileSizeMB = pickedFile.statSync().size / (1024 * 1024);

      if (fileSizeMB > 40) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Файл слишком большой. Максимум: 40 МБ'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _uploadedGeoJson = pickedFile;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Файл выбран: ${result.files.single.name} (${fileSizeMB.toStringAsFixed(1)} МБ)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора файла: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadMapToServer() async {
    if (_uploadedGeoJson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала выберите файл'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_cityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Укажите город'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (mounted) setState(() => _isUploading = true);

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.uploadMapUrl),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['city'] = _cityController.text.trim();
      request.fields['description'] = _descriptionController.text.trim();

      final file = await http.MultipartFile.fromPath(
        'geojson_file',
        _uploadedGeoJson!.path,
        filename: _uploadedGeoJson!.path.split('/').last,
      );
      request.files.add(file);

      final response = await request.send();
      final resp = await http.Response.fromStream(response);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Карта успешно загружена'),
              backgroundColor: Colors.green,
            ),
          );

          _clearForm();
          await _loadUploadedMaps();
        }
      } else {
        throw Exception('Ошибка: ${resp.statusCode} - ${resp.reasonPhrase}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _deleteMap(int mapId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить карту?'),
        content: const Text('Вы уверены, что хотите удалить эту карту?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) throw Exception('Токен не найден');

      final response = await http.delete(
        Uri.parse(AppConfig.deleteMapUrl(mapId)),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🗑️ Карта удалена'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadUploadedMaps();
        }
      } else {
        throw Exception('Ошибка удаления: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearForm() {
    if (mounted) {
      setState(() {
        _uploadedGeoJson = null;
        _cityController.clear();
        _descriptionController.clear();
      });
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return RefreshIndicator(
      onRefresh: _loadUploadedMaps,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Загрузить новую карту',
              style: theme.textTheme.titleLarge?.copyWith(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Выберите файл GeoJSON и укажите город для загрузки на сервер',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _pickGeoJson,
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.upload_file),
                label: Text(
                  _uploadedGeoJson != null
                      ? 'Файл выбран: ${_uploadedGeoJson!.path.split('/').last}'
                      : 'Выбрать GeoJSON файл',
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_uploadedGeoJson != null) ...[
              _buildSelectedFileInfo(primaryColor),
              const SizedBox(height: 16),
            ],
            _buildTextField(
              controller: _cityController,
              label: 'Город',
              hint: 'Введите название города',
              icon: Icons.location_city,
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _descriptionController,
              label: 'Описание (опционально)',
              hint: 'Описание карты или зон',
              maxLines: 2,
              icon: Icons.description,
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading || _uploadedGeoJson == null
                    ? null
                    : _uploadMapToServer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isUploading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  _isUploading ? 'Загрузка...' : 'Загрузить на сервер',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryColor.withOpacity(0.2)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ℹ️ Ограничения',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('• Поддерживаются: .geojson, .json'),
                  Text('• Макс. размер: 40 МБ'),
                  Text('• Только корректные геоданные'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Загруженные карты',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _uploadedMaps.isEmpty
                    ? _buildEmptyState(primaryColor)
                    : _buildMapsList(primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFileInfo(Color primaryColor) {
    final fileSize = _formatFileSize(_uploadedGeoJson!.statSync().size);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: primaryColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _uploadedGeoJson!.path.split('/').last,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Размер: $fileSize',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _uploadedGeoJson = null),
            icon: const Icon(Icons.close, color: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    IconData? icon,
    required Color primaryColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapsList(Color primaryColor) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _uploadedMaps.length,
      itemBuilder: (context, index) {
        final map = Map<String, dynamic>.from(_uploadedMaps[index]);
        return _buildMapCard(map, primaryColor);
      },
    );
  }

  Widget _buildMapCard(Map<String, dynamic> map, Color primaryColor) {
    final id = map['id'] as int;
    final city = map['city'] as String? ?? 'Неизвестный город';
    final description = map['description'] as String? ?? '';
    final fileName = map['file_name'] as String? ?? '';
    final fileSize = map['file_size'] as int? ?? 0;
    final uploadDate = map['upload_date'] as String? ?? '';

    final formattedFileSize = _formatFileSize(fileSize);
    final displayName = fileName.split('/').last;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.map, color: primaryColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$city • $formattedFileSize',
                        style:
                            const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (description.isNotEmpty)
              Text(description,
                  style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            if (uploadDate.isNotEmpty)
              Text(
                'Загружено: $uploadDate',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Просмотр'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: ElevatedButton.icon(
                    onPressed: () => _deleteMap(id),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Удалить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color primaryColor) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.map, size: 64, color: primaryColor.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              'Нет загруженных карт',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Загрузите первую карту GeoJSON',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes байт';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

// === ВКЛАДКА 2: Управление зонами ===
class ZoneManagementTab extends StatefulWidget {
  const ZoneManagementTab({super.key});

  @override
  State<ZoneManagementTab> createState() => _ZoneManagementTabState();
}

class _ZoneManagementTabState extends State<ZoneManagementTab> {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late Future<List<String>> _zonesFuture;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _zonesFuture = _loadZones();
  }

  Future<List<String>> _loadZones() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) return [];
    return _apiService.getAvailableZones(token);
  }

  Future<void> _addZone() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      await _apiService.createZone(token, name);
      setState(() {
        _zonesFuture = _loadZones();
        _controller.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _deleteZone(String name) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      final zones = await _zonesFuture;
      final id = zones.indexOf(name) + 1;

      await _apiService.deleteZone(token, id);
      setState(() {
        _zonesFuture = _loadZones();
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _zonesFuture = _loadZones();
        });
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Управление зонами',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Добавление, удаление и редактирование зон по номерам',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Добавить зону',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: const InputDecoration(
                              hintText: 'Номер зоны (1, 2, 3...)',
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _addZone,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'Добавить',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Существующие зоны',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<String>>(
              future: _zonesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final zones = snapshot.data ?? [];
                if (zones.isEmpty) {
                  return Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.grid_3x3,
                              size: 64, color: primaryColor.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          const Text(
                            'Нет зон',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Добавьте первую зону',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: zones.length,
                  itemBuilder: (context, index) {
                    final zone = zones[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              zone,
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        title: Text('Зона $zone'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteZone(zone),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// === ВКЛАДКА 3: Онлайн-карта сотрудников ===
class EmployeeMapTab extends StatefulWidget {
  const EmployeeMapTab({super.key});

  @override
  State<EmployeeMapTab> createState() => _EmployeeMapTabState();
}

class _EmployeeMapTabState extends State<EmployeeMapTab> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  late WebSocketService _webSocketService;
  List<Location> _onlineUsers = [];
  LatLng? _currentLocation;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    try {
      await _fetchCurrentLocation();
      await _connectWebSocket();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      // ИСПРАВЛЕНО: Убраны лишние пробелы в URL
      final response = await http.get(Uri.parse('https://ipapi.co/json/'));

      // Добавлена проверка на успешный ответ и наличие тела
      if (response.statusCode == 200 && response.body != null) {
        final data = jsonDecode(response.body);

        // Добавлена безопасная проверка на null значения
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;

        if (lat != null && lng != null && mounted) {
          setState(() {
            _currentLocation = LatLng(lat, lng);
          });
        }
      } else {
        debugPrint('Не удалось получить геолокацию: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Ошибка получения локации по IP: $e');
    }
  }

  Future<void> _connectWebSocket() async {
    final token = await _storage.read(key: 'jwt_token');
    if (token == null) {
      setState(() {
        _error = 'Токен не найден';
      });
      return;
    }

    _webSocketService = WebSocketService(onLocationsUpdated: (users) {
      if (mounted) {
        setState(() {
          _onlineUsers = users;
        });
      }
    });

    try {
      await _webSocketService.connect();
    } catch (e) {
      setState(() {
        _error = 'Ошибка подключения к серверу: $e';
      });
    }
  }

  @override
  void dispose() {
    _webSocketService.disconnect();
    super.dispose();
  }

  Future<void> _refreshMap() async {
    try {
      await _fetchCurrentLocation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Карта обновлена')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(child: Text('Ошибка: $_error'));
    }

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _currentLocation ?? const LatLng(43.2389, 76.8897),
            initialZoom: 12.0,
            minZoom: 5.0,
            maxZoom: 18.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: AppConstants.cartoDbPositronUrl,
              subdomains: AppConstants.cartoDbSubdomains,
              retinaMode: RetinaMode.isHighDensity(context),
            ),

            // Текущая локация
            if (_currentLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation!,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            // Онлайн пользователи
            if (_onlineUsers.isNotEmpty)
              MarkerLayer(
                markers: _onlineUsers.map((u) {
                  return Marker(
                    point: LatLng(u.lat, u.lng),
                    width: 60,
                    height: 30,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 3,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        u.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                          shadows: [
                            Shadow(
                              blurRadius: 1.0,
                              color: Colors.black,
                              offset: Offset(0.5, 0.5),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),

        // Кнопка обновления
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton(
            backgroundColor: Colors.green,
            onPressed: _refreshMap,
            tooltip: 'Обновить карту',
            child: const Icon(Icons.refresh, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
