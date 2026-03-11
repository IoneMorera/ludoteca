import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../providers/juegos_provider.dart';
import '../models/juego.dart';
import '../services/api_service.dart';
import '../widgets/game_image.dart';

class JuegoDetailScreen extends StatefulWidget {
  final int juegoId;
  const JuegoDetailScreen({super.key, required this.juegoId});

  @override
  State<JuegoDetailScreen> createState() => _JuegoDetailScreenState();
}

class _JuegoDetailScreenState extends State<JuegoDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<JuegosProvider>().fetchJuego(widget.juegoId);
  }

  Future<void> _changeImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Cámara'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (picked == null) return;

    try {
      final formData = FormData.fromMap({
        'imagen': await MultipartFile.fromFile(File(picked.path).path),
        '_method': 'PUT',
      });
      await ApiService().upload('/juegos/${widget.juegoId}', formData);
      if (mounted) {
        context.read<JuegosProvider>().fetchJuego(widget.juegoId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagen actualizada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JuegosProvider>();
    final juego = provider.juegoDetalle;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(juego?.nombre ?? 'Cargando...'),
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : juego == null
              ? const Center(child: Text('Juego no encontrado'))
              : RefreshIndicator(
                  onRefresh: () => provider.fetchJuego(widget.juegoId),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHeader(juego, theme),
                      const SizedBox(height: 20),
                      _buildInfoGrid(juego, theme),
                      if (juego.propietarios.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildSection('Propietarios', theme,
                            child: Wrap(
                              spacing: 8,
                              children: juego.propietarios
                                  .map((p) => Chip(label: Text(p.nombre)))
                                  .toList(),
                            )),
                      ],
                      if (juego.expansiones.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildSection('Expansiones (${juego.expansiones.length})',
                            theme,
                            child: Column(
                              children: juego.expansiones
                                  .map((exp) => ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.extension,
                                            size: 20),
                                        title: Text(exp.nombre,
                                            style:
                                                const TextStyle(fontSize: 14)),
                                        trailing:
                                            const Icon(Icons.chevron_right,
                                                size: 18),
                                        onTap: () => Navigator.of(context)
                                            .pushNamed('/juego',
                                                arguments: exp.id),
                                      ))
                                  .toList(),
                            )),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(Juego juego, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _changeImage,
          child: Stack(
            children: [
              GameImage(
                juego: juego,
                width: 120,
                height: 120,
                borderRadius: BorderRadius.circular(12),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(juego.nombre,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              if (juego.esExpansion) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Expansión',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600)),
                ),
              ],
              if (juego.descripcion != null &&
                  juego.descripcion!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(juego.descripcion!,
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 13, height: 1.4)),
              ],
              if (juego.esExpansion && juego.juegoBase != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => Navigator.of(context)
                      .pushNamed('/juego', arguments: juego.juegoBase!.id),
                  child: Text('Juego base: ${juego.juegoBase!.nombre}',
                      style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoGrid(Juego juego, ThemeData theme) {
    final items = <_InfoItem>[
      _InfoItem('Categoría', juego.categoria?.nombre ?? '-', Icons.category),
      _InfoItem('Jugadores', juego.jugadoresTexto, Icons.people),
      _InfoItem('Edad', juego.edadTexto, Icons.child_care),
      _InfoItem('Estado', juego.estado ?? '-', Icons.info_outline),
      _InfoItem(
          'Fecha compra', _formatDate(juego.fechaCompra), Icons.calendar_today),
      _InfoItem(
          'Ubicación',
          juego.ubicacion?.rutaCompleta ?? 'Sin asignar',
          Icons.location_on),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.5,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(item.icon, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(item.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 2),
              Text(item.value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSection(String title, ThemeData theme, {required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  final IconData icon;
  _InfoItem(this.label, this.value, this.icon);
}
