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

  Future<void> _showEventoMenu(Evento evento) async {
    final editable = evento.esEditable;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                evento.nombre,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            if (editable)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Editar evento'),
                onTap: () => Navigator.pop(ctx, 'editar'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Eliminar evento',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(ctx, 'eliminar'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'editar') {
      await _editarEvento();
    } else if (action == 'eliminar') {
      await _eliminarEvento(evento);
    }
  }

  Future<void> _showJuegoMenu(EventoJuego ej) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                ej.juegoNombre,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
              title: const Text(
                'Quitar del evento',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(ctx, 'quitar'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'quitar') {
      await _quitarJuego(ej);
    }
  }

  Future<void> _quitarJuego(EventoJuego ej) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar juego'),
        content: Text('¿Quitar "${ej.juegoNombre}" del evento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await context.read<EventosProvider>().removeJuego(
          widget.eventoLocalId,
          ej.juegoLocalId,
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

  Future<void> _editarEvento() async {
    final updated = await Navigator.of(context).pushNamed(
      '/evento/editar',
      arguments: widget.eventoLocalId,
    );
    if (updated == true && mounted) {
      await context.read<EventosProvider>().fetchEvento(widget.eventoLocalId);
    }
  }

  Future<void> _eliminarEvento(Evento evento) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar evento'),
        content: Text(
          '¿Eliminar "${evento.nombre}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await context.read<EventosProvider>().deleteEvento(widget.eventoLocalId);
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
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onLongPress: () => _showEventoMenu(evento),
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
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final ej = evento.juegos[index];
                      final tile = Card(
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
                          onLongPress: editable
                              ? () => _showJuegoMenu(ej)
                              : null,
                        ),
                      );

                      if (!editable) return tile;

                      return Dismissible(
                        key: ValueKey('ej_${ej.localId ?? ej.juegoLocalId}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          await _quitarJuego(ej);
                          return false;
                        },
                        child: tile,
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
