/// Modelo de configuración del dock flotante (v2).
///
/// Cada perfil ("bots" y "general") guarda su propia lista de elementos
/// (orden, visibilidad, destacado) y su propio [DockStyle] (bordes,
/// transparencia, profundidad): no se comparte estilo entre perfiles, según
/// corrección explícita del usuario sobre el primer draft.
library;

/// Forma de los bordes del dock y de sus elementos internos.
enum DockBorderShape {
  square,
  soft,
  rounded;

  /// Radio del contenedor exterior del dock, en dp.
  double get outerRadius => switch (this) {
    DockBorderShape.square => 4,
    DockBorderShape.soft => 12,
    DockBorderShape.rounded => 24,
  };

  /// Radio de cada celda/elemento interior: sigue al radio exterior con un
  /// margen fijo de 4dp, sin bajar de 0.
  double get innerRadius => (outerRadius - 4).clamp(0, outerRadius);

  static DockBorderShape parse(Object? value) => values.firstWhere(
    (candidate) => candidate.name == value,
    orElse: () => DockBorderShape.soft,
  );
}

/// Profundidad visual del dock (sombra/superficie).
enum DockDepth {
  flat,
  elevated,
  floating;

  static DockDepth parse(Object? value) => values.firstWhere(
    (candidate) => candidate.name == value,
    orElse: () => DockDepth.elevated,
  );
}

/// Identificadores estables de cada elemento que puede aparecer en un dock.
///
/// "back" no vive aquí: es contextual, se calcula en tiempo de navegación y
/// nunca se persiste como parte del catálogo de un perfil.
enum DockItemId {
  bots,
  work,
  create,
  home,
  settings,
  // Accesos directos opcionales: existen en el catálogo de AMBOS perfiles
  // pero ocultos por defecto (ver [defaultBots]/[defaultGeneral]); el
  // usuario los activa a mano desde Ajustes › Dock si los quiere en la
  // barra.
  cron,
  tasks,
  sessions,
  tools;

  static DockItemId? parse(Object? value) => values
      .cast<DockItemId?>()
      .firstWhere((candidate) => candidate?.name == value, orElse: () => null);
}

/// Estilo visual de un perfil de dock: bordes, transparencia y profundidad.
class DockStyle {
  static const schemaVersion = 1;

  final DockBorderShape borderShape;

  /// 0.0 = opaco, 1.0 = máxima transparencia (con desenfoque de fondo).
  final double transparency;
  final DockDepth depth;

  const DockStyle({
    this.borderShape = DockBorderShape.soft,
    this.transparency = 0.0,
    this.depth = DockDepth.elevated,
  });

  DockStyle copyWith({
    DockBorderShape? borderShape,
    double? transparency,
    DockDepth? depth,
  }) => DockStyle(
    borderShape: borderShape ?? this.borderShape,
    transparency: transparency ?? this.transparency,
    depth: depth ?? this.depth,
  );

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'border_shape': borderShape.name,
    'transparency': transparency,
    'depth': depth.name,
  };

  factory DockStyle.fromJson(Map<String, Object?>? json) {
    // Acepta cualquier versión <= la actual (parseo campo a campo,
    // defensivo, más abajo, hace de "migración" en la práctica mientras no
    // haya un cambio de forma real que la requiera); solo una versión
    // FUTURA (mayor que la que este binario entiende, p.ej. tras un
    // downgrade de la app) falla cerrado a los valores por defecto en vez
    // de arriesgarse a malinterpretar un formato que aún no existe (ver
    // C3). `is! int` cubre también el caso de un valor corrupto/ausente.
    final version = json?['schema_version'];
    if (json == null || version is! int || version > schemaVersion) {
      return const DockStyle();
    }
    final rawTransparency = json['transparency'];
    final transparency = rawTransparency is num
        ? rawTransparency.toDouble().clamp(0.0, 1.0)
        : 0.0;
    return DockStyle(
      borderShape: DockBorderShape.parse(json['border_shape']),
      transparency: transparency,
      depth: DockDepth.parse(json['depth']),
    );
  }
}

/// Un elemento del catálogo de un perfil: qué es y si está visible.
///
/// El orden dentro de la lista del perfil ES el orden de aparición en el
/// dock; no hace falta un índice adicional.
class DockItemConfig {
  final DockItemId id;
  final bool visible;

  const DockItemConfig({required this.id, this.visible = true});

  DockItemConfig copyWith({bool? visible}) =>
      DockItemConfig(id: id, visible: visible ?? this.visible);

  Map<String, Object?> toJson() => {'id': id.name, 'visible': visible};

  static DockItemConfig? fromJson(Map<String, Object?> json) {
    final id = DockItemId.parse(json['id']);
    if (id == null) return null;
    // Comprobación de tipo explícita en vez de `!= false`: con `!= false`
    // cualquier valor no booleano (un número, una cadena, `null`) cuela
    // como "visible" en vez de caer a un valor por defecto razonable (bug
    // confirmado: C5).
    final rawVisible = json['visible'];
    return DockItemConfig(id: id, visible: rawVisible is bool ? rawVisible : true);
  }
}

/// Configuración completa de un perfil de dock ("bots" o "general").
class DockProfileConfig {
  static const schemaVersion = 1;

  final List<DockItemConfig> items;
  final bool showBackOnSubscreens;
  final DockStyle style;

  const DockProfileConfig({
    required this.items,
    this.showBackOnSubscreens = true,
    this.style = const DockStyle(),
  });

  List<DockItemId> get visibleItemIds => [
    for (final item in items)
      if (item.visible) item.id,
  ];

  DockProfileConfig copyWith({
    List<DockItemConfig>? items,
    bool? showBackOnSubscreens,
    DockStyle? style,
  }) => DockProfileConfig(
    items: items ?? this.items,
    showBackOnSubscreens: showBackOnSubscreens ?? this.showBackOnSubscreens,
    style: style ?? this.style,
  );

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'items': [for (final item in items) item.toJson()],
    'show_back_on_subscreens': showBackOnSubscreens,
    'style': style.toJson(),
  };

  factory DockProfileConfig.fromJson(
    Map<String, Object?>? json,
    DockProfileConfig fallback,
  ) {
    // Ver el comentario equivalente en `DockStyle.fromJson` (C3): solo una
    // versión futura falla cerrado; el resto sigue al parseo campo a campo
    // de más abajo, que ya cae a `fallback` por su cuenta ante datos
    // insuficientes (lista de items vacía, etc.).
    final version = json?['schema_version'];
    if (json == null || version is! int || version > schemaVersion) {
      return fallback;
    }
    final rawItems = json['items'];
    final parsedItems = <DockItemConfig>[];
    final seenIds = <DockItemId>{};
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          final asStringMap = <String, Object?>{
            for (final e in entry.entries)
              if (e.key is String) e.key as String: e.value,
          };
          final item = DockItemConfig.fromJson(asStringMap);
          // Un id repetido en lo persistido (dato corrupto o de una versión
          // con un bug propio) rompía las suposiciones de `resolveDockSlots`
          // (una entrada por id); se deduplica al parsear en vez de
          // propagar la corrupción al resto del dock (bug confirmado: C5).
          if (item != null && seenIds.add(item.id)) parsedItems.add(item);
        }
      }
    }
    // Nada útil que rescatar de lo persistido (ausente/vacío/todo
    // corrupto): al `fallback` completo, ANTES de rellenar con el catálogo
    // por defecto más abajo — si este check viviera después de ese
    // relleno, `parsedItems` ya no estaría vacío nunca (se habría llenado
    // con todo el catálogo por defecto oculto) y este caso devolvería un
    // perfil con todo oculto en vez del `fallback` real.
    if (parsedItems.isEmpty) return fallback;
    // Cualquier id del catálogo por defecto que falte en lo persistido (por
    // ejemplo, tras una actualización que añade un elemento nuevo) se agrega
    // al final, oculto, para no perder elementos futuros silenciosamente ni
    // reordenar lo que el usuario ya configuró.
    for (final defaultItem in fallback.items) {
      if (!seenIds.contains(defaultItem.id)) {
        parsedItems.add(defaultItem.copyWith(visible: false));
      }
    }
    return DockProfileConfig(
      items: parsedItems,
      showBackOnSubscreens: json['show_back_on_subscreens'] != false,
      style: DockStyle.fromJson(
        (json['style'] as Map?)?.cast<String, Object?>(),
      ),
    );
  }

  static DockProfileConfig defaultBots() => const DockProfileConfig(
    items: [
      // "Inicio" va primero: sin él, el perfil Bots no tenía forma de volver
      // al dashboard general desde el dock (confirmado en dispositivo real).
      DockItemConfig(id: DockItemId.home),
      DockItemConfig(id: DockItemId.bots),
      DockItemConfig(id: DockItemId.create),
      DockItemConfig(id: DockItemId.work),
      // Accesos directos opcionales: en el catálogo, ocultos de fábrica.
      DockItemConfig(id: DockItemId.cron, visible: false),
      DockItemConfig(id: DockItemId.tasks, visible: false),
      DockItemConfig(id: DockItemId.sessions, visible: false),
      DockItemConfig(id: DockItemId.tools, visible: false),
    ],
  );

  static DockProfileConfig defaultGeneral() => const DockProfileConfig(
    items: [
      DockItemConfig(id: DockItemId.home),
      DockItemConfig(id: DockItemId.create),
      DockItemConfig(id: DockItemId.bots),
      DockItemConfig(id: DockItemId.settings),
      DockItemConfig(id: DockItemId.work, visible: false),
      // Accesos directos opcionales: en el catálogo, ocultos de fábrica.
      DockItemConfig(id: DockItemId.cron, visible: false),
      DockItemConfig(id: DockItemId.tasks, visible: false),
      DockItemConfig(id: DockItemId.sessions, visible: false),
      DockItemConfig(id: DockItemId.tools, visible: false),
    ],
  );
}

/// Raíz persistida: un [DockProfileConfig] por perfil, más el interruptor
/// GLOBAL (no por perfil) que apaga el dock flotante en toda la app.
class DockPreferences {
  static const schemaVersion = 1;

  final DockProfileConfig bots;
  final DockProfileConfig general;

  /// Activado por defecto. Cuando es `false`, ningún dock (ni "Bots" ni
  /// "General") se pinta en ninguna pantalla: la app debe seguir siendo
  /// 100% navegable/funcional solo con la UI nativa de cada pantalla (ver
  /// `GeneralDockShell`, que en ese caso devuelve el `body` sin envolver
  /// nada, y las acciones nativas — FAB, back nativo del `AppBar` — que
  /// nunca deben depender exclusivamente del dock para existir).
  final bool useDock;

  const DockPreferences({
    required this.bots,
    required this.general,
    this.useDock = true,
  });

  factory DockPreferences.defaults() => DockPreferences(
    bots: DockProfileConfig.defaultBots(),
    general: DockProfileConfig.defaultGeneral(),
  );

  DockPreferences copyWith({
    DockProfileConfig? bots,
    DockProfileConfig? general,
    bool? useDock,
  }) => DockPreferences(
    bots: bots ?? this.bots,
    general: general ?? this.general,
    useDock: useDock ?? this.useDock,
  );

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'bots': bots.toJson(),
    'general': general.toJson(),
    'use_dock': useDock,
  };

  factory DockPreferences.fromJson(Map<String, Object?>? json) {
    final defaults = DockPreferences.defaults();
    // Ver el comentario equivalente en `DockStyle.fromJson` (C3).
    final version = json?['schema_version'];
    if (json == null || version is! int || version > schemaVersion) {
      return defaults;
    }
    final rawUseDock = json['use_dock'];
    return DockPreferences(
      bots: DockProfileConfig.fromJson(
        (json['bots'] as Map?)?.cast<String, Object?>(),
        defaults.bots,
      ),
      general: DockProfileConfig.fromJson(
        (json['general'] as Map?)?.cast<String, Object?>(),
        defaults.general,
      ),
      useDock: rawUseDock is bool ? rawUseDock : defaults.useDock,
    );
  }
}

/// Calcula qué renderizar en cada hueco del dock: los elementos visibles del
/// perfil, en orden, con "Atrás" (representado como `null`) insertado en el
/// primer hueco cuando [showBack] es true.
///
/// El "destacado" (el elemento que nunca se retira para hacerle sitio a
/// "Atrás") ya no es un campo persistido aparte (ver C6): es, por
/// definición, el primer elemento de [visibleItems] — exactamente lo mismo
/// que ya calculaba Ajustes › Dock (antes como `pinnedItemId` recalculado en
/// cada edición) para decidir qué item "no se puede robar" a otro. Con una
/// sola fuente de verdad, el orden ya IMPLICA qué item queda protegido.
///
/// Para no añadir un hueco extra a la barra se retira el último elemento
/// visible que no sea el destacado. Si el único elemento visible YA ES el
/// destacado (por ser el único, y por tanto también el primero), no hay
/// nada que retirar sin romper esa garantía: la barra gana un hueco más en
/// vez de perder el destacado (caso raro — la barra en sí no cambia de
/// tamaño, cada item solo se estrecha un poco más; antes el código
/// contradecía este mismo doc y lo retiraba igual, ver E).
///
/// Si el perfil no tiene NINGÚN elemento visible (todos ocultos desde
/// Ajustes › Dock) pero [showBack] es true, el resultado es `[null]`: nunca
/// se deja una barra flotante vacía y sin navegación (bug confirmado: A4).
///
/// Al volver al nivel superior basta con volver a llamar con
/// `showBack: false` para recuperar la lista completa.
List<DockItemId?> resolveDockSlots({
  required List<DockItemId> visibleItems,
  required bool showBack,
}) {
  if (!showBack) return List<DockItemId?>.from(visibleItems);
  if (visibleItems.isEmpty) return const <DockItemId?>[null];
  final result = List<DockItemId>.from(visibleItems);
  final pinnedItemId = result.first;
  final removeIndex = result.lastIndexWhere((id) => id != pinnedItemId);
  if (removeIndex != -1) result.removeAt(removeIndex);
  return <DockItemId?>[null, ...result];
}
