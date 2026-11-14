extends Sprite2D
## Walks this sprite to your phone's location, received from OwnTracks via MQTT.
## Attach to a Sprite2D that is NOT inside the CharacterBody2D (e.g. directly under Node2D).
## Uses the MQTT addon in res://addons/mqtt/

# --- MQTT / OwnTracks ---------------------------------------------------
const BROKER_URL := "tcp://test.mosquitto.org:1883"
const DEVICE_ID := "godot-hack-7391"          # must match "Device ID" in OwnTracks
const TOPIC := "owntracks/+/" + DEVICE_ID

# --- Map ----------------------------------------------------------------
# This real-world point appears in the middle of the screen.
const ORIGIN_LAT := 45.495631
const ORIGIN_LON := -73.579097
const PIXELS_PER_METER := 2.0                 # bigger = more zoomed in
const SCREEN_MARGIN := 60.0                   # keep the sprite this many px inside the screen edge

# --- GPS filtering (stops it wandering when you stand still) ----------------
const MAX_ACCURACY_M := 50.0                  # ignore fixes less accurate than this
const MIN_MOVE_M := 6.0                       # ignore moves smaller than this (GPS jitter)
const SMOOTHING := 0.5                        # 0..1, how much each new fix counts (lower = smoother)

# --- Walking ------------------------------------------------------------
const MIN_SPEED := 60.0                       # px/s
const MAX_SPEED := 400.0                      # px/s
const ARRIVE_TIME := 2.5                      # reach a new spot in about this many seconds
const BOB_HEIGHT := 6.0                       # px the sprite bounces while walking (0 = off)
const BOB_SPEED := 12.0
const FLIP_WHEN_MOVING_RIGHT := true          # set false if your sprite faces right by default

var mqtt
var target_pos: Vector2
var walk_speed := MIN_SPEED
var has_fix := false
var last_timestamp := 0
var bob_time := 0.0


func _ready() -> void:
	target_pos = global_position
	_start_mqtt()


func _start_mqtt() -> void:
	var mqtt_script = load("res://addons/mqtt/mqtt.gd")
	if mqtt_script == null:
		push_error("MQTT addon missing: res://addons/mqtt/mqtt.gd")
		return
	mqtt = mqtt_script.new()
	mqtt.verbose_level = 1
	add_child(mqtt)
	mqtt.broker_connected.connect(func():
		print("Connected to broker, listening on ", TOPIC)
		mqtt.subscribe(TOPIC))
	mqtt.broker_connection_failed.connect(func(): push_error("MQTT connection failed"))
	mqtt.received_message.connect(_on_message)
	mqtt.connect_to_broker(BROKER_URL)


func _on_message(_topic, message) -> void:
	var data = JSON.parse_string(str(message))
	if not (data is Dictionary and data.get("_type") == "location"):
		return

	# Skip old / repeated messages (OwnTracks can resend them).
	var tst := int(data.get("tst", 0))
	if tst != 0 and tst <= last_timestamp:
		return
	last_timestamp = tst

	# Skip inaccurate fixes.
	var acc := float(data.get("acc", 0.0))
	if acc > MAX_ACCURACY_M:
		print("Ignoring fix, accuracy %.0f m is too poor" % acc)
		return

	var new_pos := _clamp_to_screen(latlon_to_screen(float(data.lat), float(data.lon)))

	# First fix: appear there right away instead of walking across the map.
	if not has_fix:
		has_fix = true
		global_position = new_pos
		target_pos = new_pos
		print("First GPS fix -> ", new_pos)
		return

	# Tiny moves are GPS noise, not you walking.
	if new_pos.distance_to(target_pos) < MIN_MOVE_M * PIXELS_PER_METER:
		return

	# Blend with the previous target to smooth out zig-zags.
	target_pos = target_pos.lerp(new_pos, SMOOTHING)
	walk_speed = clamp(global_position.distance_to(target_pos) / ARRIVE_TIME, MIN_SPEED, MAX_SPEED)
	print("Location %s, %s (±%.0f m) -> walking to %s" % [data.lat, data.lon, acc, target_pos])


func _process(delta: float) -> void:
	var before := global_position
	# Walk at a steady speed toward the target (no rushing / crawling).
	global_position = global_position.move_toward(target_pos, walk_speed * delta)
	var moved := global_position - before

	if moved.length() > 0.01:
		# Little walking bounce.
		bob_time += delta * BOB_SPEED
		offset.y = -abs(sin(bob_time)) * BOB_HEIGHT
		# Face the walking direction (only on clear sideways movement, so it doesn't flicker).
		if abs(moved.x) > abs(moved.y) * 0.3:
			flip_h = (moved.x > 0) == FLIP_WHEN_MOVING_RIGHT
	else:
		bob_time = 0.0
		offset.y = 0.0


# Turns lat/lon into a screen position. Right = east, up = north.
func latlon_to_screen(lat: float, lon: float) -> Vector2:
	var east_m := (lon - ORIGIN_LON) * 111320.0 * cos(deg_to_rad(ORIGIN_LAT))
	var north_m := (lat - ORIGIN_LAT) * 110540.0
	var center := get_viewport_rect().size / 2
	return center + Vector2(east_m, -north_m) * PIXELS_PER_METER


func _clamp_to_screen(p: Vector2) -> Vector2:
	var size := get_viewport_rect().size
	return Vector2(
		clamp(p.x, SCREEN_MARGIN, size.x - SCREEN_MARGIN),
		clamp(p.y, SCREEN_MARGIN, size.y - SCREEN_MARGIN))
