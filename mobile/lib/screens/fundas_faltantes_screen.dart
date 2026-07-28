import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../data/juego_repository.dart';
import '../providers/auth_provider.dart';
import '../providers/juegos_provider.dart';

class FundasFaltantesScreen extends StatefulWidget {
  const FundasFaltantesScreen({super.key});

  @override
  State<FundasFaltantesScreen> createState() => _FundasFaltantesScreenState();
}

class _FundasFaltantesScreenState extends State<FundasFaltantesScreen> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      context.read<JuegosProvider>().fetchStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JuegosProvider>();
    final auth = context.watch<AuthProvider>();
    final fundasFaltantes = provider.fundasFaltantes;

    if (auth.noEnfundo) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fundas pendientes')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Has desactivado los avisos de enfundado en tu perfil.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final total = fundasFaltantes.fold<int>(0, (sum, item) {
      return sum + ((item['cantidad_total'] as int?) ?? 0);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Fundas pendientes')),
      body: RefreshIndicator(
        onRefresh: () => provider.fetchStats(),
        child: fundasFaltantes.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 96),
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No faltan fundas',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 0,
                    color: Colors.orange.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Colors.orange.withValues(alpha: 0.35),
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Colors.orange.withValues(alpha: 0.15),
                        child: const Icon(Icons.style, color: Colors.orange),
                      ),
                      title: const Text(
                        'Faltan Fundas',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '$total fundas pendientes en ${fundasFaltantes.length} tama\u00f1os',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...(List<Map<String, dynamic>>.from(fundasFaltantes)
                        ..sort((a, b) => JuegoRepository.normalizeText(
                                (a['tipo_nombre'] ?? '').toString())
                            .compareTo(JuegoRepository.normalizeText(
                                (b['tipo_nombre'] ?? '').toString()))))
                      .map((funda) {
                    final juegosRaw = funda['juegos_json'] as String?;
                    final juegos = juegosRaw != null
                        ? (jsonDecode(juegosRaw) as List).cast<Map>()
                        : const <Map>[];
                    final juegosOrdenados = List<Map>.from(juegos)
                      ..sort((a, b) => JuegoRepository.normalizeText(
                              (a['juego_nombre'] ?? '').toString())
                          .compareTo(JuegoRepository.normalizeText(
                              (b['juego_nombre'] ?? '').toString())));
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ExpansionTile(
                        leading: const Icon(Icons.style),
                        title: Text(
                          (funda['tipo_nombre'] ?? 'Tipo no disponible')
                              .toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${funda['ancho_mm']} x ${funda['alto_mm']} mm',
                        ),
                        trailing: Text(
                          '${funda['cantidad_total']} fundas',
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        children: juegosOrdenados.map((item) {
                          return ListTile(
                            title: Text(
                              (item['juego_nombre'] ?? 'Juego no disponible')
                                  .toString(),
                            ),
                            trailing: Text(
                              '${item['cantidad_cartas']} cartas',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () {
                              Navigator.of(context).pushNamed(
                                '/juego',
                                arguments: (item['juego_local_id'] as num?)
                                    ?.toInt(),
                              );
                            },
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}
