import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../data/juego_repository.dart';
import '../models/juego.dart';
import '../providers/juegos_provider.dart';
import '../widgets/game_image.dart';

/// Tipos de aviso de la pantalla de Inicio que listan juegos.
enum JuegoAvisoTipo { porEstrenar, faltanTraduccion, expansionOtroIdioma }

/// Pantalla gen\u00e9rica que lista los juegos de un aviso concreto (por estrenar
/// o pendientes de tradumaquetar), similar a la de fundas faltantes.
class JuegosAvisoScreen extends StatefulWidget {
  final JuegoAvisoTipo tipo;

  const JuegosAvisoScreen({super.key, required this.tipo});

  @override
  State<JuegosAvisoScreen> createState() => _JuegosAvisoScreenState();
}

class _JuegosAvisoScreenState extends State<JuegosAvisoScreen> {
  bool _loading = true;
  List<Juego> _juegos = [];
  List<ExpansionIdiomaAviso> _avisosExpansion = [];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = context.read<JuegosProvider>().juegoRepository;
    if (widget.tipo == JuegoAvisoTipo.expansionOtroIdioma) {
      final avisos = await repo.juegosConExpansionOtroIdioma();
      if (mounted) {
        setState(() {
          _avisosExpansion = avisos;
          _loading = false;
        });
      }
      return;
    }
    final juegos = widget.tipo == JuegoAvisoTipo.porEstrenar
        ? await repo.juegosPorEstrenar()
        : await repo.juegosFaltanTraduccion();
    if (mounted) {
      setState(() {
        _juegos = juegos;
        _loading = false;
      });
    }
  }

  int get _count => widget.tipo == JuegoAvisoTipo.expansionOtroIdioma
      ? _avisosExpansion.length
      : _juegos.length;

  bool get _isEmpty => widget.tipo == JuegoAvisoTipo.expansionOtroIdioma
      ? _avisosExpansion.isEmpty
      : _juegos.isEmpty;

  String get _titulo {
    switch (widget.tipo) {
      case JuegoAvisoTipo.porEstrenar:
        return 'Juegos Por Estrenar';
      case JuegoAvisoTipo.faltanTraduccion:
        return 'Faltan Traducciones';
      case JuegoAvisoTipo.expansionOtroIdioma:
        return 'Expansiones en Otro Idioma';
    }
  }

  String get _emptyText {
    switch (widget.tipo) {
      case JuegoAvisoTipo.porEstrenar:
        return 'No tienes juegos por estrenar';
      case JuegoAvisoTipo.faltanTraduccion:
        return 'No hay juegos pendientes de traducir';
      case JuegoAvisoTipo.expansionOtroIdioma:
        return 'No hay expansiones en otro idioma';
    }
  }

  Color get _color {
    switch (widget.tipo) {
      case JuegoAvisoTipo.porEstrenar:
        return Colors.teal;
      case JuegoAvisoTipo.faltanTraduccion:
        return Colors.indigo;
      case JuegoAvisoTipo.expansionOtroIdioma:
        return Colors.deepOrange;
    }
  }

  IconData get _icon {
    switch (widget.tipo) {
      case JuegoAvisoTipo.porEstrenar:
        return Icons.card_giftcard;
      case JuegoAvisoTipo.faltanTraduccion:
        return Icons.translate;
      case JuegoAvisoTipo.expansionOtroIdioma:
        return Icons.language;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titulo)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 96),
                        Icon(Icons.check_circle, size: 64, color: Colors.green),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            _emptyText,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          elevation: 0,
                          color: _color.withValues(alpha: 0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                                color: _color.withValues(alpha: 0.35)),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _color.withValues(alpha: 0.15),
                              child: Icon(_icon, color: _color),
                            ),
                            title: Text(
                              _titulo,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('$_count juegos'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.tipo ==
                            JuegoAvisoTipo.expansionOtroIdioma) ...[
                          ..._avisosExpansion.map(_buildExpansionAvisoTile),
                        ] else ...[
                          ..._juegos.map(_buildJuegoTile),
                        ],
                      ],
                    ),
            ),
    );
  }

  Widget _buildExpansionAvisoTile(ExpansionIdiomaAviso aviso) {
    final base = aviso.base;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: GameImage(
              juego: base,
              width: 48,
              height: 48,
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text(base.nombre,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Base: ${_idiomasTexto(base)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .pushNamed('/juego', arguments: base.localId ?? base.id),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: aviso.expansiones.map((exp) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right,
                          size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${exp.nombre} \u00b7 ${_idiomasTexto(exp)}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[800]),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJuegoTile(Juego juego) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: GameImage(
          juego: juego,
          width: 48,
          height: 48,
          borderRadius: BorderRadius.circular(8),
        ),
        title: Text(juego.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: widget.tipo == JuegoAvisoTipo.faltanTraduccion
            ? Text(_idiomasTexto(juego))
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .pushNamed('/juego', arguments: juego.localId ?? juego.id),
      ),
    );
  }

  String _idiomasTexto(Juego juego) {
    if (juego.idiomas.isEmpty) return 'Sin idioma indicado';
    const labels = {
      'castellano': 'Castellano',
      'catalan': 'Catal\u00e1n',
      'ingles': 'Ingl\u00e9s',
      'frances': 'Franc\u00e9s',
      'aleman': 'Alem\u00e1n',
      'portugues': 'Portugu\u00e9s',
      'otros': 'Otros',
    };
    final texto =
        juego.idiomas.map((i) => labels[i] ?? i).join(', ');
    return juego.tradumaquetadoParcial
        ? '$texto \u00b7 Tradu. parcial'
        : texto;
  }
}
