class_name PhoneScreen
extends Control
## Juan's smartphone. A titanium-framed handset with a rounded glass screen
## (everything on it is masked to the screen's anti-aliased rounded corners),
## a Dynamic-Island style cutout, a live status bar and a home screen of apps:
##
##   Phone       dialer - emergency calls fail without service
##   Clock       analog + digital time
##   Flashlight  the LED (same as F)
##   Cameras     the school CCTV; the phone turns landscape
##   Messages    conversations (hints from classmates, the SOS thread)
##   Notes       tonight's objectives, ticked off as they change
##
## Connectivity (story): the blackout at 11:44 PM took the internet with it, so
## texts fail and calls need the rooftop. The school Wi-Fi access points run off
## the server rack, which is on the UPS: the phone stays on "STI-Students" with
## no internet, enough for the Robot Expo app to follow the firmware update on
## the server. When WARDEN's circuit dies (breaker or UPS empty) Wi-Fi goes too.
##
## Controls while the phone is up: mouse wheel = select / scroll / switch camera,
## left click = open, right click = back (at home: put the phone away).

enum Page { HOME, CAMERAS, MESSAGES, THREAD, NOTES, CLOCK, DIALER }

const PORTRAIT := Vector2(250.0, 510.0)
const LANDSCAPE := Vector2(880.0, 440.0)
const MARGIN := Vector2(34.0, 30.0)
const FRAME := 3.0
const BEZEL := 10.0
const BODY_RADIUS := 46.0
const SCREEN_RADIUS := 34.0
## Portrait screen size, the layout the portrait pages are drawn for.
const SW := 224.0
const SH := 484.0

const WHITE := Color(0.97, 0.97, 0.99)
const DIM := Color(0.92, 0.93, 0.96, 0.72)
const FAINT := Color(0.92, 0.93, 0.96, 0.52)
const BLUE := Color(0.04, 0.52, 1.0)
const RED := Color(1.0, 0.27, 0.23)
const GREEN := Color(0.2, 0.78, 0.35)
const ORANGE := Color(1.0, 0.62, 0.04)
const PAGE_BG := Color(0.035, 0.035, 0.045)
const CARD := Color(0.11, 0.11, 0.13)

const APPS: Array[StringName] = [&"phone", &"clock", &"flashlight", &"cameras", &"messages", &"notes"]
const APP_NAMES: Dictionary = {
	&"phone": "Phone", &"clock": "Clock", &"flashlight": "Flashlight",
	&"cameras": "Cameras", &"messages": "Messages", &"notes": "Notes",
}
## APPS from this index on live in the dock.
const DOCK_FIRST := 2
const ICON := 40.0
const COLUMN_X: Array[float] = [14.0, 66.0, 118.0, 170.0]

## The rogue firmware update: started 11:38 PM, finishes at 12:00 AM (in game
## minutes relative to 11:45 PM).
const UPDATE_START: float = -7.0
const UPDATE_END: float = 15.0
const ROBOT_ORANGE := Color(1.0, 0.45, 0.12)

static var _fonts: Dictionary = {}

var page: Page = Page.HOME
var selected: int = 3

var _phone: PlayerPhoneUI = null
var _cctv: CctvApp = null
var _shown: bool = false
var _slide: float = 0.0
var _size_now: Vector2 = PORTRAIT
var _page_t: float = 1.0
var _shake: float = 0.0
var _time: float = 0.0
var _clock_text: String = "11:45 PM"
var _last_battery: float = -1.0

# frame / screen
var _rig: Control = null
var _screen: Panel = null
var _island: Panel = null
var _curtain: ColorRect = null
var _indicator: Panel = null
var _hints: PanelContainer = null
var _hint_row: HBoxContainer = null
var _hint_page: int = -1
var _pages: Dictionary = {}
# status bar
var _status: Control = null
var _status_time: Label = null
var _status_icons: StatusIcons = null
# home
var _big_clock: Label = null
var _date: Label = null
var _widget_text: Label = null
# Robot Expo live activity (home screen)
var _live_status: Label = null
var _live_pct: Label = null
var _live_fill: Panel = null
var _update_done: bool = false
var _icons: Array[AppIcon] = []
var _dock_tip: Label = null
var _tip_time: float = 0.0
# banner
var _banner: Panel = null
var _banner_icon: AppIcon = null
var _banner_title: Label = null
var _banner_body: Label = null
var _banner_time: float = 0.0
## Notifications that arrive while one is showing wait their turn.
var _banner_queue: Array[Array] = []
# messages
var _threads: Array[Dictionary] = []
var _thread_sel: int = 0
var _thread_rows: VBoxContainer = null
var _thread_scroll: ScrollContainer = null
var _thread_list: VBoxContainer = null
var _thread_name: Label = null
var _thread_avatar: Avatar = null
# notes
var _objectives: Array[String] = []
var _notes_list: VBoxContainer = null
var _notes_unseen: bool = false
# clock
var _clock_face: AppIcon = null
var _clock_digital: Label = null
var _clock_date: Label = null
# dialer
var _dial_status: Label = null
var _call_time: float = -1.0
# cameras
var _feed: TextureRect = null
var _cam_rec: Panel = null
var _cam_id: Label = null
var _cam_time: Label = null
var _cam_floor: Label = null
var _cam_where: Label = null
var _cam_pager: Label = null
var _cam_lost: Label = null


func setup(phone: PlayerPhoneUI, cctv: CctvApp) -> void:
	_phone = phone
	_cctv = cctv


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seed_threads()
	_build()
	EventBus.time_advanced.connect(_on_time)
	EventBus.objective_updated.connect(_on_objective)
	EventBus.sos_progress_changed.connect(_on_sos_progress)
	EventBus.sos_sent.connect(_on_sos_sent)
	EventBus.midnight_started.connect(_on_update_complete)
	EventBus.robot_online.connect(_on_robot_online)
	EventBus.lab_power_cut.connect(_on_server_lost)
	_clock_text = TimeManager.get_formatted_time()
	visible = false


# ================================================================ control

func show_phone(start_page: Page = Page.HOME) -> void:
	if not _shown:
		_shown = true
		visible = true
		page = Page.HOME
		_size_now = PORTRAIT
		_curtain.color.a = 0.0
	_open_page(start_page)


func hide_phone() -> void:
	_shown = false
	if _cctv != null:
		_cctv.close()


func is_in_cameras() -> bool:
	return _shown and page == Page.CAMERAS


## A short buzz: the phone shakes in Juan's hand.
func buzz() -> void:
	_shake = 0.55


## Mouse wheel.
func scroll(direction: int) -> void:
	if page != Page.CLOCK and page != Page.NOTES and page != Page.DIALER:
		SfxSynth.play_ui(self, SfxSynth.click(), -26.0, 1.8)
	match page:
		Page.HOME:
			selected = posmod(selected + direction, APPS.size())
			_refresh_icons()
		Page.CAMERAS:
			if _cctv != null:
				_cctv.step(direction)
		Page.MESSAGES:
			_thread_sel = posmod(_thread_sel + direction, _threads.size())
			_refresh_thread_list()
		Page.THREAD:
			_thread_scroll.scroll_vertical += direction * 48


## Left click.
func confirm() -> void:
	match page:
		Page.HOME:
			SfxSynth.play_ui(self, SfxSynth.click(), -20.0, 1.3)
			var icon: AppIcon = _icons[selected]
			icon.scale = Vector2.ONE * 0.86
			create_tween().tween_property(icon, ^"scale", Vector2.ONE * 1.06, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_launch(APPS[selected])
		Page.MESSAGES:
			SfxSynth.play_ui(self, SfxSynth.click(), -20.0, 1.3)
			_open_thread(_thread_sel)
		Page.DIALER:
			_place_call()


## Right click. False at the home screen (the caller then lowers the phone).
func back() -> bool:
	match page:
		Page.HOME:
			return false
	SfxSynth.play_ui(self, SfxSynth.click(), -22.0, 1.0)
	match page:
		Page.THREAD:
			_open_page(Page.MESSAGES)
		_:
			_open_page(Page.HOME)
	return true


func _launch(app: StringName) -> void:
	match app:
		&"flashlight":
			_phone.toggle_flashlight()
			_tip("Flashlight On" if _phone.is_flashlight_on else "Flashlight Off")
			_refresh_icons()
		&"cameras":
			_open_page(Page.CAMERAS)
		&"messages":
			_open_page(Page.MESSAGES)
		&"notes":
			_open_page(Page.NOTES)
		&"clock":
			_open_page(Page.CLOCK)
		&"phone":
			_open_page(Page.DIALER)


func _open_page(target: Page) -> void:
	if page == Page.CAMERAS and target != Page.CAMERAS and _cctv != null:
		_cctv.close()
	var turning: bool = (page == Page.CAMERAS) != (target == Page.CAMERAS)
	page = target
	for key: Page in _pages:
		(_pages[key] as Control).visible = key == target
	match target:
		Page.CAMERAS:
			if _cctv != null:
				_cctv.open()
		Page.MESSAGES:
			_refresh_thread_list()
		Page.NOTES:
			_notes_unseen = false
			_refresh_notes()
		Page.DIALER:
			_call_time = -1.0
			_dial_status.text = "Emergency call"
			_dial_status.add_theme_color_override(&"font_color", DIM)
	_refresh_icons()
	_status.visible = target != Page.CAMERAS
	_indicator.visible = target != Page.CAMERAS
	if turning and _shown and _slide > 0.0:
		_curtain.color.a = 1.0
	# Apps zoom in from 94 %.
	_page_t = 0.0 if target != Page.HOME else 0.35


func _tip(text: String) -> void:
	_dock_tip.text = text
	_tip_time = 1.4


func _notify(app: StringName, title: String, body: String) -> void:
	if _banner_time > 0.6:
		_banner_queue.append([app, title, body])
		return
	_banner_icon.kind = app
	_banner_icon.queue_redraw()
	_banner_title.text = title
	_banner_body.text = body
	_banner_time = 3.6
	if _shown:
		buzz()


# ================================================================ frame

func _process(delta: float) -> void:
	_time += delta
	_slide = move_toward(_slide, 1.0 if _shown else 0.0, delta * (4.5 if _shown else 6.0))
	if not _shown and _slide <= 0.0:
		visible = false
		if page == Page.CAMERAS:
			page = Page.HOME
		return
	_layout(delta)
	_update_status()
	_update_banner(delta)
	_page_t = minf(_page_t + delta * 6.5, 1.0)
	var page_node: Control = _pages[page]
	var e: float = ease(_page_t, 0.35)
	page_node.modulate.a = e
	page_node.pivot_offset = page_node.size * 0.5
	page_node.scale = Vector2.ONE * lerpf(0.94, 1.0, e)
	if _tip_time > 0.0:
		_tip_time -= delta
	_dock_tip.modulate.a = clampf(_tip_time * 3.0, 0.0, 1.0)
	match page:
		Page.HOME:
			_update_home()
		Page.CAMERAS:
			_update_cameras()
		Page.CLOCK:
			_update_clock()
		Page.DIALER:
			_update_call(delta)


func _layout(delta: float) -> void:
	var view: Vector2 = get_viewport_rect().size
	var landscape: bool = page == Page.CAMERAS
	var target_size: Vector2 = LANDSCAPE if landscape else PORTRAIT
	_size_now = _size_now.lerp(target_size, 1.0 - exp(-delta * 16.0))
	if _size_now.distance_to(target_size) < 2.0:
		_size_now = target_size
	var rest: Vector2 = (view - _size_now) * 0.5 if landscape else view - _size_now - MARGIN
	var low := Vector2(rest.x, view.y + 30.0)
	var pos: Vector2 = low.lerp(rest, ease(_slide, -2.4))
	if _shake > 0.0:
		_shake -= delta
		pos += Vector2(sin(_time * 95.0), cos(_time * 120.0)) * 3.0 * (_shake / 0.55)
	_rig.position = pos.round()
	_rig.size = _size_now.round()
	_rig.pivot_offset = _rig.size * 0.5
	_rig.rotation = (1.0 - ease(_slide, -2.4)) * 0.12
	# Black while the phone turns, then the picture fades back.
	var turning: float = clampf(_size_now.distance_to(target_size) / 90.0, 0.0, 1.0)
	_curtain.color.a = maxf(move_toward(_curtain.color.a, 0.0, delta * 6.0), turning)
	# The island moves to the side in landscape.
	var scr: Vector2 = _screen.size
	if landscape:
		_island.size = Vector2(22.0, 72.0)
		_island.position = Vector2(9.0, (scr.y - 72.0) * 0.5)
	else:
		_island.size = Vector2(76.0, 22.0)
		_island.position = Vector2((scr.x - 76.0) * 0.5, 9.0)
	_indicator.position = Vector2((scr.x - 96.0) * 0.5, scr.y - 9.0)
	# Control hints float next to the phone, always describing this page.
	if _hint_page != page:
		_hint_page = page
		_fill_hints()
	var hs: Vector2 = _hints.get_combined_minimum_size()
	_hints.size = hs
	if landscape:
		_hints.position = Vector2(_rig.position.x + (_rig.size.x - hs.x) * 0.5, _rig.position.y + _rig.size.y + 12.0)
	else:
		_hints.position = Vector2(_rig.position.x + _rig.size.x - hs.x, _rig.position.y - hs.y - 10.0)
	_hints.modulate.a = ease(_slide, 2.0)


## What each input does on the current page: [key, action].
func _hint_items() -> Array:
	match page:
		Page.HOME:
			return [["WHEEL", "Select"], ["LMB", "Open"], ["RMB", "Put away"]]
		Page.CAMERAS:
			return [["WHEEL", "Switch camera"], ["RMB", "Back"], ["V", "Close"]]
		Page.MESSAGES:
			return [["WHEEL", "Select"], ["LMB", "Open"], ["RMB", "Back"]]
		Page.THREAD:
			return [["WHEEL", "Scroll"], ["RMB", "Back"]]
		Page.DIALER:
			return [["LMB", "Call"], ["RMB", "Back"]]
	return [["RMB", "Back"]]


func _fill_hints() -> void:
	for c: Node in _hint_row.get_children():
		c.queue_free()
	for item: Array in _hint_items():
		var cap := _label(11, Color(0.08, 0.08, 0.1), 700, HORIZONTAL_ALIGNMENT_CENTER)
		cap.text = item[0]
		var sb := box(Color(0.93, 0.93, 0.95), 4.0)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		cap.add_theme_stylebox_override(&"normal", sb)
		_hint_row.add_child(cap)
		var act := _label(12, Color(0.95, 0.94, 0.9), 500)
		act.text = item[1]
		_hint_row.add_child(act)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(6, 0)
		_hint_row.add_child(gap)
	_hint_row.get_child(_hint_row.get_child_count() - 1).queue_free()


func _update_status() -> void:
	_status_time.text = _clock_text.get_slice(" ", 0)
	var battery: float = _battery()
	_status_icons.battery = battery
	var on_roof: bool = _is_on_roof()
	_status_icons.bars = 1 if on_roof else 0
	_status_icons.service = "SOS" if on_roof else ""
	_status_icons.wifi = _has_wifi() and not on_roof
	_status_icons.queue_redraw()
	for limit: float in [20.0, 10.0]:
		if _last_battery >= 0.0 and _last_battery > limit and battery <= limit:
			_notify(&"battery", "Low Battery", "%d%% of battery remaining." % int(limit))
	_last_battery = battery


func _update_banner(delta: float) -> void:
	_banner_time = maxf(_banner_time - delta, 0.0)
	if _banner_time <= 0.0 and not _banner_queue.is_empty() and _banner.position.y < -60.0:
		var next: Array = _banner_queue.pop_front()
		_notify(next[0], next[1], next[2])
	var showing: float = 1.0 if _banner_time > 0.0 else 0.0
	var top: float = 14.0 if page == Page.CAMERAS else 40.0
	var y_target: float = lerpf(-80.0, top, showing)
	_banner.position.y = lerpf(_banner.position.y, y_target, 1.0 - exp(-delta * 12.0))
	var w: float = minf(_screen.size.x - 16.0, 360.0)
	_banner.size.x = w
	_banner.position.x = (_screen.size.x - w) * 0.5
	_banner.visible = _banner.position.y > -78.0


func _update_home() -> void:
	_big_clock.text = _clock_text.get_slice(" ", 0)
	_date.text = "Friday, November 14"
	var objective: String = _objectives.back() if not _objectives.is_empty() else "Get out of the building."
	# Pre-wrapped and capped at three lines; Notes has the whole text.
	_widget_text.text = _clamp_lines(objective, font(600), 13, SW - 56.0, 3)
	var progress: float = update_progress()
	if not _has_wifi():
		_live_status.text = "Server unreachable"
		_live_pct.text = "--"
	elif progress < 1.0:
		_live_status.text = "Firmware v2.4 \u00B7 installing"
		_live_pct.text = "%d%%" % int(progress * 100.0)
	else:
		_live_status.text = "v2.4 installed \u00B7 4 online"
		_live_pct.text = "100%"
	_live_fill.size.x = maxf((SW - 28.0 - 64.0) * progress, 4.0)


## How far the rogue update is, 0..1, from the game clock.
func update_progress() -> float:
	return clampf((float(TimeManager.elapsed_minutes) - UPDATE_START) / (UPDATE_END - UPDATE_START), 0.0, 1.0)


## School Wi-Fi is up while WARDEN's circuit (and its UPS) is.
func _has_wifi() -> bool:
	return _cctv == null or not _cctv.is_offline


func _update_cameras() -> void:
	if _cctv == null:
		return
	(_feed.material as ShaderMaterial).set_shader_parameter(&"switch_static", _cctv.get_static())
	_cam_rec.modulate.a = 1.0 if fmod(_time, 1.2) < 0.75 else 0.15
	var count: int = _cctv.feed_count()
	_cam_id.text = "REC   CAM %02d" % (_cctv.feed_index() + 1)
	_cam_time.text = "11/14   %s" % _clock_text
	_cam_floor.text = Campus.floor_name(_cctv.feed_floor())
	# The floor already has its own chip; drop the "1F - " prefix.
	var where: String = _cctv.feed_name()
	_cam_where.text = where.get_slice(" - ", 1) if where.contains(" - ") else where
	_cam_pager.text = "‹   %02d / %02d   ›" % [_cctv.feed_index() + 1, count]
	_cam_lost.visible = _cctv.is_offline
	_cam_rec.visible = not _cctv.is_offline
	if _cctv.is_offline:
		_cam_id.text = "CAM %02d" % (_cctv.feed_index() + 1)


func _update_clock() -> void:
	_clock_face.hour = TimeManager.get_hour()
	_clock_face.minute = TimeManager.get_minute()
	_clock_face.queue_redraw()
	_clock_digital.text = _clock_text
	_clock_date.text = "Friday, November 14"


func _update_call(delta: float) -> void:
	if _call_time < 0.0:
		return
	_call_time += delta
	if _call_time < 2.2:
		_dial_status.text = "Calling" + ".".repeat(int(_call_time * 3.0) % 4)
	elif _call_time < 2.3:
		_dial_status.text = "Call Failed"
		_dial_status.add_theme_color_override(&"font_color", RED)
		buzz()
		_call_time = 2.3
	elif _call_time > 4.5:
		_dial_status.text = "No Service"
		_dial_status.add_theme_color_override(&"font_color", DIM)
		_call_time = -1.0


func _place_call() -> void:
	if _call_time >= 0.0:
		return
	_call_time = 0.0
	_dial_status.add_theme_color_override(&"font_color", GREEN)
	SfxSynth.play_ui(self, SfxSynth.click(), -18.0, 1.4)


func _battery() -> float:
	if _phone != null and _phone._stats != null:
		return _phone._stats.phone_battery
	return 100.0


func _is_on_roof() -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	return player != null and Campus.floor_from_y(player.global_position.y) == Campus.ROOF_FLOOR


# ================================================================ events

func _on_time(hour: int, minute: int, formatted: String, _p: float) -> void:
	_clock_text = formatted
	for icon: AppIcon in _icons:
		if icon.kind == &"clock":
			icon.hour = hour
			icon.minute = minute
			icon.queue_redraw()


func _on_objective(_id: StringName, text: String, _p: float) -> void:
	if not _objectives.is_empty() and _objectives.back() == text:
		return
	var first: bool = _objectives.is_empty()
	_objectives.append(text)
	if not first:
		_notes_unseen = true
		_notify(&"notes", "Notes", text)
	if page == Page.NOTES:
		_refresh_notes()
	_refresh_icons()


## 12:00 AM: the update finishes. The phone buzzes even in Juan's pocket.
func _on_update_complete() -> void:
	if _update_done:
		return
	_update_done = true
	var t: Dictionary = _thread(&"robot_expo")
	(t["msgs"] as Array).append({"out": false, "time": "12:00 AM",
		"text": "Update complete. Firmware v2.4 is installed. Robots are rebooting one at a time. After-hours patrol: ON."})
	t["unread"] = int(t["unread"]) + 1
	_threads.erase(t)
	_threads.push_front(t)
	_notify(&"robot", "Robot Expo", "Update complete. Rebooting robots one at a time. After-hours patrol: ON.")
	SfxSynth.play_ui(self, SfxSynth.phone_buzz(), -10.0)
	if not _shown:
		EventBus.ui_notification.emit("Your phone buzzes. A notification lights up the screen.", 3.5)
	_refresh_icons()
	if page == Page.MESSAGES:
		_refresh_thread_list()


## Each robot coming back online is reported by the app - the one piece of
## warning Juan gets that another one is loose.
func _on_robot_online(robot_name: String) -> void:
	if not _has_wifi():
		return
	# POSE comes online on the same frame the update finishes: report that first.
	_on_update_complete()
	var t: Dictionary = _thread(&"robot_expo")
	(t["msgs"] as Array).append({"out": false, "time": _clock_text, "text": "%s rebooted. Status: ONLINE." % robot_name})
	t["unread"] = int(t["unread"]) + 1
	_notify(&"robot", "Robot Expo", "%s rebooted. Status: ONLINE." % robot_name)
	SfxSynth.play_ui(self, SfxSynth.phone_buzz(), -12.0)
	if not _shown:
		EventBus.ui_notification.emit("Your phone buzzes: %s is back online." % robot_name, 3.5)
	_refresh_icons()


## The server died: the app loses it, and the Wi-Fi drops.
func _on_server_lost(_cause: StringName) -> void:
	_notify(&"robot", "Robot Expo", "Connection to the server lost.")


func _thread(id: StringName) -> Dictionary:
	for t: Dictionary in _threads:
		if t.get("id", &"") == id:
			return t
	return {}


func _on_sos_progress(seconds: float, required: float) -> void:
	if int(seconds) % 5 == 0:
		_notify(&"messages", "Sending SOS…", "%d of %d seconds. Keep the phone up." % [int(seconds), int(required)])


func _on_sos_sent() -> void:
	_threads.push_front({
		"name": "Emergency SOS", "color": RED, "unread": 1,
		"msgs": [
			{"out": true, "text": "SOS. I'm trapped inside STI College Kalibo. The gate is locked. Please send help.", "time": _clock_text},
			{"out": false, "text": "Emergency services: Your location was received. Help is on the way. ETA %s. Stay somewhere safe." % TimeManager.get_rescue_time_text(), "time": _clock_text},
		],
	})
	_notify(&"messages", "Emergency SOS", "Help is on the way. ETA %s." % TimeManager.get_rescue_time_text())
	_refresh_icons()
	if page == Page.MESSAGES:
		_refresh_thread_list()


# ================================================================ messages

func _seed_threads() -> void:
	_threads = [
		{"name": "Mama", "color": Color(0.9, 0.45, 0.6), "unread": 2, "msgs": [
			{"out": false, "text": "Where are you? Dinner is getting cold.", "time": "8:02 PM"},
			{"out": false, "text": "Text me when you're on your way home.", "time": "9:47 PM"},
			{"out": false, "text": "Juan??", "time": "11:31 PM"},
			{"out": true, "text": "Ma I fell asleep at school. I think I'm locked in", "time": "11:45 PM", "failed": true},
		]},
		{"name": "CpE x CS Expo Booth", "color": Color(0.95, 0.55, 0.2), "unread": 6, "group": true, "msgs": [
			{"out": false, "from": "Kyle", "text": "uhh why are the bots updating?? who pushed v2.4", "time": "11:38 PM"},
			{"out": false, "from": "Rina", "text": "not me", "time": "11:38 PM"},
			{"out": false, "from": "Marco", "text": "not me either, I'm literally in bed", "time": "11:39 PM"},
			{"out": false, "from": "Kyle", "text": "the lab cam shows them twitching on the docks. that's not in any changelog", "time": "11:41 PM"},
			{"out": false, "from": "Rina", "text": "wait the lab cam just flashed white. was that a SPARK??", "time": "11:44 PM"},
			{"out": false, "from": "Kyle", "text": "I'm telling Sir first thing tomorrow. nobody touch anything", "time": "11:44 PM"},
		]},
		{"id": &"robot_expo", "name": "Robot Expo", "color": ROBOT_ORANGE, "unread": 2, "msgs": [
			{"out": false, "text": "Firmware update v2.4 started on POSE, CONCIERGE, SCUTTLE and PROTOTYPE. Keep the robots docked until it completes.", "time": "11:38 PM"},
			{"out": false, "text": "Warning: abnormal current draw on 4 robots.", "time": "11:44 PM"},
		]},
		{"name": "Kyle (CpE)", "color": Color(0.35, 0.45, 0.95), "unread": 0, "msgs": [
			{"out": false, "text": "expo setup done. the bots are charging in the Com Sci Lab, 2F", "time": "6:15 PM"},
			{"out": false, "text": "DON'T touch them. firmware is still buggy", "time": "6:15 PM"},
			{"out": true, "text": "ok ok. which one's the creepy mannequin", "time": "6:20 PM"},
			{"out": false, "text": "POSE lol. it only moves when nobody is looking at it. motion test thing", "time": "7:40 PM"},
			{"out": false, "text": "and the CCTV counts as looking. we left the cams running all night", "time": "7:40 PM"},
		]},
		{"name": "BSCS 3-A", "color": Color(0.3, 0.7, 0.55), "unread": 0, "msgs": [
			{"out": false, "text": "Ma'am says the expo starts 8 AM sharp, be there by 7", "time": "4:58 PM"},
			{"out": false, "text": "who's left in the lab?", "time": "5:30 PM"},
			{"out": true, "text": "me, finishing the poster", "time": "5:31 PM"},
		]},
	]


func _unread_total() -> int:
	var n: int = 0
	for t: Dictionary in _threads:
		n += int(t["unread"])
	return n


func _refresh_thread_list() -> void:
	for c: Node in _thread_list.get_children():
		c.queue_free()
	for i in _threads.size():
		var t: Dictionary = _threads[i]
		var msgs: Array = t["msgs"]
		var last: Dictionary = msgs.back()
		var row := Panel.new()
		row.custom_minimum_size = Vector2(SW - 16.0, 58.0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row_box := box(Color(1, 1, 1, 0.1) if i == _thread_sel else Color(0, 0, 0, 0), 14.0)
		if i == _thread_sel:
			row_box.border_color = Color(1, 1, 1, 0.95)
			row_box.set_border_width_all(2)
		row.add_theme_stylebox_override(&"panel", row_box)
		_thread_list.add_child(row)
		var av := Avatar.new()
		av.letter = String(t["name"]).left(1)
		av.color = t["color"]
		_place(row, av, Vector2(8, 10), Vector2(38, 38))
		var unread: bool = int(t["unread"]) > 0
		var name := _label(14, WHITE, 700 if unread else 500)
		name.text = t["name"]
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_place(row, name, Vector2(54, 9), Vector2(100, 20))
		var when := _label(11, DIM, 400, HORIZONTAL_ALIGNMENT_RIGHT)
		when.text = last["time"]
		_place(row, when, Vector2(140, 11), Vector2(60, 16))
		var preview := _label(12, Color(1, 1, 1, 0.88) if unread else DIM, 400)
		var prefix: String = "You: " if last["out"] else (String(last["from"]) + ": " if last.has("from") else "")
		preview.text = prefix + String(last["text"])
		preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_place(row, preview, Vector2(54, 30), Vector2(130 if int(t["unread"]) > 0 else 146, 18))
		if int(t["unread"]) > 0:
			var dot := Panel.new()
			dot.add_theme_stylebox_override(&"panel", box(BLUE, 5.0))
			_place(row, dot, Vector2(192, 34), Vector2(10, 10))


func _open_thread(index: int) -> void:
	var t: Dictionary = _threads[index]
	t["unread"] = 0
	_thread_name.text = t["name"]
	_thread_avatar.letter = String(t["name"]).left(1)
	_thread_avatar.color = t["color"]
	_thread_avatar.queue_redraw()
	for c: Node in _thread_rows.get_children():
		c.queue_free()
	var last_time: String = ""
	for m: Dictionary in t["msgs"]:
		if m["time"] != last_time:
			last_time = m["time"]
			var stamp := _label(11, FAINT, 500, HORIZONTAL_ALIGNMENT_CENTER)
			stamp.text = "Today " + last_time
			_thread_rows.add_child(stamp)
		_thread_rows.add_child(_bubble(m))
	_open_page(Page.THREAD)
	_scroll_thread_to_end.call_deferred()


func _scroll_thread_to_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_thread_scroll.scroll_vertical = int(_thread_scroll.get_v_scroll_bar().max_value)


func _bubble(m: Dictionary) -> Control:
	var out: bool = m["out"]
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if m.has("from") and not out:
		var who := _label(11, Color(1, 1, 1, 0.6), 600)
		who.text = "   " + String(m["from"])
		column.add_child(who)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := box(BLUE if out else Color(0.17, 0.17, 0.19), 16.0)
	sb.content_margin_left = 11
	sb.content_margin_right = 11
	sb.content_margin_top = 7
	sb.content_margin_bottom = 8
	bubble.add_theme_stylebox_override(&"panel", sb)
	var text := _label(13, WHITE, 400)
	text.text = m["text"]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var w: float = font(400).get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	text.custom_minimum_size.x = minf(ceilf(w) + 2.0, 148.0)
	bubble.add_child(text)
	if out:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(spacer)
	if m.get("failed", false):
		var fail := _label(11, RED, 600, HORIZONTAL_ALIGNMENT_RIGHT)
		fail.text = "Not Delivered"
		column.add_child(fail)
	return column


# ================================================================ notes

func _refresh_notes() -> void:
	for c: Node in _notes_list.get_children():
		c.queue_free()
	if _objectives.is_empty():
		_objectives.append("Get out of the building.")
	var start: int = maxi(_objectives.size() - 7, 0)
	for i in range(_objectives.size() - 1, start - 1, -1):
		var current: bool = i == _objectives.size() - 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var check := CheckDot.new()
		check.done = not current
		check.custom_minimum_size = Vector2(18, 18)
		check.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(check)
		var text := _label(13, WHITE if current else FAINT, 600 if current else 400)
		text.text = _objectives[i]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_notes_list.add_child(row)
		if current and _objectives.size() > 1:
			var line := Panel.new()
			line.custom_minimum_size = Vector2(0, 1)
			line.add_theme_stylebox_override(&"panel", box(Color(1, 1, 1, 0.08), 0.0))
			_notes_list.add_child(line)
			var done := _label(11, FAINT, 600)
			done.text = "COMPLETED"
			_notes_list.add_child(done)


func _refresh_icons() -> void:
	for i in _icons.size():
		var icon: AppIcon = _icons[i]
		icon.selected = page == Page.HOME and i == selected
		icon.lit = icon.kind == &"flashlight" and _phone != null and _phone.is_flashlight_on
		match icon.kind:
			&"messages":
				icon.badge = _unread_total()
			&"notes":
				icon.badge = 1 if _notes_unseen else 0
		icon.queue_redraw()
	# The selected icon is also slightly larger, not just ringed.
	for i in _icons.size():
		_icons[i].pivot_offset = _icons[i].size * 0.5
		_icons[i].scale = Vector2.ONE * (1.06 if page == Page.HOME and i == selected else 1.0)


# ================================================================ build

func _build() -> void:
	_rig = Control.new()
	_rig.size = PORTRAIT
	_rig.position = Vector2(-3000, -3000)
	_rig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rig)
	# Side buttons, tucked behind the band so only their edge shows.
	for b: Array in [[true, 92.0, 26.0], [true, 132.0, 44.0], [true, 186.0, 44.0], [false, 150.0, 70.0]]:
		var btn := Panel.new()
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_theme_stylebox_override(&"panel", box(Color(0.3, 0.31, 0.34), 2.0))
		if b[0]:
			btn.position = Vector2(-2.5, b[1])
			btn.size = Vector2(5.0, b[2])
		else:
			btn.anchor_left = 1.0
			btn.anchor_right = 1.0
			btn.offset_left = -2.5
			btn.offset_right = 2.5
			btn.offset_top = b[1]
			btn.offset_bottom = b[1] + b[2]
		_rig.add_child(btn)
	# Titanium band, with a soft shadow under the phone.
	var band := Panel.new()
	_inset(band, 0.0)
	var band_box := box(Color(0.25, 0.26, 0.28), BODY_RADIUS)
	band_box.border_color = Color(0.5, 0.51, 0.54)
	band_box.set_border_width_all(1)
	band_box.shadow_color = Color(0, 0, 0, 0.55)
	band_box.shadow_size = 22
	band_box.shadow_offset = Vector2(0, 8)
	band.add_theme_stylebox_override(&"panel", band_box)
	_rig.add_child(band)
	# Black glass around the display.
	var glass := Panel.new()
	_inset(glass, FRAME)
	glass.add_theme_stylebox_override(&"panel", box(Color(0.0, 0.0, 0.0), BODY_RADIUS - FRAME))
	_rig.add_child(glass)
	# The display. clip_children masks every child to its rounded, anti-aliased shape.
	_screen = Panel.new()
	_inset(_screen, FRAME + BEZEL)
	_screen.add_theme_stylebox_override(&"panel", box(Color(0.0, 0.0, 0.0), SCREEN_RADIUS))
	_screen.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_rig.add_child(_screen)
	_build_wallpaper()
	_pages[Page.HOME] = _build_home()
	_pages[Page.CAMERAS] = _build_cameras()
	_pages[Page.MESSAGES] = _build_messages()
	_pages[Page.THREAD] = _build_thread()
	_pages[Page.NOTES] = _build_notes()
	_pages[Page.CLOCK] = _build_clock()
	_pages[Page.DIALER] = _build_dialer()
	for key: Page in _pages:
		(_pages[key] as Control).visible = key == Page.HOME
	_build_status_bar()
	_build_banner()
	_island = Panel.new()
	_island.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_island.add_theme_stylebox_override(&"panel", box(Color(0, 0, 0), 11.0))
	_screen.add_child(_island)
	var lens := Panel.new()
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lens.add_theme_stylebox_override(&"panel", box(Color(0.07, 0.08, 0.12), 4.0))
	lens.anchor_left = 0.5
	lens.anchor_right = 0.5
	lens.anchor_top = 0.5
	lens.anchor_bottom = 0.5
	lens.offset_left = 18
	lens.offset_right = 26
	lens.offset_top = -4
	lens.offset_bottom = 4
	_island.add_child(lens)
	_indicator = Panel.new()
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator.size = Vector2(96, 4)
	_indicator.add_theme_stylebox_override(&"panel", box(Color(1, 1, 1, 0.78), 2.0))
	_screen.add_child(_indicator)
	_curtain = ColorRect.new()
	_inset(_curtain, 0.0)
	_curtain.color = Color(0, 0, 0, 0)
	_screen.add_child(_curtain)
	# Glass reflection: a faint diagonal sheen over the whole display.
	var sheen := TextureRect.new()
	_inset(sheen, 0.0)
	sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheen.texture = _linear([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.0)],
		Vector2(0, 0), Vector2(1, 1))
	_screen.add_child(sheen)
	# Key-cap hints on a dark pill so they stay readable over any scene.
	_hints = PanelContainer.new()
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_box := box(Color(0.02, 0.02, 0.03, 0.72), 10.0)
	hint_box.content_margin_left = 10
	hint_box.content_margin_right = 10
	hint_box.content_margin_top = 5
	hint_box.content_margin_bottom = 5
	_hints.add_theme_stylebox_override(&"panel", hint_box)
	add_child(_hints)
	_hint_row = HBoxContainer.new()
	_hint_row.add_theme_constant_override(&"separation", 6)
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.add_child(_hint_row)
	_refresh_icons()


func _build_wallpaper() -> void:
	var base := TextureRect.new()
	_inset(base, 0.0)
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.texture = _linear([Color(0.07, 0.08, 0.2), Color(0.04, 0.03, 0.1), Color(0.01, 0.01, 0.03)], Vector2(0.3, 0.0), Vector2(0.7, 1.0))
	_screen.add_child(base)
	# Soft colour blobs.
	for blob: Array in [[Vector2(-60, -30), 260.0, Color(0.42, 0.22, 0.85, 0.55)],
			[Vector2(110, 230), 300.0, Color(0.05, 0.55, 0.75, 0.38)],
			[Vector2(-80, 360), 240.0, Color(0.85, 0.25, 0.45, 0.28)]]:
		var col: Color = blob[2]
		var r := TextureRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.position = blob[0]
		r.size = Vector2.ONE * float(blob[1])
		var g := Gradient.new()
		g.colors = PackedColorArray([col, Color(col.r, col.g, col.b, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		r.texture = t
		_screen.add_child(r)


func _build_status_bar() -> void:
	_status = Control.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.anchor_right = 1.0
	_status.offset_bottom = 32
	_screen.add_child(_status)
	_status_time = _label(14, WHITE, 600, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_status, _status_time, Vector2(10, 9), Vector2(56, 18))
	_status_icons = StatusIcons.new()
	_status_icons.anchor_left = 1.0
	_status_icons.anchor_right = 1.0
	_status_icons.offset_left = -118
	_status_icons.offset_right = -16
	_status_icons.offset_top = 10
	_status_icons.offset_bottom = 26
	_status.add_child(_status_icons)


func _build_banner() -> void:
	_banner = Panel.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := box(Color(0.16, 0.16, 0.19, 0.95), 18.0)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 10
	_banner.add_theme_stylebox_override(&"panel", sb)
	_banner.size = Vector2(SW - 16.0, 62.0)
	_banner.position = Vector2(8, -90)
	_screen.add_child(_banner)
	_banner_icon = AppIcon.new()
	_banner_icon.kind = &"messages"
	_place(_banner, _banner_icon, Vector2(10, 16), Vector2(30, 30))
	_banner_title = _label(12, WHITE, 600)
	_banner_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_banner.add_child(_banner_title)
	_banner_title.anchor_right = 1.0
	_banner_title.offset_left = 50
	_banner_title.offset_top = 9
	_banner_title.offset_right = -40
	_banner_title.offset_bottom = 25
	var now := _label(11, DIM, 400, HORIZONTAL_ALIGNMENT_RIGHT)
	now.text = "now"
	_banner.add_child(now)
	now.anchor_left = 1.0
	now.anchor_right = 1.0
	now.offset_left = -50
	now.offset_right = -12
	now.offset_top = 10
	now.offset_bottom = 24
	_banner_body = _label(12, Color(0.92, 0.93, 0.96, 0.82), 400)
	_banner_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_body.max_lines_visible = 2
	_banner_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_banner.add_child(_banner_body)
	_banner_body.anchor_right = 1.0
	_banner_body.offset_left = 50
	_banner_body.offset_top = 25
	_banner_body.offset_right = -12
	_banner_body.offset_bottom = 60


func _new_page(opaque: bool) -> Control:
	var p: Control
	if opaque:
		var panel := Panel.new()
		panel.add_theme_stylebox_override(&"panel", box(PAGE_BG, 0.0))
		p = panel
	else:
		p = Control.new()
	_inset(p, 0.0)
	_screen.add_child(p)
	return p


func _app_header(p: Control, title: String, back_to: String = "Home") -> void:
	var back := _label(13, BLUE, 400)
	back.text = "‹ " + back_to
	_place(p, back, Vector2(14, 34), Vector2(100, 18))
	var t := _label(27, WHITE, 700)
	t.text = title
	_place(p, t, Vector2(14, 50), Vector2(SW - 28.0, 36))


func _build_home() -> Control:
	var p := _new_page(false)
	_big_clock = _label(64, Color(1, 1, 1, 0.94), 300, HORIZONTAL_ALIGNMENT_CENTER)
	_place(p, _big_clock, Vector2(0, 34), Vector2(SW, 80))
	_date = _label(13, Color(1, 1, 1, 0.75), 600, HORIZONTAL_ALIGNMENT_CENTER)
	_place(p, _date, Vector2(0, 112), Vector2(SW, 18))
	# Widget: tonight's objective.
	var widget := Panel.new()
	widget.add_theme_stylebox_override(&"panel", box(Color(1, 1, 1, 0.11), 20.0))
	_place(p, widget, Vector2(14, 142), Vector2(SW - 28.0, 92))
	var head := _label(11, ORANGE, 700)
	head.text = "TONIGHT"
	_place(widget, head, Vector2(14, 10), Vector2(80, 14))
	_widget_text = _label(13, WHITE, 600)
	_widget_text.add_theme_constant_override(&"line_spacing", 0)
	_place(widget, _widget_text, Vector2(14, 26), Vector2(SW - 28.0 - 28.0, 54))
	# App row.
	for i in DOCK_FIRST:
		var icon := _make_icon(APPS[i])
		_place(p, icon, Vector2(COLUMN_X[i], 250), Vector2(ICON, ICON))
		var name := _label(11, Color(1, 1, 1, 0.92), 500, HORIZONTAL_ALIGNMENT_CENTER)
		name.text = APP_NAMES[APPS[i]]
		_place(p, name, Vector2(COLUMN_X[i] - 6.0, 294), Vector2(ICON + 12.0, 15))
	# Live activity: the Robot Expo app following the firmware update.
	var live := Panel.new()
	live.add_theme_stylebox_override(&"panel", box(Color(0.0, 0.0, 0.0, 0.42), 18.0))
	_place(p, live, Vector2(14, 318), Vector2(SW - 28.0, 54))
	var robot := AppIcon.new()
	robot.kind = &"robot"
	_place(live, robot, Vector2(10, 12), Vector2(30, 30))
	var title := _label(12, WHITE, 700)
	title.text = "Robot Expo"
	_place(live, title, Vector2(50, 7), Vector2(110, 16))
	_live_status = _label(11, DIM, 500)
	_live_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place(live, _live_status, Vector2(50, 23), Vector2(SW - 28.0 - 62.0, 15))
	_live_pct = _label(13, ROBOT_ORANGE, 700, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(live, _live_pct, Vector2(SW - 28.0 - 56.0, 9), Vector2(44, 18))
	var track := Panel.new()
	track.add_theme_stylebox_override(&"panel", box(Color(1, 1, 1, 0.14), 2.0))
	_place(live, track, Vector2(50, 42), Vector2(SW - 28.0 - 64.0, 4))
	_live_fill = Panel.new()
	_live_fill.add_theme_stylebox_override(&"panel", box(ROBOT_ORANGE, 2.0))
	_place(live, _live_fill, Vector2(50, 42), Vector2(4, 4))
	# Dock.
	var dock := Panel.new()
	dock.add_theme_stylebox_override(&"panel", box(Color(1, 1, 1, 0.12), 26.0))
	_place(p, dock, Vector2(8, SH - 104.0), Vector2(SW - 16.0, 84))
	for i in range(DOCK_FIRST, APPS.size()):
		var col: int = i - DOCK_FIRST
		var icon := _make_icon(APPS[i])
		_place(p, icon, Vector2(COLUMN_X[col], SH - 94.0), Vector2(ICON, ICON))
		var dname := _label(11, Color(1, 1, 1, 0.92), 500, HORIZONTAL_ALIGNMENT_CENTER)
		dname.text = APP_NAMES[APPS[i]]
		dname.add_theme_constant_override(&"outline_size", 0)
		_place(p, dname, Vector2(COLUMN_X[col] - 6.0, SH - 50.0), Vector2(ICON + 12.0, 15))
	_dock_tip = _label(11, WHITE, 600, HORIZONTAL_ALIGNMENT_CENTER)
	_dock_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dock_tip.add_theme_stylebox_override(&"normal", box(Color(0.12, 0.12, 0.14, 0.92), 10.0))
	_place(p, _dock_tip, Vector2((SW - 130.0) * 0.5, SH - 134.0), Vector2(130, 22))
	_dock_tip.modulate.a = 0.0
	return p


func _make_icon(kind: StringName) -> AppIcon:
	var icon := AppIcon.new()
	icon.kind = kind
	icon.hour = TimeManager.get_hour()
	icon.minute = TimeManager.get_minute()
	_icons.append(icon)
	return icon


func _build_cameras() -> Control:
	var p := _new_page(true)
	_feed = TextureRect.new()
	_inset(_feed, 0.0)
	_feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cctv_feed.gdshader")
	_feed.material = mat
	if _cctv != null:
		_feed.texture = _cctv.get_feed_texture()
	p.add_child(_feed)
	var frame := Brackets.new()
	_inset(frame, 22.0)
	p.add_child(frame)
	var mono := Color(0.93, 0.97, 0.92)
	_cam_rec = Panel.new()
	_cam_rec.add_theme_stylebox_override(&"panel", box(RED, 5.0))
	_place(p, _cam_rec, Vector2(46, 42), Vector2(10, 10))
	_cam_id = _label(14, mono, 700)
	_place(p, _cam_id, Vector2(62, 36), Vector2(240, 22))
	_cam_time = _label(13, mono, 600, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchored(p, _cam_time, Vector2(1, 0), Rect2(-300, 36, 256, 22))
	_cam_floor = _label(12, Color(0.05, 0.06, 0.05), 700, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_floor.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cam_floor.add_theme_stylebox_override(&"normal", box(mono, 4.0))
	_anchored(p, _cam_floor, Vector2(0, 1), Rect2(46, -66, 44, 22))
	_cam_where = _label(18, mono, 700)
	_anchored(p, _cam_where, Vector2(0, 1), Rect2(100, -70, 500, 28))
	_cam_pager = _label(14, mono, 600, HORIZONTAL_ALIGNMENT_RIGHT)
	_anchored(p, _cam_pager, Vector2(1, 1), Rect2(-246, -68, 200, 24))
	_cam_lost = _label(30, mono, 700, HORIZONTAL_ALIGNMENT_CENTER)
	_cam_lost.text = "NO SIGNAL"
	_cam_lost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cam_lost.add_theme_stylebox_override(&"normal", box(Color(0, 0, 0, 0.55), 6.0))
	_anchored(p, _cam_lost, Vector2(0.5, 0.5), Rect2(-120, -26, 240, 52))
	_cam_lost.visible = false
	return p


func _build_messages() -> Control:
	var p := _new_page(true)
	_app_header(p, "Messages")
	_thread_list = VBoxContainer.new()
	_thread_list.add_theme_constant_override(&"separation", 2)
	_place(p, _thread_list, Vector2(8, 96), Vector2(SW - 16.0, 360))
	return p


func _build_thread() -> Control:
	var p := _new_page(true)
	_thread_scroll = ScrollContainer.new()
	_thread_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_thread_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var bar: VScrollBar = _thread_scroll.get_v_scroll_bar()
	var track := box(Color(1, 1, 1, 0.06), 2.0)
	track.content_margin_left = 3
	track.content_margin_right = 0
	bar.add_theme_stylebox_override(&"scroll", track)
	bar.add_theme_stylebox_override(&"grabber", box(Color(1, 1, 1, 0.45), 2.0))
	bar.add_theme_stylebox_override(&"grabber_highlight", box(Color(1, 1, 1, 0.45), 2.0))
	bar.add_theme_stylebox_override(&"grabber_pressed", box(Color(1, 1, 1, 0.45), 2.0))
	bar.custom_minimum_size.x = 4
	_place(p, _thread_scroll, Vector2(10, 106), Vector2(SW - 20.0, SH - 166.0))
	# A right margin keeps bubbles clear of the scroll indicator.
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override(&"margin_right", 10)
	pad.add_theme_constant_override(&"margin_top", 4)
	pad.add_theme_constant_override(&"margin_bottom", 4)
	_thread_scroll.add_child(pad)
	_thread_rows = VBoxContainer.new()
	_thread_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thread_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_thread_rows.add_theme_constant_override(&"separation", 6)
	pad.add_child(_thread_rows)
	# Header bar over the conversation.
	var top := Panel.new()
	top.add_theme_stylebox_override(&"panel", box(Color(0.075, 0.075, 0.09, 0.97), 0.0))
	_place(p, top, Vector2(0, 0), Vector2(SW, 102))
	var back := _label(24, BLUE, 400)
	back.text = "‹"
	_place(p, back, Vector2(14, 40), Vector2(20, 32))
	_thread_avatar = Avatar.new()
	_place(p, _thread_avatar, Vector2(SW * 0.5 - 19.0, 38), Vector2(38, 38))
	_thread_name = _label(11, WHITE, 600, HORIZONTAL_ALIGNMENT_CENTER)
	_place(p, _thread_name, Vector2(0, 80), Vector2(SW, 16))
	# Disabled input field: there is no service to send anything.
	var field := Panel.new()
	field.add_theme_stylebox_override(&"panel", _outline(Color(1, 1, 1, 0.22), 15.0))
	_place(p, field, Vector2(12, SH - 52.0), Vector2(SW - 24.0, 30))
	var ph := _label(12, FAINT, 400)
	ph.text = "Text Message  ·  No Service"
	_place(field, ph, Vector2(14, 6), Vector2(170, 18))
	return p


func _build_notes() -> Control:
	var p := _new_page(true)
	_app_header(p, "Notes")
	var sub := _label(11, ORANGE, 700)
	sub.text = "TONIGHT  ·  EXPO NIGHT"
	_place(p, sub, Vector2(14, 88), Vector2(SW - 28.0, 16))
	_notes_list = VBoxContainer.new()
	_notes_list.add_theme_constant_override(&"separation", 12)
	_place(p, _notes_list, Vector2(14, 114), Vector2(SW - 28.0, 340))
	return p


func _build_clock() -> Control:
	var p := _new_page(true)
	_app_header(p, "Clock")
	_clock_face = AppIcon.new()
	_clock_face.kind = &"clock_face"
	_place(p, _clock_face, Vector2(SW * 0.5 - 80.0, 104), Vector2(160, 160))
	_clock_digital = _label(30, WHITE, 300, HORIZONTAL_ALIGNMENT_CENTER)
	_place(p, _clock_digital, Vector2(0, 280), Vector2(SW, 40))
	_clock_date = _label(13, DIM, 500, HORIZONTAL_ALIGNMENT_CENTER)
	_place(p, _clock_date, Vector2(0, 320), Vector2(SW, 18))
	return p


func _build_dialer() -> Control:
	var p := _new_page(true)
	var number := _label(36, WHITE, 300, HORIZONTAL_ALIGNMENT_CENTER)
	number.text = "911"
	_place(p, number, Vector2(0, 46), Vector2(SW, 46))
	_dial_status = _label(12, DIM, 500, HORIZONTAL_ALIGNMENT_CENTER)
	_place(p, _dial_status, Vector2(0, 92), Vector2(SW, 18))
	var keys: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
	var letters: Array[String] = ["", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ", "", "+", ""]
	for i in keys.size():
		var key := Panel.new()
		key.add_theme_stylebox_override(&"panel", box(Color(0.2, 0.2, 0.22), 27.0))
		_place(p, key, Vector2(17.0 + (i % 3) * 68.0, 124.0 + (i / 3) * 62.0), Vector2(54, 54))
		var d := _label(22, WHITE, 400, HORIZONTAL_ALIGNMENT_CENTER)
		d.text = keys[i]
		_place(key, d, Vector2(0, 6 if letters[i] != "" else 12), Vector2(54, 28))
		if letters[i] != "":
			var l := _label(8, Color(1, 1, 1, 0.75), 700, HORIZONTAL_ALIGNMENT_CENTER)
			l.text = letters[i]
			_place(key, l, Vector2(0, 33), Vector2(54, 12))
	var call := Panel.new()
	var call_box := box(GREEN, 27.0)
	call_box.border_color = Color(1, 1, 1, 0.95)
	call_box.set_border_width_all(2)
	call.add_theme_stylebox_override(&"panel", call_box)
	_place(p, call, Vector2(SW * 0.5 - 27.0, 380), Vector2(54, 54))
	var handset := AppIcon.new()
	handset.kind = &"handset"
	_place(call, handset, Vector2(7, 7), Vector2(40, 40))
	return p


# ================================================================ helpers

static func font(weight: int) -> Font:
	if not _fonts.has(weight):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"])
		f.font_weight = weight
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		_fonts[weight] = f
	return _fonts[weight]


static func box(color: Color, radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(round(radius)))
	sb.corner_detail = 20
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 0.8
	return sb


static func _outline(color: Color, radius: float) -> StyleBoxFlat:
	var sb := box(Color(0, 0, 0, 0), radius)
	sb.draw_center = false
	sb.border_color = color
	sb.set_border_width_all(1)
	return sb


## Draws an anti-aliased rounded rectangle on `ci`.
static func rrect(ci: CanvasItem, r: Rect2, radius: float, color: Color, top_only: bool = false) -> void:
	var sb := box(color, minf(radius, minf(r.size.x, r.size.y) * 0.5))
	if top_only:
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
	ci.draw_style_box(sb, r)


## Filled polygon with an anti-aliased edge.
static func poly(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	ci.draw_colored_polygon(pts, color)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, color, 1.0, true)


func _label(font_size: int, color: Color, weight: int = 400, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.add_theme_font_override(&"font", font(weight))
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Word-wraps `text` to `width` px and keeps at most `max_lines` lines, ending
## the last one with an ellipsis if anything was cut.
static func _clamp_lines(text: String, f: Font, fs: int, width: float, max_lines: int) -> String:
	var lines: Array[String] = []
	var line: String = ""
	var words: PackedStringArray = text.split(" ", false)
	var cut: bool = false
	for i in words.size():
		var attempt: String = words[i] if line == "" else line + " " + words[i]
		if f.get_string_size(attempt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width or line == "":
			line = attempt
			continue
		lines.append(line)
		line = words[i]
		if lines.size() == max_lines:
			cut = true
			break
	if not cut and line != "":
		lines.append(line)
	if cut:
		var last: String = lines[max_lines - 1]
		while last != "" and f.get_string_size(last + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			last = last.left(last.length() - 1)
		lines[max_lines - 1] = last.strip_edges().trim_suffix(".").trim_suffix(",") + "…"
	return "\n".join(lines)


func _place(parent: Control, child: Control, pos: Vector2, sz: Vector2) -> void:
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(child)
	child.position = pos
	child.size = sz


## Places `child` relative to an anchor corner (0/1 per axis) of `parent`.
func _anchored(parent: Control, child: Control, anchor: Vector2, r: Rect2) -> void:
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(child)
	child.anchor_left = anchor.x
	child.anchor_right = anchor.x
	child.anchor_top = anchor.y
	child.anchor_bottom = anchor.y
	child.offset_left = r.position.x
	child.offset_top = r.position.y
	child.offset_right = r.end.x
	child.offset_bottom = r.end.y


func _inset(c: Control, by: float) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = by
	c.offset_top = by
	c.offset_right = -by
	c.offset_bottom = -by


func _linear(colors: Array, from: Vector2, to: Vector2) -> GradientTexture2D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / float(colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = from
	t.fill_to = to
	return t


# ================================================================ drawn parts

## An app icon: rounded-square tile with a vector glyph, a badge and a
## selection ring. Also draws the big clock face and the call-button handset.
class AppIcon extends Control:
	var kind: StringName = &""
	var lit: bool = false
	var badge: int = 0
	var selected: bool = false
	var hour: int = 11
	var minute: int = 45

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s: float = size.x
		var u: float = s / 40.0
		var c: Vector2 = size * 0.5
		var full := Rect2(Vector2.ZERO, size)
		var rad: float = s * 0.235
		var W := Color(1, 1, 1)
		if kind == &"clock_face":
			_clock(c, s * 0.5, true)
			return
		if kind == &"handset":
			_handset(c, u, W)
			return
		var bg: Color = _bg()
		PhoneScreen.rrect(self, full, rad, bg)
		PhoneScreen.rrect(self, Rect2(0, 0, s, s * 0.5), rad, Color(1, 1, 1, 0.08), true)
		match kind:
			&"flashlight":
				var g: Color = Color(0.2, 0.16, 0.05) if lit else W
				PhoneScreen.poly(self, PackedVector2Array([c + Vector2(-8, -11) * u, c + Vector2(8, -11) * u,
					c + Vector2(5, -3) * u, c + Vector2(-5, -3) * u]), g)
				PhoneScreen.rrect(self, Rect2(c + Vector2(-9, -14) * u, Vector2(18, 3.5) * u), 1.5 * u, g)
				PhoneScreen.rrect(self, Rect2(c + Vector2(-5, -4) * u, Vector2(10, 18) * u), 2.5 * u, g)
				draw_circle(c + Vector2(0, 2.5) * u, 1.8 * u, bg, true, -1.0, true)
			&"cameras":
				draw_set_transform(c + Vector2(1, -2) * u, -0.3, Vector2.ONE)
				PhoneScreen.rrect(self, Rect2(Vector2(-12, -6) * u, Vector2(20, 11) * u), 3.0 * u, W)
				PhoneScreen.rrect(self, Rect2(Vector2(7, -4.5) * u, Vector2(5, 8) * u), 1.5 * u, Color(0.8, 0.82, 0.86))
				draw_circle(Vector2(-7, -0.5) * u, 1.9 * u, PhoneScreen.RED, true, -1.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_line(c + Vector2(-5, 4) * u, c + Vector2(-7, 11) * u, W, 2.6 * u, true)
				PhoneScreen.rrect(self, Rect2(c + Vector2(-12, 10) * u, Vector2(10, 3) * u), 1.5 * u, W)
			&"messages":
				PhoneScreen.rrect(self, Rect2(c + Vector2(-12, -10) * u, Vector2(24, 18) * u), 9.0 * u, W)
				PhoneScreen.poly(self, PackedVector2Array([c + Vector2(-8, 4) * u, c + Vector2(-12, 11) * u,
					c + Vector2(-2, 7) * u]), W)
			&"battery":
				PhoneScreen.rrect(self, Rect2(c + Vector2(-11, -6) * u, Vector2(20, 12) * u), 3.0 * u, W)
				PhoneScreen.rrect(self, Rect2(c + Vector2(9.5, -2.5) * u, Vector2(2.5, 5) * u), 1.0 * u, W)
				PhoneScreen.rrect(self, Rect2(c + Vector2(-9, -4) * u, Vector2(4, 8) * u), 1.5 * u, PhoneScreen.RED)
			&"notes":
				PhoneScreen.rrect(self, Rect2(0, 0, s, s * 0.3), rad, Color(1.0, 0.8, 0.16), true)
				for i in 4:
					var y: float = (18.0 + i * 5.5) * u
					var x2: float = (31.0 if i < 3 else 22.0) * u
					draw_line(Vector2(9 * u, y), Vector2(x2, y), Color(0.72, 0.72, 0.74), 1.6 * u, true)
			&"robot":
				PhoneScreen.rrect(self, Rect2(c + Vector2(-11, -7) * u, Vector2(22, 17) * u), 5.0 * u, W)
				draw_circle(c + Vector2(-5, 1) * u, 2.6 * u, bg, true, -1.0, true)
				draw_circle(c + Vector2(5, 1) * u, 2.6 * u, bg, true, -1.0, true)
				draw_line(c + Vector2(0, -7) * u, c + Vector2(0, -12) * u, W, 1.8 * u, true)
				draw_circle(c + Vector2(0, -13) * u, 2.0 * u, W, true, -1.0, true)
				PhoneScreen.rrect(self, Rect2(c + Vector2(-14, -2) * u, Vector2(3, 6) * u), 1.0 * u, W)
				PhoneScreen.rrect(self, Rect2(c + Vector2(11, -2) * u, Vector2(3, 6) * u), 1.0 * u, W)
			&"phone":
				_handset(c, u, W)
			&"clock":
				_clock(c, 16.0 * u, false)
		if badge > 0:
			var bc := Vector2(s - 3.0 * u, 3.0 * u)
			draw_circle(bc, 8.5 * u, PhoneScreen.RED, true, -1.0, true)
			var f: Font = PhoneScreen.font(600)
			var txt := str(badge)
			var fs: int = int(11 * u)
			var w: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, bc + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, W)
		if selected:
			var ring := PhoneScreen.box(Color(0, 0, 0, 0), rad + 4.0)
			ring.draw_center = false
			ring.border_color = Color(1, 1, 1, 0.95)
			ring.set_border_width_all(2)
			draw_style_box(ring, full.grow(4.0))

	func _bg() -> Color:
		match kind:
			&"flashlight":
				return Color(1.0, 0.84, 0.32) if lit else Color(0.24, 0.24, 0.27)
			&"cameras":
				return Color(0.17, 0.19, 0.24)
			&"messages", &"phone":
				return PhoneScreen.GREEN
			&"notes":
				return Color(0.99, 0.98, 0.95)
			&"clock":
				return Color(0.06, 0.06, 0.07)
			&"battery":
				return Color(0.24, 0.24, 0.27)
			&"robot":
				return PhoneScreen.ROBOT_ORANGE
		return Color(0.3, 0.3, 0.3)

	func _handset(c: Vector2, u: float, col: Color) -> void:
		var o: Vector2 = c + Vector2(1.5, -1.5) * u
		draw_arc(o, 8.5 * u, PI * 0.3, PI * 1.2, 24, col, 4.6 * u, true)
		draw_circle(o + Vector2.from_angle(PI * 0.3) * 8.5 * u, 3.4 * u, col, true, -1.0, true)
		draw_circle(o + Vector2.from_angle(PI * 1.2) * 8.5 * u, 3.4 * u, col, true, -1.0, true)

	func _clock(c: Vector2, r: float, big: bool) -> void:
		draw_circle(c, r, Color(0.12, 0.12, 0.14) if big else Color(0.97, 0.97, 0.98), true, -1.0, true)
		var ink: Color = Color(0.95, 0.95, 0.97) if big else Color(0.1, 0.1, 0.12)
		for i in 12:
			var a: float = TAU * i / 12.0
			var inner: float = r * (0.78 if i % 3 == 0 else 0.86)
			draw_line(c + Vector2.from_angle(a) * inner, c + Vector2.from_angle(a) * r * 0.92, ink,
				maxf(r * (0.05 if i % 3 == 0 else 0.03), 1.0), true)
		var m_angle: float = TAU * minute / 60.0 - PI * 0.5
		var h_angle: float = TAU * (float(hour % 12) + minute / 60.0) / 12.0 - PI * 0.5
		draw_line(c, c + Vector2.from_angle(h_angle) * r * 0.5, ink, maxf(r * 0.09, 1.5), true)
		draw_line(c, c + Vector2.from_angle(m_angle) * r * 0.74, ink, maxf(r * 0.06, 1.2), true)
		draw_circle(c, maxf(r * 0.07, 1.5), PhoneScreen.ORANGE, true, -1.0, true)


## Signal bars or "No Service", and the battery glyph with its percentage.
class StatusIcons extends Control:
	var bars: int = 0
	var service: String = "No Service"
	var battery: float = 100.0
	var wifi: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f: Font = PhoneScreen.font(600)
		var W := PhoneScreen.WHITE
		var x: float = size.x - 26.0
		var y: float = 2.0
		var low: bool = battery <= 20.0
		var outline := PhoneScreen.box(Color(0, 0, 0, 0), 3.5)
		outline.draw_center = false
		outline.border_color = Color(1, 1, 1, 0.45)
		outline.set_border_width_all(1)
		draw_style_box(outline, Rect2(x, y, 23, 12))
		PhoneScreen.rrect(self, Rect2(x + 23.5, y + 4, 2.0, 4), 1.0, Color(1, 1, 1, 0.45))
		var fill: float = clampf(battery / 100.0, 0.0, 1.0) * 19.0
		if fill > 0.5:
			PhoneScreen.rrect(self, Rect2(x + 2, y + 2, maxf(fill, 2.0), 8), 2.0, PhoneScreen.RED if low else W)
		var pct := "%d" % int(ceil(battery))
		var pw: float = f.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		x -= pw + 5.0
		draw_string(f, Vector2(x, y + 10.5), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, PhoneScreen.RED if low else W)
		# Wi-Fi: three arcs (school network, no internet).
		if wifi:
			x -= 18.0
			var o := Vector2(x + 7.0, y + 12.0)
			for i in 3:
				draw_arc(o, 3.0 + i * 3.4, PI * 1.25, PI * 1.75, 12, W, 1.8, true)
			draw_circle(o + Vector2(0, -0.6), 1.3, W, true, -1.0, true)
		# Signal: four bars, dim when there is no service.
		x -= 24.0
		for i in 4:
			var h: float = 3.0 + i * 2.6
			PhoneScreen.rrect(self, Rect2(x + i * 4.5, y + 12.0 - h, 3.0, h), 1.0, W if i < bars else Color(1, 1, 1, 0.28))
		x -= 5.0
		if service == "":
			return
		var sw: float = f.get_string_size(service, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(f, Vector2(x - sw, y + 10.5), service, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W)


## Round contact picture with an initial.
class Avatar extends Control:
	var letter: String = "?"
	var color: Color = Color(0.5, 0.5, 0.55)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		draw_circle(c, r, color, true, -1.0, true)
		draw_circle(c + Vector2(0, -r * 0.35), r * 0.62, Color(1, 1, 1, 0.08), true, -1.0, true)
		var f: Font = PhoneScreen.font(600)
		var fs: int = int(r * 0.95)
		var w: float = f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w * 0.5, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))


## Notes checklist dot: ring for the current objective, filled tick when done.
class CheckDot extends Control:
	var done: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 1.0
		if done:
			draw_circle(c, r, Color(PhoneScreen.ORANGE, 0.55), true, -1.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4.5, -3.5)]),
				Color(1, 1, 1, 0.9), 1.8, true)
		else:
			draw_arc(c, r, 0.0, TAU, 40, PhoneScreen.ORANGE, 1.6, true)


## CCTV viewfinder corners and centre cross.
class Brackets extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var col := Color(0.93, 0.97, 0.92, 0.7)
		var l: float = 26.0
		var r := Rect2(Vector2.ZERO, size)
		for corner: Array in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
				[Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
			var p: Vector2 = corner[0]
			var d: Vector2 = corner[1]
			draw_polyline(PackedVector2Array([p + Vector2(0, d.y * l), p, p + Vector2(d.x * l, 0)]), col, 2.0, true)
		var c: Vector2 = size * 0.5
		draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), Color(col, 0.35), 1.0, true)
		draw_line(c + Vector2(0, -10), c + Vector2(0, 10), Color(col, 0.35), 1.0, true)
