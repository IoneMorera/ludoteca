import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/evento.dart';
import '../providers/eventos_provider.dart';

class EventosScreen extends StatefulWidget {
  final int initialTab;

  const EventosScreen({super.key, this.initialTab = 0});

  @override
  State<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends State<EventosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventosProvider>().fetchEventos();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _crearEvento() async {
    final created = await Navigator.of(context).pushNamed('/evento/nuevo');
    if (created == true && mounted) {
      await context.read<EventosProvider>().fetchEventos();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventosProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Futuros'),
            Tab(text: 'Pasados'),
          ],
        ),
      ),
      body: provider.loading && provider.eventosFuturos.isEmpty && provider.eventosPasados.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _EventosList(
                  eventos: provider.eventosFuturos,
                  emptyMessage: 'No hay eventos futuros',
                  onRefresh: () => provider.fetchEventos(),
                ),
                _EventosList(
                  eventos: provider.eventosPasados,
                  emptyMessage: 'No hay eventos pasados',
                  showEstado: true,
                  onRefresh: () => provider.fetchEventos(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _crearEvento,
        tooltip: 'Nuevo evento',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EventosList extends StatelessWidget {
  final List<Evento> eventos;
  final String emptyMessage;
  final bool showEstado;
  final Future<void> Function() onRefresh;

  const _EventosList({
    required this.eventos,
    required this.emptyMessage,
    this.showEstado = false,
    required this.onRefresh,
  });

  String _formatFecha(DateTime inicio, DateTime fin) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    if (inicio.year == fin.year &&
        inicio.month == fin.month &&
        inicio.day == fin.day) {
      return fmt(inicio);
    }
    return '${fmt(inicio)} - ${fmt(fin)}';
  }

  @override
  Widget build(BuildContext context) {
    if (eventos.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(child: Text(emptyMessage)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: eventos.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final evento = eventos[index];
          final estado = evento.effectiveEstado;

          IconData? trailingIcon;
          Color? cardColor;
          if (showEstado) {
            if (estado == EventoEstado.cerrado) {
              trailingIcon = Icons.lock_outline;
              cardColor = Colors.grey;
            } else if (estado == EventoEstado.pendienteColocar) {
              trailingIcon = Icons.schedule;
              cardColor = Colors.amber;
            }
          }

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: (cardColor ?? Theme.of(context).colorScheme.outline)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: (cardColor ?? Theme.of(context).colorScheme.primary)
                    .withValues(alpha: 0.12),
                child: Icon(
                  trailingIcon ?? Icons.event,
                  color: cardColor ?? Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                evento.nombre,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatFecha(evento.fechaInicio, evento.fechaFin)),
                  Text(evento.localizacion),
                  if (evento.juegos.isNotEmpty)
                    Text('${evento.juegos.length} juegos'),
                  if (showEstado && estado == EventoEstado.pendienteColocar)
                    Text(
                      'Pendiente de colocar',
                      style: TextStyle(
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (showEstado && estado == EventoEstado.cerrado)
                    Text(
                      'Evento cerrado',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).pushNamed(
                  '/evento',
                  arguments: evento.localId,
                );
                if (context.mounted) {
                  await context.read<EventosProvider>().fetchEventos();
                }
              },
            ),
          );
        },
      ),
    );
  }
}
