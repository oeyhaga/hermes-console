# Hermes Console 1.2.12 — notas de publicación

Build candidata: `1.2.12+9200` (2026-09-22). La validación física final en Pixel 9 Pro queda
pendiente del propietario antes de cualquier publicación; nada se sube sin su visto bueno.
Pruebas hechas: suite completa (111/111, dos pasadas), `flutter analyze` limpio, gitleaks y grep
manual de rutas/IPs/tokens sobre todo el diff limpios, emulador Android 35 y Pixel 9 Pro
conectados a la instancia real de Hermes (con el plugin de enrutado Laya activo), incluidos
cortes de red reales por `adb`. Esta build añade sobre la `+9010`: el rediseño de la píldora de
actividad/panel/compactación/editor inline, y las correcciones de una auditoría de seguridad y
una revisión de código independientes (ver más abajo).

## Lo más importante frente a 1.2.11

- **Stop como en Desktop.** Llega siempre al servidor (ya no lo bloquea una comprobación local
  de propiedad ni un fallo al escribir en disco), se confirma con la señal real del gateway y
  escala con un límite de 8 s en vez de quedarse en «Deteniendo…». Está disponible mientras
  haya trabajo, sea cual sea (turno, proceso en segundo plano, subagente, bucle o sesión
  arrancada en otro sitio), desde el chat y desde las filas de Inicio y la lista; también
  detiene los procesos en segundo plano; un turno interrumpido dice «Detenido»; y una sesión
  colgada por auto-continuar muestra un banner «Detener esta sesión».
- **Editar, cola y forzar como en Desktop.** La fila se resuelve por contenido, las ediciones
  consecutivas funcionan, un fallo restaura el historial sin burbujas huérfanas, y un «forzar»
  que el backend declina porque el turno acababa de terminar ya no se anuncia como fallo: el
  mensaje sigue en cola.
- **Pérdida de red.** El chat se recupera solo: reintentos con jitter hasta 15 s, aviso
  inmediato cuando Android detecta la red o la app vuelve a primer plano, ticket nuevo en cada
  intento, y si el turno terminó mientras estabas sin conexión se adopta la respuesta final del
  historial. Mientras dura, el chat lo dice con calma y avisa con «Reconectado».
- **Aprobaciones y preguntas del agente (#42), voz desde la segunda grabación (#39) y borrador
  (#37, con pruebas de regresión).**
- **Una burbuja por turno,** con la cabecera del avatar sin aro de carga y en el color de acento,
  y un desplegable «Completado ⌄» debajo del nombre; **una sola píldora de actividad** que se
  expande en el sitio a un panel compacto con scroll (tareas con check animado, ahora, hecho con
  duraciones, segundo plano/subagentes/bucles); **compactación real** (manual y automática) con
  barra indeterminada y hechos reales del backend, nunca un porcentaje inventado; **editar en la
  propia burbuja**, sin ventana modal, con más espacio para escribir; **aviso de Stop discreto**
  que se desvanece solo; **archivos con visor propio** (imagen, vídeo, PDF, texto, audio);
  **trabajo en segundo plano visible** en el chat, Inicio y la lista, incluido Stop de
  subagentes; avisos flotantes arriba; flechas de subir/bajar solo cuando sirven.
- Sondeos del chat y de las listas guiados por eventos con respaldo lento; backoff estable;
  historial largo accesible tras compactar; nueva autorización normal `ACCESS_NETWORK_STATE`.
- **Seguridad**: denylist de rutas sensibles para `MEDIA:` mucho más amplia (claves SSH,
  `.ssh`/`.aws`/`.kube`/`.docker`/etc., `/proc`, `/sys`, `/dev`) con una segunda comprobación
  antes de mostrar texto en línea; instaladores/ejecutables ya no se auto-abren; las descargas
  autenticadas ya no siguen redirecciones con la credencial de sesión puesta; un intent de
  compartir externo solo se acepta desde `content://`; una ruta personal ya no puede filtrarse en
  el paquete público de evidencias del release.
- **Correcciones de una revisión de código independiente**: Stop de un proceso en segundo plano
  ya no puede afectar a otra sesión en un cliente compartido; una ráfaga de reintentos de sesión
  ya no puede recursar sin límite; el panel de actividad ya no recalcula en cada pulsación de
  tecla; una edición interrumpida a mitad de camino ya no puede reportar éxito falso.

## Límites conocidos

- Las notificaciones de trabajo que termina en otro dispositivo (p. ej. la tablet) no están.
- Sin certeza de «exactamente una vez» si la conexión cae justo al enviar un mensaje (el
  backend actual ignora `client_turn_id`); un turno sin actividad durante 10 min separado del
  cliente puede ser interrumpido por el servidor.
- Console y Desktop siguen sin poder continuar el mismo turno en vivo entre clientes.

## Ya validado (2026-09-22)

Turno largo con herramientas y cierre forzado; corte de red real (modo avión 90 s) con el turno
en marcha; Stop con proceso en segundo plano, con subagentes (confirmado con `ps` en el
servidor) y desde Inicio; editar en la burbuja y cola con «forzar»; cabecera y flechas; archivos
(TXT, PDF, imagen, audio); tareas del agente y su panel; aprobaciones (`clarify`); compactación
manual y automática; voz con dos grabaciones seguidas contra un STT del servidor.

## Pendiente

Prueba física final del propietario en el Pixel 9 Pro con la build `+9200` antes de publicar;
modo voz/Realtime queda fuera de alcance de esta versión (auditoría aparte).
