extends RefCounted

const Chords := preload("res://scripts/chords.gd")

var _mask := 0
var _pool: Array[Chords.Triad] = []
var _bag: Array[Chords.Triad] = []
var _previous_root := -1


func use_groups(mask: int) -> void:
	if mask == _mask:
		return
	_mask = mask
	_pool = Chords.enabled_chords(mask)
	_bag.clear()


func next() -> Chords.Triad:
	if _bag.is_empty():
		_refill()
	var chord: Chords.Triad = _bag.pop_front()
	_previous_root = chord.root
	return chord


func _refill() -> void:
	var shuffled: Array[Chords.Triad] = _pool.duplicate()
	shuffled.shuffle()
	var counts := PackedInt32Array()
	counts.resize(Chords.PITCH_CLASSES)
	for chord in shuffled:
		counts[chord.root] += 1

	var previous := _previous_root
	for _slot in range(shuffled.size()):
		var selected := -1
		for index in range(shuffled.size()):
			var chord := shuffled[index]
			if chord.root == previous:
				continue
			counts[chord.root] -= 1
			if _can_finish(counts, shuffled.size() - 1, chord.root):
				selected = index
				break
			counts[chord.root] += 1
		# Every supported pool has a valid order, even with a preceding root.
		assert(selected >= 0)
		var chord := shuffled[selected]
		shuffled.remove_at(selected)
		_bag.append(chord)
		previous = chord.root


static func _can_finish(counts: PackedInt32Array, remaining: int, previous: int) -> bool:
	# A root needs a different root between each pair, and also before its
	# first occurrence if it matches the preceding chord.
	for root in range(counts.size()):
		var others := remaining - counts[root]
		if counts[root] > others + int(root != previous):
			return false
	return true
