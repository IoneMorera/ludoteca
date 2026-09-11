import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../data/propietario_repository.dart';
import '../models/juego.dart';
import '../providers/juegos_provider.dart';
import '../providers/sync_provider.dart';
import '../utils/text_normalize.dart';
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
  final _searchPersonal = TextEditingController();
  final _searchConjunta = TextEditingController();
  String _queryPersonal = '';
  String _queryConjunta = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    SchedulerBinding.instance.addPostFrameCallback((_) => _fetchPropietarios());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchPersonal.dispose();
    _searchConjunta.dispose();
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

  List<Juego> _filtrar(List<Juego> juegos, String query) {
    final q = normalizeText(query.trim());
    if (q.isEmpty) return juegos;
    return juegos
        .where((j) => normalizeText(j.nombre).contains(q))
        .toList();
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onChanged: onChanged,
      ),
    );
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
    final filtrados = _filtrar(_coleccionPersonal, _queryPersonal);
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
        _buildSearchField(
          controller: _searchPersonal,
          hint: 'Buscar en esta colección...',
          onChanged: (v) => setState(() => _queryPersonal = v),
        ),
        if (!_loadingPersonal && _coleccionPersonal.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _queryPersonal.trim().isEmpty
                    ? '${_coleccionPersonal.length} juegos'
                    : '${filtrados.length} de ${_coleccionPersonal.length} juegos',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
          ),
        Expanded(
          child: _loadingPersonal
              ? const Center(child: CircularProgressIndicator())
              : filtrados.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _sincronizarYRecargar,
                      child: ListView(
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              _coleccionPersonal.isEmpty
                                  ? 'No hay juegos en esta colección'
                                  : 'Ningún juego coincide con la búsqueda',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _sincronizarYRecargar,
                      child: ListView.builder(
                        itemCount: filtrados.length,
                        itemBuilder: (ctx, i) =>
                            _buildJuegoTile(filtrados[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildConjuntaTab() {
    final filtrados = _filtrar(_coleccionConjunta, _queryConjunta);
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
        _buildSearchField(
          controller: _searchConjunta,
          hint: 'Buscar en la colección conjunta...',
          onChanged: (v) => setState(() => _queryConjunta = v),
        ),
        if (!_loadingConjunta && _coleccionConjunta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _queryConjunta.trim().isEmpty
                    ? '${_coleccionConjunta.length} juegos únicos'
                    : '${filtrados.length} de ${_coleccionConjunta.length} juegos',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
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
                  : filtrados.isEmpty
                      ? Center(
                          child: Text(
                            _coleccionConjunta.isEmpty
                                ? 'No hay juegos en la colección conjunta'
                                : 'Ningún juego coincide con la búsqueda',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _sincronizarYRecargar,
                          child: ListView.builder(
                            itemCount: filtrados.length,
                            itemBuilder: (ctx, i) =>
                                _buildJuegoTile(filtrados[i]),
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
