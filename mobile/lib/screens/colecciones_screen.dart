import 'package:flutter/material.dart';
import '../models/juego.dart';
import '../services/api_service.dart';
import '../widgets/game_image.dart';

class ColeccionesScreen extends StatefulWidget {
  const ColeccionesScreen({super.key});

  @override
  State<ColeccionesScreen> createState() => _ColeccionesScreenState();
}

class _ColeccionesScreenState extends State<ColeccionesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _api = ApiService();

  List<Propietario> _propietarios = [];
  bool _loadingPropietarios = true;

  // Personal
  List<Juego> _coleccionPersonal = [];
  bool _loadingPersonal = false;
  int? _propietarioSeleccionadoId;
  int _personalPage = 1;
  int _personalLastPage = 1;
  int _personalTotal = 0;
  bool _loadingMorePersonal = false;
  final ScrollController _personalScrollController = ScrollController();

  // Conjunta
  List<Juego> _coleccionConjunta = [];
  bool _loadingConjunta = false;
  List<int> _propietariosConjuntaIds = [];
  int _conjuntaPage = 1;
  int _conjuntaLastPage = 1;
  int _conjuntaTotal = 0;
  bool _loadingMoreConjunta = false;
  final ScrollController _conjuntaScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _personalScrollController.addListener(_onPersonalScroll);
    _conjuntaScrollController.addListener(_onConjuntaScroll);
    _fetchPropietarios();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _personalScrollController.dispose();
    _conjuntaScrollController.dispose();
    super.dispose();
  }

  void _onPersonalScroll() {
    if (_personalScrollController.position.pixels >=
            _personalScrollController.position.maxScrollExtent - 200 &&
        !_loadingMorePersonal &&
        _personalPage < _personalLastPage) {
      _fetchColeccionPersonal(_propietarioSeleccionadoId!, page: _personalPage + 1, append: true);
    }
  }

  void _onConjuntaScroll() {
    if (_conjuntaScrollController.position.pixels >=
            _conjuntaScrollController.position.maxScrollExtent - 200 &&
        !_loadingMoreConjunta &&
        _conjuntaPage < _conjuntaLastPage) {
      _fetchColeccionConjunta(page: _conjuntaPage + 1, append: true);
    }
  }

  Future<void> _fetchPropietarios() async {
    try {
      final response = await _api.get('/propietarios');
      final propietarios = (response.data as List)
          .map((p) => Propietario.fromJson(p))
          .toList();

      final principal = propietarios.where((p) => p.esPrincipal).firstOrNull;
      final defaultId = principal?.id ?? propietarios.firstOrNull?.id;

      setState(() {
        _propietarios = propietarios;
        _loadingPropietarios = false;
        _propietarioSeleccionadoId = defaultId;
        _propietariosConjuntaIds = [];
      });

      if (defaultId != null) {
        _fetchColeccionPersonal(defaultId);
      }
    } catch (_) {
      setState(() => _loadingPropietarios = false);
    }
  }

  Future<void> _fetchColeccionPersonal(int propietarioId, {int page = 1, bool append = false}) async {
    if (append) {
      setState(() => _loadingMorePersonal = true);
    } else {
      setState(() => _loadingPersonal = true);
    }
    try {
      final response = await _api.get('/juegos', params: {
        'propietario_id': propietarioId,
        'solo_base': '1',
        'per_page': '30',
        'page': page,
      });
      final data = response.data;
      final juegosRaw = data['data'] as List? ?? [];
      final parsed = juegosRaw.map((j) => Juego.fromJson(j as Map<String, dynamic>)).toList();
      setState(() {
        if (append) {
          _coleccionPersonal.addAll(parsed);
        } else {
          _coleccionPersonal = parsed;
        }
        _personalPage = data['current_page'] ?? 1;
        _personalLastPage = data['last_page'] ?? 1;
        _personalTotal = data['total'] ?? 0;
        _loadingPersonal = false;
        _loadingMorePersonal = false;
      });
    } catch (e) {
      debugPrint('COLECCION ERROR personal: $e');
      setState(() {
        if (!append) _coleccionPersonal = [];
        _loadingPersonal = false;
        _loadingMorePersonal = false;
      });
    }
  }

  Future<void> _fetchColeccionConjunta({int page = 1, bool append = false}) async {
    if (_propietariosConjuntaIds.isEmpty) {
      setState(() {
        _coleccionConjunta = [];
        _conjuntaTotal = 0;
      });
      return;
    }
    if (append) {
      setState(() => _loadingMoreConjunta = true);
    } else {
      setState(() => _loadingConjunta = true);
    }
    try {
      final Set<int> seenIds = append
          ? _coleccionConjunta.map((j) => j.id).toSet()
          : {};
      final List<Juego> allGames = append ? List.from(_coleccionConjunta) : [];
      int maxLastPage = 1;
      int total = 0;

      for (final id in _propietariosConjuntaIds) {
        final response = await _api.get('/juegos', params: {
          'propietario_id': id,
          'solo_base': '1',
          'per_page': '30',
          'page': page,
        });
        final data = response.data;
        final juegosRaw = data['data'] as List? ?? [];
        final lp = data['last_page'] ?? 1;
        if (lp > maxLastPage) maxLastPage = lp;
        total += (data['total'] as int? ?? 0);

        for (final j in juegosRaw) {
          final juego = Juego.fromJson(j as Map<String, dynamic>);
          if (!seenIds.contains(juego.id)) {
            seenIds.add(juego.id);
            allGames.add(juego);
          }
        }
      }

      allGames.sort((a, b) => a.nombre.compareTo(b.nombre));

      setState(() {
        _coleccionConjunta = allGames;
        _conjuntaPage = page;
        _conjuntaLastPage = maxLastPage;
        _conjuntaTotal = total;
        _loadingConjunta = false;
        _loadingMoreConjunta = false;
      });
    } catch (e) {
      debugPrint('COLECCION ERROR conjunta: $e');
      setState(() {
        if (!append) _coleccionConjunta = [];
        _loadingConjunta = false;
        _loadingMoreConjunta = false;
      });
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
            value: _propietarioSeleccionadoId,
            decoration: const InputDecoration(
              labelText: 'Propietario',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: _propietarios
                .map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text('${p.nombre}${p.esPrincipal ? ' (Principal)' : ''}')))
                .toList(),
            onChanged: (id) {
              if (id == null) return;
              setState(() => _propietarioSeleccionadoId = id);
              _fetchColeccionPersonal(id);
            },
          ),
        ),
        if (_personalTotal > 0 && !_loadingPersonal)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('$_personalTotal juegos',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ),
          ),
        Expanded(
          child: _loadingPersonal
              ? const Center(child: CircularProgressIndicator())
              : _coleccionPersonal.isEmpty
                  ? const Center(
                      child: Text('No hay juegos en esta colección',
                          style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: () => _fetchColeccionPersonal(
                          _propietarioSeleccionadoId!),
                      child: ListView.builder(
                        controller: _personalScrollController,
                        itemCount: _coleccionPersonal.length + (_loadingMorePersonal ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == _coleccionPersonal.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _buildJuegoTile(_coleccionPersonal[i]);
                        },
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
              final selected = _propietariosConjuntaIds.contains(p.id);
              return FilterChip(
                label: Text(p.nombre),
                selected: selected,
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _propietariosConjuntaIds.add(p.id);
                    } else {
                      _propietariosConjuntaIds.remove(p.id);
                    }
                  });
                  _fetchColeccionConjunta();
                },
              );
            }).toList(),
          ),
        ),
        if (_conjuntaTotal > 0 && !_loadingConjunta)
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
                      child: Text('Selecciona propietarios para ver la colección conjunta',
                          style: TextStyle(color: Colors.grey)))
                  : _coleccionConjunta.isEmpty
                      ? const Center(
                          child: Text('No hay juegos en la colección conjunta',
                              style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: () => _fetchColeccionConjunta(),
                          child: ListView.builder(
                            controller: _conjuntaScrollController,
                            itemCount: _coleccionConjunta.length + (_loadingMoreConjunta ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i == _coleccionConjunta.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return _buildJuegoTile(_coleccionConjunta[i]);
                            },
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
        trailing: juego.esExpansion
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Exp.',
                    style: TextStyle(fontSize: 10, color: Colors.blue[700])),
              )
            : null,
        onTap: () => Navigator.of(context).pushNamed('/juego', arguments: juego.id),
      ),
    );
  }
}
