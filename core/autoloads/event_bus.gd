extends Node
## EventBus (autoload) - global signal bus for "Expo Night".
## Systems never hold references to each other; they talk through these signals.

# ----------------------------------------------------------------------- time
signal time_advanced(hour: int, minute: int, formatted: String, progress: float)
## 12:00 AM - the rogue update finishes and the first robot reboots.
signal midnight_started()
signal hour_struck(hour: int, aggression_level: int)
signal aggression_escalated(level: int)
signal rescue_time_changed(hour: int, minute: int)
## 6:00 AM, or 3:30 AM once the rooftop SOS went out.
signal rescue_arrived()

# ---------------------------------------------------------------------- noise
signal noise_emitted(origin: Vector3, radius: float, noise_type: StringName, source: Node)
## A robot heard a noise Juan made himself (the HUD noise meter turns red).
signal player_noise_heard(robot: Node)

# --------------------------------------------------------------- player stats
signal stamina_changed(value: float)
signal panic_changed(value: float, tier: int)
signal panic_tier_changed(tier: int)
## Fired when panic crosses one of PlayerStats.PANIC_THRESHOLDS.
signal panic_threshold_crossed(threshold: int, rising: bool)
signal shaky_hands_changed(active: bool)
signal footwear_changed(footwear: int)
signal bleeding_changed(is_bleeding: bool)
signal phone_battery_changed(percent: float)
signal flashlight_toggled(is_on: bool)
signal phone_raised(is_out: bool)
## The LED beam hit an exterior jalousie window or a corridor viewing pane.
signal flashlight_leaked(point: Vector3, surface: Node3D)
signal player_hidden_changed(is_hidden: bool, spot: Node3D)
signal player_wounded(source: StringName)

# ------------------------------------------------------------------ inventory
signal inventory_changed()
signal item_picked_up(item_id: StringName)
signal item_used(item_id: StringName)
signal item_crafted(item_id: StringName)

# ---------------------------------------------------------------------- world
signal door_state_changed(door: Node3D)
signal door_breached(door: Node3D)
signal glass_shattered(glass: Node3D, point: Vector3)

# ------------------------------------------------------------------------- ui
## `actions` is an Array of {"id": StringName, "label": String}.
signal ui_prompt_changed(actions: Array, selected: int)
signal ui_subtitle(text: String, duration: float, speaker: StringName)
signal ui_notification(text: String, duration: float)
signal ui_channel_started(label: String, duration: float)
signal ui_channel_progress(ratio: float)
signal ui_channel_finished(completed: bool)
signal ui_gasp_prompt(active: bool, window: float)
signal ui_peek_changed(is_peeking: bool)
signal hallucination_started(kind: StringName, position: Vector3)

# ------------------------------------------------------- objectives / endings
signal objective_updated(objective_id: StringName, text: String, progress: float)
signal sos_progress_changed(seconds: float, required: float)
signal sos_sent()
signal gate_breach_progress(ratio: float)
signal gate_opened(method: StringName)
## WARDEN's circuit (server, CCTV, Com Sci Lab docks) lost power. `cause` is
## &"breaker" (LP-2F main thrown by Juan) or &"ups_empty" (backup battery ran out).
signal lab_power_cut(cause: StringName)
## A robot finished rebooting after the update and is now hunting.
signal robot_online(display_name: String)
signal game_won(ending_id: StringName, title: String, description: String)
signal game_lost(cause: String)
