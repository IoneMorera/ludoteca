import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/evento.dart';
import '../providers/eventos_provider.dart';

class EventoFormScreen extends StatefulWidget {
  const EventoFormScreen({super.key});

  @override
  State<EventoFormScreen> createState() => _EventoFormScreenState();
}

class _EventoFormScreenState extends State<EventoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _localizacionCtrl = TextEditingController();
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  bool _saving = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _localizacionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required bool isInicio,
  }) async {
    final initial = isInicio
        ? (_fechaInicio ?? DateTime.now())
        : (_fechaFin ?? _fechaInicio ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'ES'),
    );
    if (picked == null) return;
    setState(() {
      if (isInicio) {
        _fechaInicio = DateTime(picked.year, picked.month, picked.day);
        if (_fechaFin != null && _fechaFin!.isBefore(_fechaInicio!)) {
          _fechaFin = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      } else {
        _fechaFin = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fechaInicio == null || _fechaFin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona las fechas de inicio y fin')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final evento = Evento(
        nombre: _nombreCtrl.text.trim(),
        fechaInicio: _fechaInicio!,
        fechaFin: _fechaFin!,
        localizacion: _localizacionCtrl.text.trim(),
      );
      await context.read<EventosProvider>().saveEvento(evento);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Seleccionar';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo evento'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'El nombre es obligatorio' : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha de inicio'),
              subtitle: Text(_formatDate(_fechaInicio)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(isInicio: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha de fin'),
              subtitle: Text(_formatDate(_fechaFin)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(isInicio: false),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _localizacionCtrl,
              decoration: const InputDecoration(
                labelText: 'Localización',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'La localización es obligatoria'
                  : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _guardar,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar evento'),
            ),
          ],
        ),
      ),
    );
  }
}
