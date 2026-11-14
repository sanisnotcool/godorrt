extends Sprite2D
## Moves this sprite to your phone's location, received from OwnTracks via MQTT.
## Uses the MQTT addon in res://addons/mqtt/

const BROKER_URL := "tcp://test.mosquitto.org:1883"
# Must match "Device ID" in OwnTracks.
const DEVICE_ID := "godot-hack-7391"
const TOPIC := "owntracks/+/" + DEVICE_ID

# This real-world point appears in the middle of the screen.
const ORIGIN_LAT := 45.495631
const ORIGIN_LON := -73.579097
# How many pixels one meter takes up on screen. Bigger = more zoomed in.
const PIXELS_PER_METER := 2.0

var mqtt
var target_pos := Vector2.ZERO


func _ready() -> void:
	target_pos = get_viewport_rect().size / 2
	global_position = target_pos

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


func _on_message(topic, message) -> void:
	var data = JSON.parse_string(str(message))
	if data is Dictionary and data.get("_type") == "location":
		target_pos = latlon_to_screen(float(data.lat), float(data.lon))
		print("Location: ", data.lat, ", ", data.lon, " -> ", target_pos)


func _process(delta: float) -> void:
	# Glide toward the new position instead of teleporting
	# global_position because this sprite is a child of CharacterBody2D
	global_position = global_position.lerp(target_pos, 1.0 - exp(-3.0 * delta))


# Turns lat/lon into a screen position. Right = east, up = north.
func latlon_to_screen(lat: float, lon: float) -> Vector2:
	var east_m := (lon - ORIGIN_LON) * 111320.0 * cos(deg_to_rad(ORIGIN_LAT))
	var north_m := (lat - ORIGIN_LAT) * 110540.0
	var center := get_viewport_rect().size / 2
	return center + Vector2(east_m, -north_m) * PIXELS_PER_METER
