class EventoEstado {
  static const abierto = 'abierto';
  static const pendienteColocar = 'pendiente_colocar';
  static const cerrado = 'cerrado';
}

class Evento {
  final int? localId;
  final int? serverId;
  final String nombre;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String localizacion;
  final String estado;
  final String? updatedAt;
  final bool dirty;
  final List<EventoJuego> juegos;

  const Evento({
    this.localId,
    this.serverId,
    required this.nombre,
    required this.fechaInicio,
    required this.fechaFin,
    required this.localizacion,
    this.estado = EventoEstado.abierto,
    this.updatedAt,
    this.dirty = false,
    this.juegos = const [],
  });

  /// Estado efectivo según fecha y estado persistido.
  String get effectiveEstado {
    if (estado == EventoEstado.abierto && fechaFin.isBefore(DateTime.now())) {
      return EventoEstado.pendienteColocar;
    }
    return estado;
  }

  bool get esFuturo =>
      effectiveEstado == EventoEstado.abierto && !fechaFin.isBefore(DateTime.now());

  bool get esEditable => effectiveEstado == EventoEstado.abierto;

  bool get puedeCerrar => effectiveEstado == EventoEstado.pendienteColocar;

  bool get esSoloLectura => effectiveEstado == EventoEstado.cerrado;

  Evento copyWith({
    int? localId,
    int? serverId,
    String? nombre,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? localizacion,
    String? estado,
    String? updatedAt,
    bool? dirty,
    List<EventoJuego>? juegos,
  }) {
    return Evento(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      nombre: nombre ?? this.nombre,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      localizacion: localizacion ?? this.localizacion,
      estado: estado ?? this.estado,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      juegos: juegos ?? this.juegos,
    );
  }

  factory Evento.fromMap(Map<String, dynamic> map, {List<EventoJuego> juegos = const []}) {
    return Evento(
      localId: map['local_id'] as int?,
      serverId: map['server_id'] as int?,
      nombre: map['nombre'] as String,
      fechaInicio: DateTime.parse(map['fecha_inicio'] as String),
      fechaFin: DateTime.parse(map['fecha_fin'] as String),
      localizacion: map['localizacion'] as String,
      estado: map['estado'] as String? ?? EventoEstado.abierto,
      updatedAt: map['updated_at'] as String?,
      dirty: ((map['dirty'] as int?) ?? 0) == 1,
      juegos: juegos,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'localizacion': localizacion,
      'estado': estado,
    };
  }
}

class EventoJuego {
  final int? localId;
  final int? serverId;
  final int eventoLocalId;
  final int? eventoServerId;
  final int juegoLocalId;
  final int? juegoServerId;
  final String juegoNombre;
  final String? juegoImagen;

  const EventoJuego({
    this.localId,
    this.serverId,
    required this.eventoLocalId,
    this.eventoServerId,
    required this.juegoLocalId,
    this.juegoServerId,
    required this.juegoNombre,
    this.juegoImagen,
  });

  factory EventoJuego.fromMap(Map<String, dynamic> map) {
    return EventoJuego(
      localId: map['local_id'] as int?,
      serverId: map['server_id'] as int?,
      eventoLocalId: map['evento_local_id'] as int,
      eventoServerId: map['evento_server_id'] as int?,
      juegoLocalId: map['juego_local_id'] as int,
      juegoServerId: map['juego_server_id'] as int?,
      juegoNombre: map['juego_nombre'] as String? ?? '',
      juegoImagen: map['juego_imagen'] as String?,
    );
  }
}
