import 'bot_room_link.dart';
import 'bot_mention_roster.dart';
import 'bot_profile_client.dart';
// Cliente del protocolo oficial usado por Hermes Desktop y el Dashboard.
//
// Transporte: WebSocket `/api/ws` + JSON-RPC 2.0. A diferencia de `/v1/runs`,
// este canal conserva una referencia al AIAgent vivo y expone
// `session.redirect` (con `session.steer` solo para compatibilidad antigua).
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/command_descriptor.dart';
import '../models/agent_profile.dart';
import '../models/admin_integrations.dart';
import '../models/bot_visual_identity.dart';
import '../models/desktop_active_session.dart';
import '../models/desktop_compression_result.dart';
import '../models/desktop_compression_outcome.dart';
import '../models/desktop_control_center.dart';
import '../models/desktop_context_breakdown.dart';
import '../models/desktop_model_catalog.dart';
import '../models/desktop_session_config.dart';
import '../models/desktop_session_snapshot.dart';
import '../models/interactive_prompt.dart';
import '../models/desktop_run_config.dart';
import '../models/tui_event.dart';
import '../models/desktop_catalog_command.dart';
import '../models/desktop_model_router.dart';
import '../models/desktop_catalog_group.dart';
import '../models/desktop_session_snapshot_compact.dart';
import '../models/desktop_settings_map.dart';
import '../models/desktop_subagent.dart';
import '../models/desktop_subagent_tail.dart';
import '../models/desktop_tool_alias.dart';
import '../models/desktop_provider.dart';
import '../models/desktop_room.dart';
import '../models/desktop_room_member.dart';
import '../models/desktop_room_link.dart';
import '../models/desktop_room_recipient.dart';
import '../models/desktop_bot_section.dart';
import '../models/desktop_bot_persona.dart';
import '../models/bot_profile.dart';
import '../models/desktop_user_context.dart';
import '../models/desktop_bot_sessions.dart';
import '../models/desktop_bot_constructor.dart';
import '../models/desktop_bot_deletion.dart';
import '../models/desktop_bot_undo.dart';
import '../models/desktop_bot_create.dart';
import '../models/desktop_bot_create_advanced.dart';
import '../models/desktop_prompt_response.dart';
import '../models/resolved_bot_section.dart';
import '../models/desktop_model_summary.dart';
import '../models/json_rpc_event_frame.dart';
import '../models/json_rpc_sampling.dart';
import '../models/slash_completion_batch.dart';
import '../models/voice_session_result.dart';
import '../models/desktop_capability_template.dart';
import '../models/sampling_policy.dart';

import 'session_control_prompt.dart';
import 'session_control_wallet.dart';
import 'desktop_json_rpc_transport.dart';
import 'json_rpc_connection.dart';
import 'interactive_prompt_submission.dart';
import 'json_rpc_reconnect_table.dart';
import 'json_rpc_retry_state.dart';
import 'json_rpc_reconnect_state.dart';
import 'json_rpc_wire.dart';
import 'json_rpc_channel.dart';
import 'json_rpc_methods.dart';
import 'json_rpc_gateway_events.dart';
import 'desktop_turn_ownership.dart';
import 'session_identity_map.dart';
import 'roles.dart';
import 'server_requests.dart';

// Builder pattern for the gateway client — runs inside a timer rather than
// building the widget tree, so it can start recovery before the first frame.
// Can be disposed even in the initial 'connecting' state.

/// How long the gateway stays in the 'unauthenticated' state before giving up
/// (negative = no auth wait).
const Duration _authWatchdogDuration = Duration(seconds: 3);

class TuiGatewayClient extends ChangeNotifier {