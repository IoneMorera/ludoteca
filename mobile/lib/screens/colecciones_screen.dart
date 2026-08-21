import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../data/propietario_repository.dart';
import '../models/juego.dart';
import '../providers/juegos_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/game_image.dart';

class ColeccionesScreen extends StatefulWidget {
  const ColeccionesScreen({super.key});

  @override
  State<ColeccionesScreen> createState() => _ColeccionesScreenState();
}

class _ColeccionesScreenState extends State<ColeccionesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<PropietarioRow> _propietarios = [];
  bool _loadingPropietarios = true;

  // Personal
  List<Juego> _coleccionPersonal = [];
  bool _loadingPersonal = false;
  int? _propietarioSeleccionadoId;

  // Conjunta
  List<Juego> _coleccionConjunta = [];
  bool _loadingConjunta = false;
  final List<int> _propietariosConjuntaIds = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    SchedulerBinding.instance.addPostFrameCallback((_) => _fetchPropietarios());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchPropietarios() async {
    setState(() => _loadingPropietarios = true);
    try {
      final repo = context.read<JuegosProvider>().propietarioRepository;
      final propietarios = await repo.getAll();

      final principal =
          propietarios.where((p) => p.esPrincipal).firstOrNull;
      final defaultId = principal?.localId ?? propietarios.firstOrNull?.localId;

      if (!mounted) return;
      setState(() {
        _propietarios = propietarios;
        _loadingPropietarios = false;
        _propietarioSeleccionadoId = defaultId;
      });

      if (defaultId != null) {
        _fetchColeccionPersonal(defaultId);
      }
    } catch (e) {
      debugPrint('COLECCION propietarios error: $e');
      if (mounted) setState(() => _loadingPropietarios = false);
    }
  }

  Future<void> _fetchColeccionPersonal(int propietarioLocalId) async {
    setState(() => _loadingPersonal = true);
    try {
      final repo = context.read<JuegosProvider>().juegoRepository;
      final juegos = await repo.search(
        soloBase: true,
        propietarioLocalId: propietarioLocalId,
        page: 1,
        perPage: 100000,
      );
      if (!mounted) return;
      setState(() {
        _coleccionPersonal = juegos;
        _loadingPersonal = false;
      });
    } catch (e) {
      debugPrint('COLECCION personal error: $e');
      if (mounted) {
        setState(() {
          _coleccionPersonal = [];
          _loadingPersonal = false;
        });
      }
    }
  }

  Future<void> _fetchColeccionConjunta() async {
    if (_propietariosConjuntaIds.isEmpty) {
      setState(() => _coleccionConjunta = []);
      return;
    }
    setState(() => _loadingConjunta = true);
    try {
      final repo = context.read<JuegosProvider>().juegoRepository;
      final juegos = await repo.search(
        soloBase: true,
        propietarioLocalIds: List.of(_propietariosConjuntaIds),
        page: 1,
        perPage: 100000,
      );
      if (!mounted) return;
      setState(() {
        _coleccionConjunta = juegos;
        _loadingConjunta = false;
      });
    } catch (e) {
      debugPrint('COLECCION conjunta error: $e');
      if (mounted) {
        setState(() {
          _coleccionConjunta = [];
          _loadingConjunta = false;
        });
      }
    }
  }

  Future<void> _sincronizarYRecargar() async {
    try {
      await context.read<SyncProvider>().syncNow();
    } catch (_) {}
    await _fetchPropietarios();
    if (_propietariosConjuntaIds.isNotEmpty) {
      await _fetchColeccionConjunta();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Colecciones'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Personal'),
            Tab(text: 'Conjunta'),
          ],
        ),
      ),
      body: _loadingPropietarios
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPersonalTab(),
                _buildConjuntaTab(),
              ],
            ),
    );
  }

  Widget _buildPersonalTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<int>(
            key: ValueKey('dropdown_$_propietarioSeleccionadoId'),
            initialValue: _propietarioSeleccionadoId,
            decoration: const InputDecoration(
              labelText: 'Propietario',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: _propietarios
                .map((p) => DropdownMenuItem(
                    value: p.localId,
                    child: Text(
                        '${p.nombre}${p.esPrincipal ? ' (Principal)' : ''}')))
                .toList(),
            onChanged: (id) {
              if (id == null) return;
              setState(() => _propietarioSeleccionadoId = id);
              _fetchColeccionPersonal(id);
            },
          ),
        ),
        if (!_loadingPersonal && _coleccionPersonal.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_coleccionPersonal.length} juegos',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ),
          ),
        Expanded(
          child: _loadingPersonal
              ? const Center(child: CircularProgressIndicator())
              : _coleccionPersonal.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _sincronizarYRecargar,
                      child: ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text('No hay juegos en esta colección',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _sincronizarYRecargar,
                      child: ListView.builder(
                        itemCount: _coleccionPersonal.length,
                        itemBuilder: (ctx, i) =>
                            _buildJuegoTile(_coleccionPersonal[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildConjuntaTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: _propietarios.map((p) {
              final selected = _propietariosConjuntaIds.contains(p.localId);
              return FilterChip(
                label: Text(p.nombre),
                selected: selected,
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _propietariosConjuntaIds.add(p.localId);
                    } else {
                      _propietariosConjuntaIds.remove(p.localId);
                    }
                  });
                  _fetchColeccionConjunta();
                },
              );
            }).toList(),
          ),
        ),
        if (!_loadingConjunta && _coleccionConjunta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_coleccionConjunta.length} juegos únicos',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ),
          ),
        Expanded(
          child: _loadingConjunta
              ? const Center(child: CircularProgressIndicator())
              : _propietariosConjuntaIds.isEmpty
                  ? const Center(
                      child: Text(
                          'Selecciona propietarios para ver la colección conjunta',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)))
                  : _coleccionConjunta.isEmpty
                      ? const Center(
                          child: Text('No hay juegos en la colección conjunta',
                              style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _sincronizarYRecargar,
                          child: ListView.builder(
                            itemCount: _coleccionConjunta.length,
                            itemBuilder: (ctx, i) =>
                                _buildJuegoTile(_coleccionConjunta[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildJuegoTile(Juego juego) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: GameImage(
          juego: juego,
          width: 44,
          height: 44,
        ),
        title: Text(juego.nombre,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          [
            if (juego.categoria != null) juego.categoria!.nombre,
            juego.jugadoresTexto,
          ].join(' · '),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: (juego.esExpansion || juego.autojugable)
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (juego.esExpansion)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Exp.',
                          style:
                              TextStyle(fontSize: 10, color: Colors.blue[700])),
                    ),
                  if (juego.autojugable) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Autojugable',
                          style: TextStyle(
                              fontSize: 10, color: Colors.indigo[700])),
                    ),
                  ],
                ],
              )
            : null,
        onTap: () => Navigator.of(context).pushNamed(
          '/juego',
          arguments: juego.localId ?? juego.id,
        ),
      ),
    );
  }
}
