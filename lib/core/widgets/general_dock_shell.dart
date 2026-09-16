import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/dock_config.dart' show DockItemId;
import '../screens/chat_screen.dart';
import '../screens/mission_control_screen.dart';
import '../screens/settings_screen.dart';
import '../services/connection_manager.dart';
import '../services/dock_preferences_store.dart';
import 'dock_shortcuts.dart';
import 'dock_style.dart' show dockShowsBack;
import 'general_mode_dock.dart';

/// Envuelve el `body` de una pantalla de navegación del perfil "General"
/// (fuera de una conversación abierta) con el mismo dock flotante que ya usa
/// `HomeDashboardScreen`: mismo patrón Stack + Positioned + callbacks
/// (onCreate/onOpenBots/onOpenSettings/...), gestionando por su cuenta el
/// "Atrás" contextual (RouteAware) para no duplicar esa lógica ni la lista
/// de callbacks en cada pantalla que se sume (Ajustes, lista de sesiones).
///
/// Deliberadamente NO se usa dentro de una conversación (`ChatScreen`): ahí
/// ya viven el composer y el pill flotante de subagentes; superponer el
/// dock los taparía/competiría con ellos.
class GeneralDockShell extends StatefulWidget {
  final Widget body;
  final SavedConnection connection;
  final ConnectionManager connManager;

  /// Acción de "Crear". Si es null, crea una conversación nueva genérica
  /// (mismo comportamiento que Inicio); algunas pantallas (p.ej. la lista de
  /// sesiones) ya tienen su propia creación con refresco de estado y la
  /// pasan aquí en vez de usar el fallback.
  final VoidCallback? onCreate;

  /// Variante contextual de [onCreate]: cuando no es null, tiene prioridad
  /// sobre `onCreate`/el fallback genérico. Recibe la `GlobalKey` ya anclada
  /// al tile "+" del dock (ver [GeneralModeDock.createAnchorKey]) para que
  /// quien la use pueda abrir un popover anclado a ese botón (p.ej. crear un
  /// cron job o una tarea directamente ahí) en vez de navegar.
  final void Function(GlobalKey anchorKey)? onCreateAnchored;

  /// False cuando esta pantalla YA ES Ajustes: evita apilar Ajustes sobre
  /// Ajustes al tocar el item "Ajustes" del dock.
  final bool includeSettingsAction;

  /// False cuando esta pantalla YA ES la lista de sesiones (solo aplica si
  /// el usuario activó el acceso opcional "Sesiones" del catálogo).
  final bool includeSessionsAction;

  /// Id del item del catálogo que representa la pantalla que YA ES esta
  /// (Cron/Tareas/Herramientas): a diferencia de Ajustes/Sesiones, estos
  /// accesos no tenían forma de desactivarse al estar ya dentro, así que
  /// tocarlos apilaba una copia de la misma pantalla indefinidamente (bug
  /// confirmado: A3). Cuando coincide con un slot, ese item se pinta como
  /// sección activa (`selected: true`) sin acción propia en vez de navegar.
  final DockItemId? currentDestination;

  const GeneralDockShell({
    required this.body,
    required this.connection,
    required this.connManager,
    this.onCreate,
    this.onCreateAnchored,
    this.includeSettingsAction = true,
    this.includeSessionsAction = true,
    this.currentDestination,
    super.key,
  });

  @override
  State<GeneralDockShell> createState() => _GeneralDockShellState();
}

class _GeneralDockShellState extends State<GeneralDockShell> {
  // Ver el doc de `dockShowsBack` (dock_style.dart) para el porqué de este
  // criterio frente al RouteAware que usaba la versión anterior.
  bool get _isSubscreen => dockShowsBack(context);

  // Solo se instancia cuando `onCreateAnchored` está presente: el resto de
  // pantallas (Ajustes, Sesiones) no necesitan que el "+" cargue una key.
  final GlobalKey _createAnchorKey = GlobalKey(
    debugLabel: 'general-dock-create-anchor',
  );

  @override
  void initState() {
    super.initState();
    unawaited(DockPreferencesController.instance.ensureLoaded());
  }

  void _handleCreate() {
    final anchored = widget.onCreateAnchored;
    if (anchored != null) {
      anchored(_createAnchorKey);
      return;
    }
    (widget.onCreate ?? _defaultCreate)();
  }

  void _defaultCreate() {
    final session = Session(
      id: GatewayChatClient.generateSessionId(),
      title: Strings.of(context).drawerNewChat,
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: DateTime.now().millisecondsSinceEpoch.toDouble() / 1000,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(connection: widget.connection, session: session),
      ),
    );
  }

  void _openBots() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MissionControlScreen(
          connection: widget.connection,
          connManager: widget.connManager,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          connection: widget.connection,
          connManager: widget.connManager,
        ),
      ),
    );
  }

  // Único criterio de "esta pantalla ya soy yo": lo declarado explícitamente
  // (Cron/Tareas/Herramientas, vía `currentDestination`) o, si no, lo que ya
  // señalan los flags `include*Action` existentes (Ajustes/Sesiones), para
  // que ambos mecanismos alimenten la misma marca visual de sección activa
  // (ver B3) sin que Ajustes/Sesiones tengan que migrar de flag.
  DockItemId? get _currentDestination {
    final explicit = widget.currentDestination;
    if (explicit != null) return explicit;
    if (!widget.includeSettingsAction) return DockItemId.settings;
    if (!widget.includeSessionsAction) return DockItemId.sessions;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DockPreferencesController.instance.listenable,
      builder: (context, _) {
        // Interruptor global "Usar dock flotante" (Ajustes): cuando está
        // apagado, esta pantalla es simplemente su `body`, sin el `Stack`
        // ni el propio `GeneralModeDock` de por medio — nada de dock
        // corriendo de fondo, ni un hueco vacío donde solía estar (pedido
        // explícito del usuario). El resto de acciones de la pantalla
        // (FAB nativo, back nativo del `AppBar`, etc.) nunca dependen de
        // este widget, así que la pantalla sigue siendo 100% funcional.
        if (!DockPreferencesController.instance.value.useDock) {
          return widget.body;
        }
        final current = _currentDestination;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.body,
            GeneralModeDock(
              onCreate: _handleCreate,
              createAnchorKey: widget.onCreateAnchored != null
                  ? _createAnchorKey
                  : null,
              onOpenBots: _openBots,
              onOpenSettings: widget.includeSettingsAction
                  ? _openSettings
                  : null,
              onOpenHome: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
              onOpenCron: current == DockItemId.cron
                  ? null
                  : () => openDockCron(
                      context,
                      widget.connection,
                      widget.connManager,
                    ),
              onOpenTasks: current == DockItemId.tasks
                  ? null
                  : () => openDockTasks(
                      context,
                      widget.connection,
                      widget.connManager,
                    ),
              onOpenSessions: widget.includeSessionsAction
                  ? () => openDockSessions(
                      context,
                      widget.connection,
                      widget.connManager,
                    )
                  : null,
              onOpenTools: current == DockItemId.tools
                  ? null
                  : () => openDockTools(
                      context,
                      widget.connection,
                      widget.connManager,
                    ),
              currentDestination: current,
              showBackContext: _isSubscreen,
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ],
        );
      },
    );
  }
}
