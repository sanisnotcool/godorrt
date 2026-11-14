extends Node
## Loads room data from Google Sheets (columns: ROOMS, EVENTS, PEOPLE).
## Add as an Autoload named "Data".

# From File > Share > Publish to web (CSV) link:
# https://docs.google.com/spreadsheets/d/e/<SHEET_ID>/pub?gid=<ROOMS_GID>&single=true&output=csv
const SHEET_ID := "PASTE_YOUR_2PACX_ID_HERE"
const ROOMS_GID := "0"

signal data_ready
var loaded := false
var rooms := {}  # room number (int) -> { "events": Array[String], "people": int }


func _ready() -> void:
	if OS.is_debug_build() and not SHEET_ID.begins_with("PASTE"):
		await _download()
	_load()
	loaded = true
	data_ready.emit()
	print("Loaded rooms: ", rooms)


func has_room(num: int) -> bool:
	return rooms.has(num)

func get_people(num: int) -> int:
	return rooms.get(num, {}).get("people", 0)

func get_events(num: int) -> Array:
	return rooms.get(num, {}).get("events", [])


func _download() -> void:
	var url := "https://docs.google.com/spreadsheets/d/e/%s/pub?gid=%s&single=true&output=csv" % [SHEET_ID, ROOMS_GID]
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url)
	var res: Array = await http.request_completed  # [result, code, headers, body]
	http.queue_free()
	if res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200:
		FileAccess.open("user://rooms.csv", FileAccess.WRITE).store_buffer(res[3])
	else:
		push_warning("Couldn't download rooms (code %s), using local copy" % res[1])


func _load() -> void:
	var path := "user://rooms.csv" if FileAccess.file_exists("user://rooms.csv") else "res://data/rooms.csv"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("No rooms file found at " + path)
		return

	var headers := Array(f.get_csv_line()).map(func(h): return h.strip_edges().to_upper())
	var c_room := headers.find("ROOMS")
	var c_events := headers.find("EVENTS")
	var c_people := headers.find("PEOPLE")
	if c_room == -1 or c_events == -1 or c_people == -1:
		push_error("rooms.csv needs ROOMS, EVENTS and PEOPLE headers, got: %s" % [headers])
		return

	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < headers.size() or not row[c_room].strip_edges().is_valid_int():
			continue  # skip blank rows
		rooms[row[c_room].to_int()] = {
			"events": _split(row[c_events]),
			"people": row[c_people].strip_edges().to_int(),
		}


func _split(cell: String) -> Array:
	var out := []
	for s in cell.split(",", false):
		if s.strip_edges() != "":
			out.append(s.strip_edges())
	return out
