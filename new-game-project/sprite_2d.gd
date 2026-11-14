extends Sprite2D
## Walks this sprite to your phone's location, received from OwnTracks via MQTT.
## Attach to a Sprite2D that is NOT inside the CharacterBody2D (e.g. directly under Node2D).
## Uses the MQTT addon in res://addons/mqtt/

const BROKER_URL := "tcp://test.mosquitto.org:1883"
const DEVICE_ID := "godot-hack-7391"          # must match "Device ID" in OwnTracks
const TOPIC := "owntracks/+/" + DEVICE_ID

# This real-world point = where you placed the sprite in the editor.
const ORIGIN_LAT := 45.495631
const ORIGIN_LON := -73.579097
const PIXELS_PER_METER := 96.0                 # bigger = more zoomed in
const SCREEN_MARGIN := 60.0                   # keep the sprite this many px inside the screen edge



# Walking
const MIN_SPEED := 10.0                       # px/s
const MAX_SPEED := 600.0                      # px/s
# Your phone only gets a NEW position every few seconds (it repeats the old one in between).
# The sprite takes about as long as the last gap to walk to each new spot,
# so it keeps moving smoothly instead of dashing then standing still.
const MIN_ARRIVE_TIME := 1.0                  # seconds
const MAX_ARRIVE_TIME := 8.0                  # seconds
const BOB_HEIGHT := 6.0                       # px bounce while walking (0 = off)
const BOB_SPEED := 12.0
const FLIP_WHEN_MOVING_RIGHT := true          # set false if your sprite faces right by default

var mqtt
var map_origin: Vector2
var target_pos: Vector2
var walk_speed := MIN_SPEED
var has_fix := false
var bob_time := 0.0
var last_change_time := 0.0                    # when the phone last reported a NEW position


func _ready() -> void:
	map_origin = global_position
	target_pos = global_position

	var mqtt_script = load("res://addons/mqtt/mqtt.gd")
	if mqtt_script == null:
		push_error("MQTT addon missing: res://addons/mqtt/mqtt.gd")
		return
	mqtt = mqtt_script.new()
	mqtt.verbose_level = 1
	add_child(mqtt)
	mqtt.broker_connected.connect(_on_connected)
	mqtt.broker_connection_failed.connect(func(): push_error("MQTT connection failed"))
	mqtt.received_message.connect(_on_message)
	mqtt.connect_to_broker(BROKER_URL)


func _on_connected() -> void:
	print("Connected to broker, listening on ", TOPIC)
	mqtt.subscribe(TOPIC)


func _on_message(_topic, message) -> void:
	var data = JSON.parse_string(str(message))
	if not (data is Dictionary and data.get("_type") == "location"):
		return

	var new_pos := _clamp_to_screen(latlon_to_screen(float(data.lat), float(data.lon)))
	var now := Time.get_ticks_msec() / 1000.0

	# First fix: appear there right away instead of walking across the map.
	if not has_fix:
		has_fix = true
		global_position = new_pos
		target_pos = new_pos
		last_change_time = now
		print("Location: ", data.lat, ", ", data.lon, " -> ", new_pos, "  (start)")
		return

	# Same spot repeated, or a tiny GPS wobble: keep walking to the current target.
	if new_pos.distance_to(target_pos) <  PIXELS_PER_METER:
		print("Location: ", data.lat, ", ", data.lon, "  (no change)")
		return

	# Walk there over about the same time the phone took to give us this new spot.
	var arrive_time: float = clamp(now - last_change_time, MIN_ARRIVE_TIME, MAX_ARRIVE_TIME)
	last_change_time = now
	target_pos = new_pos
	walk_speed = clamp(global_position.distance_to(target_pos) / arrive_time, MIN_SPEED, MAX_SPEED)
	print("Location: ", data.lat, ", ", data.lon, " -> ", new_pos, "  (NEW, walking over %.1f s)" % arrive_time)


func _process(delta: float) -> void:
	var before := global_position
	global_position = global_position.move_toward(target_pos, walk_speed * delta)
	var moved := global_position - before

	if moved.length() > 0.01:
		bob_time += delta * BOB_SPEED
		offset.y = -abs(sin(bob_time)) * BOB_HEIGHT
		# Face the walking direction (only on clear sideways movement, so it doesn't flicker).
		if abs(moved.x) > abs(moved.y) * 0.3:
			flip_h = (moved.x > 0) == FLIP_WHEN_MOVING_RIGHT
	else:
		bob_time = 0.0
		offset.y = 0.0


# Turns lat/lon into a screen position. Right = east, up = north.
# ORIGIN_LAT/LON lands where the sprite was placed in the editor.
func latlon_to_screen(lat: float, lon: float) -> Vector2:
	var east_m := (lon - ORIGIN_LON) * 111320.0 * cos(deg_to_rad(ORIGIN_LAT))
	var north_m := (lat - ORIGIN_LAT) * 110540.0
	return map_origin + Vector2(east_m, -north_m) * PIXELS_PER_METER


func _clamp_to_screen(p: Vector2) -> Vector2:
	var size := get_viewport_rect().size
	return Vector2(
		clamp(p.x, SCREEN_MARGIN, size.x - SCREEN_MARGIN),
		clamp(p.y, SCREEN_MARGIN, size.y - SCREEN_MARGIN))
