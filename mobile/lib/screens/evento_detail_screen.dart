import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/evento.dart';
import '../models/juego.dart';
import '../providers/eventos_provider.dart';
import '../widgets/game_image.dart';
import '../widgets/juego_picker_sheet.dart';

class EventoDetailScreen extends StatefulWidget {
  final int eventoLocalId;

  const EventoDetailScreen({super.key, required this.eventoLocalId});

  @override
  State<EventoDetailScreen> createState() => _EventoDetailScreenState();
}

class _EventoDetailScreenState extends State<EventoDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventosProvider>().fetchEvento(widget.eventoLocalId);
    });
  }

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

  Future<void> _anadirJuego(Evento evento) async {
    final juego = await JuegoPickerSheet.show(
      context,
      title: 'Añadir juego al evento',
      hint: 'Buscar juego base...',
      soloBase: true,
    );
    if (juego == null || juego.localId == null || !mounted) return;

    final yaExiste = evento.juegos.any((j) => j.juegoLocalId == juego.localId);
    if (yaExiste) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este juego ya está en el evento')),
      );
      return;
    }

    await context.read<EventosProvider>().addJuego(
          widget.eventoLocalId,
          juego.localId!,
        );
  }

  Future<void> _cerrarEvento() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar evento'),
        content: const Text(
          '¿Confirmas que los juegos han sido colocados? '
          'El evento quedará cerrado y no podrás modificarlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar evento'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await context.read<EventosProvider>().cerrarEvento(widget.eventoLocalId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventosProvider>();
    final evento = provider.eventoDetalle;

    if (provider.loading && evento == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (evento == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Evento')),
        body: const Center(child: Text('Evento no encontrado')),
      );
    }

    final editable = evento.esEditable;
    final puedeCerrar = evento.puedeCerrar;
    final soloLectura = evento.esSoloLectura;

    return Scaffold(
      appBar: AppBar(
        title: Text(evento.nombre),
        actions: [
          if (editable)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Añadir juego',
              onPressed: () => _anadirJuego(evento),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatFecha(evento.fechaInicio, evento.fechaFin),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.place_outlined, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Expanded(child: Text(evento.localizacion)),
                      ],
                    ),
                    if (soloLectura) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Evento cerrado (solo consulta)',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ] else if (puedeCerrar) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Pendiente de colocar juegos',
                        style: TextStyle(
                          color: Colors.amber.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Juegos (${evento.juegos.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: evento.juegos.isEmpty
                ? Center(
                    child: Text(
                      editable
                          ? 'Pulsa + para añadir juegos'
                          : 'No hay juegos en este evento',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: evento.juegos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final ej = evento.juegos[index];
                      return Dismissible(
                        key: ValueKey('ej_${ej.localId ?? ej.juegoLocalId}'),
                        direction: editable
                            ? DismissDirection.endToStart
                            : DismissDirection.none,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          await context.read<EventosProvider>().removeJuego(
                                widget.eventoLocalId,
                                ej.juegoLocalId,
                              );
                          return true;
                        },
                        child: Card(
                          elevation: 0,
                          child: ListTile(
                            leading: GameImage(
                              juego: Juego(
                                id: ej.juegoLocalId,
                                localId: ej.juegoLocalId,
                                nombre: ej.juegoNombre,
                                imagen: ej.juegoImagen,
                              ),
                              width: 48,
                              height: 48,
                            ),
                            title: Text(ej.juegoNombre),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).pushNamed(
                              '/juego',
                              arguments: ej.juegoLocalId,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (puedeCerrar)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _cerrarEvento,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Cerrar evento'),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: editable
          ? FloatingActionButton(
              onPressed: () => _anadirJuego(evento),
              tooltip: 'Añadir juego',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
