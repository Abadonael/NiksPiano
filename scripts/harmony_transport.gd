extends RefCounted

const Model := preload("res://scripts/harmony_composition.gd")
const Patterns := preload("res://scripts/harmony_patterns.gd")
const USEC_PER_MINUTE := 60000000.0
enum State { STOPPED, PLAYING, PAUSED }

var state := State.STOPPED
var event_index := -1
var pass_index := 0
var beat := 0
var _project: Dictionary
var _length := 0
var _origin := 0
var _held_time := 0
var _last_attack := -1
var _attacks: Array[Array] = []


static func time_at_beat(at_beat: float, bpm: int) -> int:
	return ceili(at_beat * USEC_PER_MINUTE / bpm)


func start(project: Dictionary, now_usec: int) -> bool:
	stop()
	_length = Model.length_beats(project)
	if _length == 0:
		return false
	_project = project.duplicate(true)
	for event: Dictionary in _project.events:
		_attacks.append(Patterns.attacks(event, Patterns.effective(_project.default_pattern, event)))
	_origin = now_usec
	state = State.PLAYING
	return true


func stop() -> void:
	state = State.STOPPED
	event_index = -1
	pass_index = 0
	beat = 0
	_last_attack = -1
	_attacks.clear()
	_project = {}


func pause(now_usec: int) -> void:
	if state == State.PLAYING:
		_held_time = maxi(0, now_usec - _origin)
		_last_attack = maxi(_last_attack, _eighth_at(_held_time))
		state = State.PAUSED


func resume(now_usec: int) -> void:
	if state == State.PAUSED:
		_origin = now_usec - _held_time
		state = State.PLAYING


func tick(now_usec: int) -> Dictionary:
	if state != State.PLAYING:
		return {}
	var elapsed := maxi(0, now_usec - _origin)
	var eighth := _eighth_at(elapsed)
	@warning_ignore("integer_division")
	var absolute_beat := eighth / Patterns.SUBDIVISIONS
	@warning_ignore("integer_division")
	pass_index = absolute_beat / _length
	if _project.repeat != 0 and pass_index >= int(_project.repeat):
		stop()
		return {}
	beat = absolute_beat % _length
	var events: Array = _project.events
	var low := 0
	var high := events.size() - 1
	while low < high:
		@warning_ignore("integer_division")
		var middle := (low + high + 1) / 2
		if int(events[middle].start_beat) <= beat:
			low = middle
		else:
			high = middle - 1
	event_index = low
	var event: Dictionary = events[event_index]
	var event_start := (pass_index * _length + int(event.start_beat)) * Patterns.SUBDIVISIONS
	# After a hitch, deliver only the latest due attack in the current event.
	for index in range(_attacks[event_index].size() - 1, -1, -1):
		var attack: Dictionary = _attacks[event_index][index]
		var attack_time := event_start + int(attack.offset)
		if attack_time > eighth:
			continue
		if attack_time <= _last_attack:
			return {}
		_last_attack = attack_time
		var result := event.duplicate()
		result.attack_pitches = attack.pitches
		return result
	return {}


func _eighth_at(elapsed: int) -> int:
	return floori(elapsed * int(_project.bpm) * Patterns.SUBDIVISIONS / USEC_PER_MINUTE)
