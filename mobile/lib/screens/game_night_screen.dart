import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/juegos_provider.dart';
import '../models/juego.dart';
import '../services/database_service.dart';
import '../models/partida.dart';
import '../widgets/game_image.dart';

class GameNightScreen extends StatefulWidget {
  const GameNightScreen({super.key});

  @override
  State<GameNightScreen> createState() => _GameNightScreenState();
}

class _GameNightScreenState extends State<GameNightScreen> {
  int _numJugadores = 2;
  int _edadMinima = 0;
  List<Juego> _resultados = [];
  Juego? _sugerencia;
  bool _searched = false;
  bool _loading = false;

  Future<void> _buscar() async {
    setState(() {
      _loading = true;
      _searched = true;
      _sugerencia = null;
    });

    final provider = context.read<JuegosProvider>();
    await provider.fetchJuegos();

    final juegos = provider.juegos.where((j) {
      if (j.esExpansion && !j.autojugable) return false;
      final minOk =
          j.numJugadoresMin == null || j.numJugadoresMin! <= _numJugadores;
      final maxOk =
          j.numJugadoresMax == null || j.numJugadoresMax! >= _numJugadores;
      final edadOk =
          _edadMinima == 0 || j.edadMinima == null || j.edadMinima! <= _edadMinima;
      return minOk && maxOk && edadOk;
    }).toList();

    setState(() {
      _resultados = juegos;
      _loading = false;
      if (juegos.isNotEmpty) {
        _sugerencia = juegos[Random().nextInt(juegos.length)];
      }
    });
  }

  void _otroJuego() {
    if (_resultados.isEmpty) return;
    setState(() {
      _sugerencia = _resultados[Random().nextInt(_resultados.length)];
    });
  }

  Future<void> _registrarPartida(Juego juego) async {
    final partida = Partida(
      juegoId: juego.id,
      juegoNombre: juego.nombre,
      juegoImagen: juego.imagen,
      fecha: DateTime.now(),
      numJugadores: _numJugadores,
    );
    await DatabaseService().insertPartida(partida);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partida registrada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Planificar partida')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Cuántos jugadores?',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton.filled(
                        onPressed: _numJugadores > 1
                            ? () => setState(() => _numJugadores--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text('$_numJugadores',
                            style: theme.textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      IconButton.filled(
                        onPressed: () => setState(() => _numJugadores++),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Edad mínima del grupo',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Slider(
                    value: _edadMinima.toDouble(),
                    min: 0,
                    max: 18,
                    divisions: 18,
                    label: _edadMinima == 0
                        ? 'Cualquiera'
                        : '$_edadMinima años',
                    onChanged: (v) =>
                        setState(() => _edadMinima = v.round()),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _buscar,
                      icon: const Icon(Icons.search),
                      label: const Text('Buscar juegos'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_searched) ...[
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_sugerencia != null) ...[
              Text('Te sugerimos...',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildSugerenciaCard(_sugerencia!, theme),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _otroJuego,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Otro juego'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _registrarPartida(_sugerencia!),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Jugar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                  '${_resultados.length} juegos compatibles',
                  style: TextStyle(color: Colors.grey[600])),
            ] else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No hay juegos para estos criterios',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSugerenciaCard(Juego juego, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            GameImage(
              juego: juego,
              width: 80,
              height: 80,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(juego.nombre,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${juego.jugadoresTexto} jugadores · ${juego.edadTexto}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  if (juego.categoria != null)
                    Text(juego.categoria!.nombre,
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
