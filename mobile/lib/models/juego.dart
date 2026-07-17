import '../config/api_config.dart';

class Juego {
  /// `id` legacy: cuando viene del servidor es `serverId`. Para registros
  /// solo-locales (a\u00fan no sincronizados) es `-localId` para evitar colisiones.
  final int id;

  /// Identificador local autoincremental en SQLite (null si solo viene de
  /// una respuesta directa del API sin pasar por la cache local).
  final int? localId;

  /// Identificador remoto en la BBDD del backend (null hasta que se sincroniza).
  final int? serverId;

  final String nombre;
  final String? descripcion;
  final String? imagen;
  final int? edadMinima;
  final int? edadMaxima;
  final int? numJugadoresMin;
  final int? numJugadoresMax;
  final int? categoriaId;
  final int? categoriaLocalId;
  final String? estado;
  final String? fechaCompra;
  final int? juegoBaseId;
  final int? juegoBaseLocalId;
  final int? juegoBaseServerId;
  final int? ubicacionLocalId;
  final int? bggId;
  final bool noEnfundar;
  final bool esExpansionFlag;
  final List<String> idiomas;
  final String? idiomaOtro;
  final bool independienteIdioma;
  final bool tradumaquetado;
  final bool tradumaquetadoParcial;
  final String? tradumaquetadoParcialNotas;
  final bool variasCopias;
  final double? precio;
  final bool enCajaBase;
  final bool sinAbrir;
  final bool printAndPlay;
  final String? phash;
  final String? imageLocalPath;
  final String? updatedAt;
  final bool dirty;
  final Categoria? categoria;
  final List<Categoria> categorias;
  final Ubicacion? ubicacion;
  final List<Propietario> propietarios;
  final List<Juego> expansiones;
  final List<JuegoFunda> fundas;
  final Juego? juegoBase;

  Juego({
    required this.id,
    required this.nombre,
    this.localId,
    this.serverId,
    this.descripcion,
    this.imagen,
    this.edadMinima,
    this.edadMaxima,
    this.numJugadoresMin,
    this.numJugadoresMax,
    this.categoriaId,
    this.categoriaLocalId,
    this.estado,
    this.fechaCompra,
    this.juegoBaseId,
    this.juegoBaseLocalId,
    this.juegoBaseServerId,
    this.ubicacionLocalId,
    this.bggId,
    this.noEnfundar = false,
    this.esExpansionFlag = false,
    this.idiomas = const [],
    this.idiomaOtro,
    this.independienteIdioma = false,
    this.tradumaquetado = false,
    this.tradumaquetadoParcial = false,
    this.tradumaquetadoParcialNotas,
    this.variasCopias = false,
    this.precio,
    this.enCajaBase = false,
    this.sinAbrir = false,
    this.printAndPlay = false,
    this.phash,
    this.imageLocalPath,
    this.updatedAt,
    this.dirty = false,
    this.categoria,
    this.categorias = const [],
    this.ubicacion,
    this.propietarios = const [],
    this.expansiones = const [],
    this.fundas = const [],
    this.juegoBase,
  });

  Juego copyWithJuegoBase(Juego? base) {
    return Juego(
      id: id,
      localId: localId,
      serverId: serverId,
      nombre: nombre,
      descripcion: descripcion,
      imagen: imagen,
      edadMinima: edadMinima,
      edadMaxima: edadMaxima,
      numJugadoresMin: numJugadoresMin,
      numJugadoresMax: numJugadoresMax,
      categoriaId: categoriaId,
      categoriaLocalId: categoriaLocalId,
      estado: estado,
      fechaCompra: fechaCompra,
      juegoBaseId: juegoBaseId,
      juegoBaseLocalId: juegoBaseLocalId,
      juegoBaseServerId: juegoBaseServerId,
      ubicacionLocalId: ubicacionLocalId,
      bggId: bggId,
      noEnfundar: noEnfundar,
      esExpansionFlag: esExpansionFlag,
      idiomas: idiomas,
      idiomaOtro: idiomaOtro,
      independienteIdioma: independienteIdioma,
      tradumaquetado: tradumaquetado,
      tradumaquetadoParcial: tradumaquetadoParcial,
      tradumaquetadoParcialNotas: tradumaquetadoParcialNotas,
      variasCopias: variasCopias,
      precio: precio,
      enCajaBase: enCajaBase,
      sinAbrir: sinAbrir,
      printAndPlay: printAndPlay,
      phash: phash,
      imageLocalPath: imageLocalPath,
      updatedAt: updatedAt,
      dirty: dirty,
      categoria: categoria,
      categorias: categorias,
      ubicacion: ubicacion,
      propietarios: propietarios,
      expansiones: expansiones,
      fundas: fundas,
      juegoBase: base,
    );
  }

  Juego copyWithExpansiones(List<Juego> list) {
    return Juego(
      id: id,
      localId: localId,
      serverId: serverId,
      nombre: nombre,
      descripcion: descripcion,
      imagen: imagen,
      edadMinima: edadMinima,
      edadMaxima: edadMaxima,
      numJugadoresMin: numJugadoresMin,
      numJugadoresMax: numJugadoresMax,
      categoriaId: categoriaId,
      categoriaLocalId: categoriaLocalId,
      estado: estado,
      fechaCompra: fechaCompra,
      juegoBaseId: juegoBaseId,
      juegoBaseLocalId: juegoBaseLocalId,
      juegoBaseServerId: juegoBaseServerId,
      ubicacionLocalId: ubicacionLocalId,
      bggId: bggId,
      noEnfundar: noEnfundar,
      esExpansionFlag: esExpansionFlag,
      idiomas: idiomas,
      idiomaOtro: idiomaOtro,
      independienteIdioma: independienteIdioma,
      tradumaquetado: tradumaquetado,
      tradumaquetadoParcial: tradumaquetadoParcial,
      tradumaquetadoParcialNotas: tradumaquetadoParcialNotas,
      variasCopias: variasCopias,
      precio: precio,
      enCajaBase: enCajaBase,
      sinAbrir: sinAbrir,
      printAndPlay: printAndPlay,
      phash: phash,
      imageLocalPath: imageLocalPath,
      updatedAt: updatedAt,
      dirty: dirty,
      categoria: categoria,
      categorias: categorias,
      ubicacion: ubicacion,
      propietarios: propietarios,
      expansiones: list,
      fundas: fundas,
      juegoBase: juegoBase,
    );
  }

  factory Juego.fromJson(Map<String, dynamic> json) {
    return Juego(
      id: json['id'] ?? 0,
      serverId: json['id'] is int ? json['id'] as int : null,
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'],
      imagen: json['imagen'],
      edadMinima: json['edad_minima'],
      edadMaxima: json['edad_maxima'],
      numJugadoresMin: json['num_jugadores_min'],
      numJugadoresMax: json['num_jugadores_max'],
      categoriaId: json['categoria_id'],
      estado: json['estado'],
      fechaCompra: json['fecha_compra'],
      juegoBaseId: json['juego_base_id'],
      juegoBaseServerId: json['juego_base_id'],
      bggId: json['bgg_id'],
      noEnfundar: json['no_enfundar'] == true || json['no_enfundar'] == 1,
      esExpansionFlag: json['es_expansion'] == true || json['es_expansion'] == 1,
      idiomas: (json['idiomas'] as List?)?.cast<String>() ?? [],
      idiomaOtro: json['idioma_otro'],
      independienteIdioma: json['independiente_idioma'] == true || json['independiente_idioma'] == 1,
      tradumaquetado: json['tradumaquetado'] == true || json['tradumaquetado'] == 1,
      tradumaquetadoParcial: json['tradumaquetado_parcial'] == true || json['tradumaquetado_parcial'] == 1,
      tradumaquetadoParcialNotas: json['tradumaquetado_parcial_notas'],
      variasCopias: json['varias_copias'] == true || json['varias_copias'] == 1,
      precio: (json['precio'] is num) ? (json['precio'] as num).toDouble() : null,
      enCajaBase: json['en_caja_base'] == true || json['en_caja_base'] == 1,
      sinAbrir: json['sin_abrir'] == true || json['sin_abrir'] == 1,
      printAndPlay: json['print_and_play'] == true || json['print_and_play'] == 1,
      updatedAt: json['updated_at'],
      categoria: json['categoria'] != null
          ? Categoria.fromJson(json['categoria'])
          : null,
      categorias: (json['categorias'] as List?)
              ?.map((c) => Categoria.fromJson(c))
              .toList() ??
          [],
      ubicacion: json['ubicacion'] != null
          ? Ubicacion.fromJson(json['ubicacion'])
          : null,
      propietarios: (json['propietarios'] as List?)
              ?.map((p) => Propietario.fromJson(p))
              .toList() ??
          [],
      expansiones: (json['expansiones'] as List?)
              ?.map((e) => Juego.fromJson(e))
              .toList() ??
          [],
      fundas: (json['fundas'] as List?)
              ?.map((f) => JuegoFunda.fromJson(f))
              .toList() ??
          [],
      juegoBase: json['juego_base'] != null
          ? Juego.fromJson(json['juego_base'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'descripcion': descripcion,
        'edad_minima': edadMinima,
        'edad_maxima': edadMaxima,
        'num_jugadores_min': numJugadoresMin,
        'num_jugadores_max': numJugadoresMax,
        'categoria_ids': categorias.map((c) => c.id).toList(),
        'estado': estado,
        'fecha_compra': fechaCompra,
        'juego_base_id': juegoBaseServerId ?? juegoBaseId,
        'ubicacion_id': ubicacion?.id,
        'no_enfundar': noEnfundar,
        'es_expansion': esExpansionFlag,
        'idiomas': idiomas,
        'idioma_otro': idiomaOtro,
        'independiente_idioma': independienteIdioma,
        'tradumaquetado': tradumaquetado,
        'tradumaquetado_parcial': tradumaquetadoParcial,
        'tradumaquetado_parcial_notas': tradumaquetadoParcialNotas,
        'varias_copias': variasCopias,
        'precio': precio,
        'en_caja_base': enCajaBase,
        'sin_abrir': sinAbrir,
        'print_and_play': printAndPlay,
        'propietario_ids': propietarios.map((p) => p.id).toList(),
        'fundas': fundas.map((f) => f.toJson()).toList(),
      };

  bool get esExpansion => esExpansionFlag;
  String get jugadoresTexto =>
      '${numJugadoresMin ?? '?'}\u2013${numJugadoresMax ?? '?'}';
  String get edadTexto => '${edadMinima ?? '?'}+';

  String? get imagenUrl {
    if (imagen == null || imagen!.isEmpty) return null;
    if (imagen!.startsWith('http://') || imagen!.startsWith('https://')) {
      return imagen;
    }
    final path = imagen!.startsWith('/') ? imagen! : '/$imagen';
    return '${ApiConfig.storageUrl}$path';
  }
}

class JuegoFunda {
  final int id;
  final int tipoFundaId;
  final int cantidadCartas;
  final bool enfundadas;
  final TipoFunda? tipoFunda;

  JuegoFunda({
    required this.id,
    required this.tipoFundaId,
    required this.cantidadCartas,
    required this.enfundadas,
    this.tipoFunda,
  });

  factory JuegoFunda.fromJson(Map<String, dynamic> json) {
    return JuegoFunda(
      id: _asInt(json['id']),
      tipoFundaId: _asInt(json['tipo_funda_id']),
      cantidadCartas: _asInt(json['cantidad_cartas']),
      enfundadas: json['enfundadas'] == true || json['enfundadas'] == 1,
      tipoFunda: json['tipo_funda'] != null
          ? TipoFunda.fromJson(json['tipo_funda'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo_funda_id': tipoFundaId,
        'cantidad_cartas': cantidadCartas,
        'enfundadas': enfundadas,
      };

  String get tipoTexto {
    if (tipoFunda == null) return 'Tipo no disponible';
    return tipoFunda!.textoCompleto;
  }
}

class TipoFunda {
  final int id;
  final String nombre;
  final int anchoMm;
  final int altoMm;

  TipoFunda({
    required this.id,
    required this.nombre,
    required this.anchoMm,
    required this.altoMm,
  });

  factory TipoFunda.fromJson(Map<String, dynamic> json) {
    return TipoFunda(
      id: _asInt(json['id']),
      nombre: json['nombre'] ?? '',
      anchoMm: _asInt(json['ancho_mm']),
      altoMm: _asInt(json['alto_mm']),
    );
  }

  String get textoCompleto => '$nombre ($anchoMm x $altoMm mm)';
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class Categoria {
  final int id;
  final String nombre;

  Categoria({required this.id, required this.nombre});

  factory Categoria.fromJson(Map<String, dynamic> json) {
    return Categoria(id: json['id'], nombre: json['nombre'] ?? '');
  }
}

class Propietario {
  final int id;
  final String nombre;
  final String? bggUsername;
  final bool esPrincipal;

  Propietario({
    required this.id,
    required this.nombre,
    this.bggUsername,
    this.esPrincipal = false,
  });

  factory Propietario.fromJson(Map<String, dynamic> json) {
    return Propietario(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      bggUsername: json['bgg_username'],
      esPrincipal: json['es_principal'] == true || json['es_principal'] == 1,
    );
  }
}

class Ubicacion {
  final int id;
  final String nombre;
  final Mueble? mueble;

  Ubicacion({required this.id, required this.nombre, this.mueble});

  factory Ubicacion.fromJson(Map<String, dynamic> json) {
    return Ubicacion(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      mueble:
          json['mueble'] != null ? Mueble.fromJson(json['mueble']) : null,
    );
  }

  String get rutaCompleta {
    if (mueble == null) return nombre;
    return '${mueble!.habitacion?.nombre ?? ''} \u203a ${mueble!.nombre} \u203a $nombre';
  }
}

class Mueble {
  final int id;
  final String nombre;
  final Habitacion? habitacion;

  Mueble({required this.id, required this.nombre, this.habitacion});

  factory Mueble.fromJson(Map<String, dynamic> json) {
    return Mueble(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      habitacion: json['habitacion'] != null
          ? Habitacion.fromJson(json['habitacion'])
          : null,
    );
  }
}

class Habitacion {
  final int id;
  final String nombre;

  Habitacion({required this.id, required this.nombre});

  factory Habitacion.fromJson(Map<String, dynamic> json) {
    return Habitacion(id: json['id'], nombre: json['nombre'] ?? '');
  }
}
