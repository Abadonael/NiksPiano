extends RefCounted

const Theory := preload("res://scripts/key_theory.gd")

var target: Theory.Tonality
var common := 0
var removed := ""
var added := ""
var signature_change: String


func _init(source_sector: int, direction: int, prefer_flats: bool, minor := false) -> void:
	var source := Theory.at_sector(source_sector, prefer_flats, minor)
	# A zero step switches rings in the current sector.
	var target_sector := posmod(source_sector + direction, Theory.WHEEL.size())
	target = Theory.at_sector(target_sector, prefer_flats, not minor if direction == 0 else minor)
	var source_names := _by_pitch(source)
	var target_names := _by_pitch(target)
	for pitch in source_names:
		if target_names.has(pitch):
			common += 1
		else:
			removed = source_names[pitch]
	for pitch in target_names:
		if not source_names.has(pitch):
			added = target_names[pitch]
	var from_signature := source.signature_names()
	var to_signature := target.signature_names()
	if source.signature == target.signature:
		signature_change = "Одинаковые ключевые знаки"
	elif source.signature * target.signature < 0:
		signature_change = "Смена записи: %s → %s" % ["  ".join(from_signature), "  ".join(to_signature)]
	elif absi(target.signature) > absi(source.signature):
		signature_change = "Новый ключевой знак: " + to_signature[-1]
	else:
		signature_change = "Убран ключевой знак: " + from_signature[-1]


static func _by_pitch(key: Theory.Tonality) -> Dictionary[int, String]:
	var result: Dictionary[int, String] = {}
	for degree in range(7):
		result[key.pitch_class(degree)] = key.note_name(degree)
	return result
