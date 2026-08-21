import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/bgg_expansion_repository.dart';
import '../data/sync_service.dart';
import '../providers/juegos_provider.dart';
import 'juego_picker_sheet.dart';

class ExpansionFaltanteActions {
  static Future<void> anadir(
    BuildContext context, {
    required BggExpansionRow expansion,
    required int juegoBaseLocalId,
  }) async {
    final result = await Navigator.of(context).pushNamed(
      '/juego/nuevo',
      arguments: expansion.toBggPrefill(juegoBaseLocalId: juegoBaseLocalId),
    );
    if (result == true && context.mounted) {
      await context.read<JuegosProvider>().fetchStats();
    }
  }

  static Future<void> vincularExistente(
    BuildContext context, {
    required BggExpansionRow expansion,
    required int juegoBaseLocalId,
  }) async {
    final juego = await JuegoPickerSheet.show(
      context,
      title: 'Vincular juego existente',
      hint: 'Buscar juego sin BGG...',
      soloSinBggId: true,
    );
    if (juego?.localId == null || !context.mounted) return;

    try {
      await context.read<JuegosProvider>().juegoRepository.vincularExpansionBgg(
            juegoLocalId: juego!.localId!,
            expansionBggId: expansion.expansionBggId,
            juegoBaseLocalId: juegoBaseLocalId,
          );
      await SyncService().syncAll();
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        await context.read<JuegosProvider>().fetchStats();
        messenger.showSnackBar(
          SnackBar(content: Text('${juego.nombre} vinculado a BGG')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  static Future<void> ignorar(
    BuildContext context, {
    required BggExpansionRow expansion,
  }) async {
    await context
        .read<JuegosProvider>()
        .bggExpansionRepository
        .marcarIgnorada(expansion.localId);
    await SyncService().syncAll();
    if (context.mounted) {
      await context.read<JuegosProvider>().fetchStats();
    }
  }

  static Future<void> showMenu(
    BuildContext context, {
    required BggExpansionRow expansion,
    required int juegoBaseLocalId,
    required VoidCallback onChanged,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Añadir'),
              onTap: () => Navigator.pop(ctx, 'anadir'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Vincular una existente'),
              onTap: () => Navigator.pop(ctx, 'vincular'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Ignorar'),
              onTap: () => Navigator.pop(ctx, 'ignorar'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;

    switch (action) {
      case 'anadir':
        await anadir(
          context,
          expansion: expansion,
          juegoBaseLocalId: juegoBaseLocalId,
        );
      case 'vincular':
        await vincularExistente(
          context,
          expansion: expansion,
          juegoBaseLocalId: juegoBaseLocalId,
        );
      case 'ignorar':
        await ignorar(context, expansion: expansion);
    }
    onChanged();
  }
}
