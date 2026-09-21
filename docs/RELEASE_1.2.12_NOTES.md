# Hermes Console 1.2.12 — notas de publicación

Build candidata: `1.2.12+9010` (2026-09-21). La validación física final en Pixel 9 Pro queda
pendiente del propietario antes de cualquier publicación; nada se sube sin su visto bueno.
Pruebas hechas: suite completa, emulador Android 35 y Pixel 9 Pro conectados a la instancia real
de Hermes (con el plugin de enrutado Laya activo), incluidos cortes de red reales por `adb`.

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
- **Una burbuja por turno,** con el sprite siempre en la cabecera (más grande y reaccionando al
  estado) y un bloque de actividad con iconos de estado; **lista de tareas del agente**
  («Tareas 3/7»); **archivos con visor propio** (imagen, vídeo, PDF, texto, audio);
  **trabajo en segundo plano visible** en el chat, Inicio y la lista; avisos flotantes arriba;
  flecha de subir solo cuando sirve.
- Sondeos del chat y de las listas guiados por eventos con respaldo lento; backoff estable;
  historial largo accesible tras compactar; nueva autorización normal `ACCESS_NETWORK_STATE`.

## Límites conocidos

- Las notificaciones de trabajo que termina en otro dispositivo (p. ej. la tablet) no están.
- Sin certeza de «exactamente una vez» si la conexión cae justo al enviar un mensaje (el
  backend actual ignora `client_turn_id`); un turno sin actividad durante 10 min separado del
  cliente puede ser interrumpido por el servidor.
- Console y Desktop siguen sin poder continuar el mismo turno en vivo entre clientes.

## Pendiente de validar en el Pixel

Turno largo con herramientas y cierre forzado; corte de red real (modo avión 90 s) con el turno
en marcha; Stop con proceso en segundo plano y desde Inicio; editar y cola con «forzar»; sprite,
iconos de estado y flecha; archivos (TXT, PDF, imagen, vídeo); tareas del agente; aprobaciones
(`clarify`); voz con dos grabaciones seguidas contra un STT del servidor.
