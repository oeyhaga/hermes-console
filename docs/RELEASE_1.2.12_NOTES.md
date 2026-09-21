# Hermes Console 1.2.12 — notas de publicación

Build candidata: `1.2.12+9010` (2026-09-21). La validación física en Pixel 9 Pro queda
pendiente antes de cualquier publicación; nada se sube sin ese visto bueno del propietario.
Las pruebas de esta versión se hicieron en emulador Android 35 conectado a la instancia real
de Hermes y, antes de las últimas mejoras, en el Pixel.

## Lo más importante frente a 1.2.11

- **Una sola burbuja por turno.** El razonamiento y los pasos de herramientas/skills viven en
  un único bloque de actividad dentro de la burbuja: muestra el paso actual mientras trabaja
  («Pensando…», «Ejecutando herramienta…») y queda plegado en una sola entrada al terminar.
  Al reabrir una conversación se reconstruye la misma burbuja desde el historial.
- **Archivos y medios que se ven solos.** Lo que Hermes entrega con `MEDIA:` se precarga y se
  abre en visores propios: imagen con zoom, vídeo con controles, PDF (miniatura y visor de
  páginas con renderizador nativo de Android), texto (vista previa y visor seleccionable),
  audio, y Guardar/Compartir en todos. Solo se descargan rutas anunciadas por Hermes, el
  servidor sigue mandando sobre lo descargable, los archivos grandes piden un toque y hay caché
  en disco.
- **Trabajo en segundo plano visible.** Procesos (con patrones de vigilancia y último acierto),
  bucles, latidos, objetivos, avance de tareas y subagentes aparecen como una píldora compacta
  en el chat y como chip «En segundo plano · N» en Inicio y en la lista.
- **Cerrar y reabrir la app.** Sin mensaje duplicado, sin quedarse en «Conectando» y con la
  respuesta final; tras cerrar del todo, Inicio y la lista muestran qué sesión sigue trabajando.
- **Sin falsos «Modelo sin respuesta».** El silencio deja de fallar el turno; a los cinco
  minutos solo aparece un aviso.
- **Edición y cola.** Editar durante un turno interrumpe y reintenta el rewind como Desktop; si el
  backend rechaza redirigir un mensaje en cola, ahora lo explica.
- **Conexión y sesiones largas.** Backoff con jitter que solo se reinicia con un socket estable,
  eventos repetidos sin duplicar, refresco por `sessions.changed` con un sondeo lento de
  seguridad; el historial anterior sigue accesible tras compactar y la caché local conserva los
  1.000 mensajes más recientes (2 MiB) avisando si recorta.
- Mensajes internos (cambio de personalidad, auto-continuar, proceso terminado) ya no aparecen
  como tuyos; las vistas previas de la lista muestran texto legible en vez de JSON de llamadas.
- Android Share pega solo el enlace; la sesión vacía compartida ya no da «session not found»;
  el botón de bajar no queda tapado; los avisos flotantes siguen el tema y no cubren el
  composer; Bot Chat canónico reanuda su conversación y la elección «sin sprite» se conserva.

## Límites conocidos

- Las notificaciones de trabajo que termina en otro dispositivo (p. ej. la tablet) no están: Hermes
  las enruta solo a la superficie dueña de la sesión.
- Console y Hermes Desktop siguen sin poder continuar el mismo turno en vivo entre clientes
  (lease entre procesos en el servidor).
- Forzar la detención desde los ajustes de Android corta toda entrega hasta volver a abrir la app.

## Pendiente de validar en el Pixel

Reproducir en el Pixel: turno largo con herramientas y cierre forzado, proceso en segundo plano
y subagente con chips en Inicio, archivos (TXT, PDF, imagen, vídeo) con sus visores, edición y
cola con forzar, Android Share con enlace y avisos flotantes sobre el composer.
