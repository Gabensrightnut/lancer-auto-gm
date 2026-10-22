class_name WorldRand
extends RefCounted
## Stable pseudo-random numbers for placing scenery: the same key and index always give the
## same value, and neighboring indices are unrelated (good for scattering).


## A float in [0, 1).
static func f(key: String, i: int = 0) -> float:
	var h := hash(key) * 668265263 + i * 374761393
	h = (h ^ (h >> 15)) * 2246822519
	h = (h ^ (h >> 13)) * 3266489917
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0
