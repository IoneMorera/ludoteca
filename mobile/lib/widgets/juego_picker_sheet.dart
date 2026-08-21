import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/juego.dart';
import '../providers/juegos_provider.dart';

/// Selector inline de juego base (formulario de expansión).
class JuegoBasePicker extends StatefulWidget {
  final int? initialLocalId;
  final ValueChanged<int?> onChanged;

  const JuegoBasePicker({
    super.key,
    this.initialLocalId,
    required this.onChanged,
  });

  @override
  State<JuegoBasePicker> createState() => _JuegoBasePickerState();
}

class _JuegoBasePickerState extends State<JuegoBasePicker> {
  int? _selectedLocalId;
  String? _selectedNombre;
  List<Juego> _suggestions = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedLocalId = widget.initialLocalId;
    _loadName();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadName() async {
    if (_selectedLocalId == null) return;
    final provider = context.read<JuegosProvider>();
    final j = await provider.juegoRepository.getByLocalId(_selectedLocalId!);
    if (mounted) setState(() => _selectedNombre = j?.nombre);
  }

  Future<void> _search(String q) async {
    final provider = context.read<JuegosProvider>();
    if (q.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    final results = await provider.juegoRepository.search(
      buscar: q,
      perPage: 20,
      soloBase: true,
    );
    if (mounted) setState(() => _suggestions = results);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedLocalId != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Chip(
              label: Text(_selectedNombre ?? 'Juego base seleccionado'),
              avatar: const Icon(Icons.casino, size: 16),
              onDeleted: () {
                setState(() {
                  _selectedLocalId = null;
                  _selectedNombre = null;
                });
                widget.onChanged(null);
              },
            ),
          ),
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Buscar juego base...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: _search,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              shrinkWrap: true,
              children: _suggestions
                  .map((j) => ListTile(
                        dense: true,
                        title: Text(j.nombre),
                        onTap: () {
                          setState(() {
                            _selectedLocalId = j.localId;
                            _selectedNombre = j.nombre;
                            _suggestions = [];
                            _searchCtrl.clear();
                          });
                          widget.onChanged(j.localId);
                        },
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet para elegir un juego existente de la ludoteca.
class JuegoPickerSheet extends StatefulWidget {
  final String title;
  final String hint;
  final bool soloBase;
  final bool soloSinBggId;

  const JuegoPickerSheet({
    super.key,
    required this.title,
    required this.hint,
    this.soloBase = false,
    this.soloSinBggId = false,
  });

  static Future<Juego?> show(
    BuildContext context, {
    String title = 'Seleccionar juego',
    String hint = 'Buscar juego...',
    bool soloBase = false,
    bool soloSinBggId = false,
  }) {
    return showModalBottomSheet<Juego>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: JuegoPickerSheet(
          title: title,
          hint: hint,
          soloBase: soloBase,
          soloSinBggId: soloSinBggId,
        ),
      ),
    );
  }

  @override
  State<JuegoPickerSheet> createState() => _JuegoPickerSheetState();
}

class _JuegoPickerSheetState extends State<JuegoPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<Juego> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final provider = context.read<JuegosProvider>();
    final results = await provider.juegoRepository.search(
      buscar: q.trim(),
      perPage: 30,
      soloBase: widget.soloBase,
      soloSinBggId: widget.soloSinBggId,
    );
    if (mounted) {
      setState(() {
        _results = results;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _results
                    .map(
                      (j) => ListTile(
                        title: Text(j.nombre),
                        subtitle: j.bggId != null
                            ? Text('BGG #${j.bggId}')
                            : null,
                        onTap: () => Navigator.of(context).pop(j),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
