# Hermes Console 1.2.10 — notas de publicación (candidata)

> No distribuir ni presentar como release pública hasta cerrar la matriz E2E en
> emulador y Hermes Desktop, firmar los artefactos exactos y aprobar
> explícitamente la publicación.

## Cambios frente a 1.2.9

- La recuperación de ownership entre Desktop y Console sigue la lineage durable
  incluso después de compactación, sin duplicar el turno local.
- La reconexión WebSocket recupera eventos por secuencia, ordena el replay y
  aparca frames live hasta cerrar el hueco.
- Un replay truncado no proyecta una continuidad no demostrada: descarta tail y
  frames live hasta que una recuperación autoritativa confirma el runtime.
- Las secuencias malformadas no pueden corromper el watermark de reconexión.
- Las delegaciones y sus hijos cierran como terminales de forma consistente al
  reabrir la conversación.
- Un turno durable que termina después de agotar la ventana de recuperación
  offline puede reconciliarse sin reenviar ni duplicar el prompt; el borrador no
  confirmado permanece editable.
- Cron, Kanban y subagentes aparecen bajo Automatización. Los no-op de Cron y
  Kanban `done` no interrumpen; los bloqueos y fallos de entrega siguen visibles.

## Google Play — Novedades (español)

Mejoramos la continuidad entre Desktop y Console: recuperación segura de chats
compactados, reconexión WebSocket ordenada y protección ante huecos de replay.
También aclaramos la actividad de Cron, Kanban y subagentes para que los avisos
sean accionables sin ruido.

## Google Play — What's new (English)

Improved Desktop-to-Console continuity: safe recovery for compacted chats,
ordered WebSocket reconnect replay, and protection from replay gaps. Cron,
Kanban, and subagent activity is also clearer, keeping actionable alerts
without unnecessary noise.
