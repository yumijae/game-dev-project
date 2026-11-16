extends Node
## Global Event Bus for "Huling Kampana"
## Autoload: EventBus
## Decoupled communication across managers, Jude, AI entities, barricades, and items.

# ==============================================================================
# 1. TIME & KAMPANA BELLS
# ==============================================================================
## Emitted each time in-game minutes advance.
## e.g., hours=23, minutes=45, formatted="11:45 PM", normalized_progress=0.0..1.0
signal time_advanced(hours: int, minutes: int, formatted_time: String, progress: float)

## Emitted at the stroke of each hour (12:00 AM, 1:00 AM, etc.).
## bell_count corresponds to the hour (12 for midnight, 1 for 1 AM, etc.).
signal hourly_bell_tolled(hour: int, bell_count: int)

## Emitted at 03:30 AM when the Rooftop Radio SOS transmission window opens.
signal rooftop_sos_window_opened()

## Emitted at 05:30 AM when dawn breaks (primary survival victory).
signal dawn_arrived()


# ==============================================================================
# 2. NOISE & ACOUSTIC PROPAGATION
# ==============================================================================
## Emitted when an entity or object generates sound.
## origin: 3D world position
## floor_level: 0=1F, 1=2F, 2=3F, 3=4F, 4=Roof
## radius: Base detection radius in meters before muffling
## loudness_db: Initial loudness in decibels (e.g. 20=crouch step, 85=slam door, 110=gun/glass)
## noise_type: "footstep", "sprint", "door_slam", "glass_break", "barricade_bang", "scream"
signal noise_emitted(origin: Vector3, floor_level: int, radius: float, loudness_db: float, noise_type: StringName)


# ==============================================================================
# 3. SCENT & PREDATORY TRACKING
# ==============================================================================
## Emitted when blood, sweat, or food is deposited into the environment.
## scent_type: "blood", "sweat", "raw_meat", "flesh"
signal scent_dropped(position: Vector3, floor_level: int, intensity: float, scent_type: StringName, is_masked: bool)

## Emitted when herbal / folklore scent-masking mixtures (Ahos, Suka, Lana) are applied.
signal scent_mask_applied(position: Vector3, radius: float, duration: float, mask_type: StringName)


# ==============================================================================
# 4. SURVIVAL ATTRIBUTES (JUDE VILLANUEVA)
# ==============================================================================
signal stamina_changed(current: float, max_val: float)
signal panic_changed(current: float, max_val: float, tier: int)
signal panic_tier_entered(tier: int) # 0=Calm, 1=Uneasy, 2=Paranoid, 3=Hallucinating
signal footwear_changed(footwear_type: StringName, noise_multiplier: float) # "shoes", "socks", "barefoot"
signal bleeding_changed(is_bleeding: bool, severity: float)
signal phone_battery_changed(percentage: float, is_torch_active: bool)
signal player_damaged(damage: float, source: StringName)
signal player_died(cause_of_death: String)


# ==============================================================================
# 5. INVENTORY & FOLKLORE CRAFTING
# ==============================================================================
signal item_picked_up(item_data: Resource, count: int)
signal item_removed(item_id: StringName, count: int)
signal item_consumed(item_data: Resource)
signal item_crafted(recipe_data: Resource)
signal quickslot_selected(slot_index: int, item_data: Resource)


# ==============================================================================
# 6. BARRICADES & ENVIRONMENT INTERACTION
# ==============================================================================
## slot: "handle_tie" (LAN cable), "bottom_gap" (cloth/asin/garlic), "lock" (key)
signal door_barricade_modified(door_node: Node3D, slot: StringName, item_id: StringName, state: bool)
signal door_breach_progress(door_node: Node3D, health_remaining: float, attacker_type: StringName)
signal door_breached(door_node: Node3D, attacker_type: StringName)
signal jalousie_slat_broken(window_node: Node3D, remaining_slats: int)
signal jalousie_salted(window_node: Node3D, is_active: bool)


# ==============================================================================
# 7. ASWANG AI SENSORY & COMBAT
# ==============================================================================
signal aswang_alerted(aswang_type: StringName, target_position: Vector3, urgency: float)
signal aswang_state_changed(aswang_type: StringName, old_state: StringName, new_state: StringName)

## Tiktik audio reverse-falloff cue (Loud = Far, Whisper = Close)
signal tiktik_call_emitted(real_position: Vector3, perceived_db: float, actual_distance: float)

## Balbal sound mimicry
signal balbal_mimicry_triggered(mimic_sound: StringName, fake_position: Vector3)

## Manananggal Lower Torso discovery & salt/garlic burning
signal manananggal_torso_discovered(torso_node: Node3D)
signal manananggal_torso_salted(progress: float)


# ==============================================================================
# 8. PANIC HALLUCINATIONS & GROUNDING (LANA TRUTH RULE)
# ==============================================================================
signal hallucination_manifested(type: StringName, instance: Node)
signal hallucination_dispelled(instance: Node)
signal lana_test_conducted(target_node: Node, is_hallucination: bool)


# ==============================================================================
# 9. ESCAPE & WIN CONDITIONS
# ==============================================================================
signal escape_progress_updated(objective_id: StringName, progress: float, description: String)
signal game_won(ending_id: StringName, ending_title: String)
signal game_over(reason: String)
