class_name WorldRand
extends RefCounted
## Stable pseudo-random numbers for placing scenery: the same key and index always give the
## same value, and neighboring indices are unrelated (good for scattering).


static var _last_key := ""
static var _last_hash := 0


## A float in [0, 1).
static func f(key: String, i: int = 0) -> float:
	# Scatter loops ask for many indices of one key in a row: hash the string once.
	if key != _last_key:
		_last_key = key
		_last_hash = hash(key) * 668265263
	var h := _last_hash + i * 374761393
	h = (h ^ (h >> 15)) * 2246822519
	h = (h ^ (h >> 13)) * 3266489917
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0
