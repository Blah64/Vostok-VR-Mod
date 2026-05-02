extends RefCounted

# test_weapon_cache.gd
#
# Coverage for the weapon-cache reuse policy. The production flow is:
#   1. Each frame, ensure_weapon_cache(weapon_rig) is called.
#   2. If the weapon_rig instance id matches the previous AND the chain was
#      complete last time, reuse the cache untouched.
#   3. Otherwise rebuild. Carry over arms_hidden iff the id matches.
#   4. Rebuild walks _RECOIL_CHAIN_NAMES; "complete" means every name
#      resolved to a Node3D.
#
# Cache invalidation is the most common source of stale-state bugs at the
# Phase 4 split (e.g., scope PIP not refreshing on weapon swap), so we pin
# the policy down here.

const WeaponCache = preload("res://tests/gdscript/lib/weapon_cache.gd")


# Mirrors vr_mod_init.gd:_RECOIL_CHAIN_NAMES (recoil chain under weapon_rig).
const _CHAIN_NAMES := ["Handling", "Sway", "Noise", "Tilt", "Impulse", "Recoil", "Holder"]


# --- can_reuse_cache ----------------------------------------------------

func test_reuse_when_same_id_and_complete(t) -> void:
	t.assert_true(WeaponCache.can_reuse_cache(42, 42, true), "same id + complete -> reuse")


func test_reject_when_id_changes(t) -> void:
	# Weapon swap: id changes, even if the previous chain was complete.
	t.assert_true(not WeaponCache.can_reuse_cache(99, 42, true), "different id -> rebuild")


func test_reject_when_prev_chain_incomplete(t) -> void:
	# Same weapon_rig but the previous frame caught it mid-load.
	# Must keep retrying until the chain is fully resolved.
	t.assert_true(not WeaponCache.can_reuse_cache(42, 42, false), "incomplete chain -> rebuild")


func test_reject_first_frame(t) -> void:
	# First frame: cached_id is whatever was zeroed-out (commonly 0).
	# Even if the new weapon_rig somehow had id 0, prev_complete is false.
	t.assert_true(not WeaponCache.can_reuse_cache(123, 0, false), "first frame -> rebuild")


# --- should_carry_arms_hidden -------------------------------------------

func test_carry_arms_hidden_when_id_unchanged(t) -> void:
	t.assert_true(WeaponCache.should_carry_arms_hidden(42, 42), "same id -> keep arms_hidden flag")


func test_drop_arms_hidden_on_swap(t) -> void:
	t.assert_true(not WeaponCache.should_carry_arms_hidden(99, 42), "weapon swap -> reset arms_hidden")


# --- walk_chain ---------------------------------------------------------
#
# Build a fake hierarchy of plain RefCounted "nodes" via Dictionary lookups
# so the test runs without instantiating the real Godot scene tree.

class FakeNode:
	var name: String
	var children: Dictionary = {}
	func _init(n: String) -> void:
		name = n


# Helper: build a chain from weapon_rig down through chain_names so each
# named node is a child of the previous. Returns the rig.
func _build_chain(chain_names: Array) -> FakeNode:
	var rig := FakeNode.new("weapon_rig")
	var current := rig
	for n in chain_names:
		var child := FakeNode.new(n)
		current.children[n] = child
		current = child
	return rig


# Helper: build a chain that breaks after the Nth element (Nth not present).
func _build_chain_broken_at(chain_names: Array, missing_index: int) -> FakeNode:
	var rig := FakeNode.new("weapon_rig")
	var current := rig
	for i in chain_names.size():
		if i == missing_index:
			break
		var n: String = chain_names[i]
		var child := FakeNode.new(n)
		current.children[n] = child
		current = child
	return rig


func _get_child(node, name: String):
	if node == null:
		return null
	if node is FakeNode:
		return node.children.get(name, null)
	return null


func test_walk_chain_complete(t) -> void:
	var rig := _build_chain(_CHAIN_NAMES)
	var result := WeaponCache.walk_chain(rig, _CHAIN_NAMES, Callable(self, "_get_child"))
	t.assert_true(result["chain_complete"], "fully populated chain reports complete")
	t.assert_eq(result["chain"].size(), _CHAIN_NAMES.size(), "chain dict has every named link")
	# Spot-check a deep link.
	t.assert_eq(result["chain"]["Holder"].name, "Holder", "Holder resolved at the deep end")


func test_walk_chain_breaks_early_first_node(t) -> void:
	var rig := _build_chain_broken_at(_CHAIN_NAMES, 0)
	var result := WeaponCache.walk_chain(rig, _CHAIN_NAMES, Callable(self, "_get_child"))
	t.assert_true(not result["chain_complete"], "missing first link -> incomplete")
	t.assert_eq(result["chain"].size(), 0, "no links collected when first is missing")


func test_walk_chain_breaks_mid_chain(t) -> void:
	# Break at index 3 (Tilt missing). Should collect Handling, Sway, Noise (3 nodes) and stop.
	var rig := _build_chain_broken_at(_CHAIN_NAMES, 3)
	var result := WeaponCache.walk_chain(rig, _CHAIN_NAMES, Callable(self, "_get_child"))
	t.assert_true(not result["chain_complete"], "mid-chain break -> incomplete")
	t.assert_eq(result["chain"].size(), 3, "collected exactly the nodes before the break")
	t.assert_true(result["chain"].has("Noise"), "Noise (last good link) is present")
	t.assert_true(not result["chain"].has("Tilt"), "Tilt (missing) is absent")


func test_walk_empty_chain_names(t) -> void:
	# Edge case: no names to look for. Should be trivially complete.
	var rig := _build_chain([])
	var result := WeaponCache.walk_chain(rig, [], Callable(self, "_get_child"))
	t.assert_true(result["chain_complete"], "empty chain_names -> complete by definition")
	t.assert_eq(result["chain"].size(), 0, "no links collected for empty input")


# --- end-to-end policy interaction -------------------------------------

func test_swap_then_complete_invalidates_then_caches(t) -> void:
	# Frame 1: weapon A, complete -> cache.
	# Frame 2: weapon A, complete -> reuse (no rebuild needed).
	# Frame 3: weapon B (id changes), complete -> rebuild.
	# Frame 4: weapon B, complete -> reuse.
	t.assert_true(not WeaponCache.can_reuse_cache(1, 0, false), "frame 1: no prior cache -> build")
	t.assert_true(WeaponCache.can_reuse_cache(1, 1, true), "frame 2: same weapon -> reuse")
	t.assert_true(not WeaponCache.can_reuse_cache(2, 1, true), "frame 3: weapon swap -> rebuild")
	t.assert_true(WeaponCache.can_reuse_cache(2, 2, true), "frame 4: same new weapon -> reuse")


func test_loading_then_complete_invalidates_until_ready(t) -> void:
	# Game still loading the weapon: chain is incomplete on frames 1 and 2.
	# Cache must rebuild every frame until the chain finishes loading.
	t.assert_true(not WeaponCache.can_reuse_cache(7, 0, false), "frame 1 (no cache): build")
	t.assert_true(not WeaponCache.can_reuse_cache(7, 7, false), "frame 2 (loading): rebuild")
	t.assert_true(not WeaponCache.can_reuse_cache(7, 7, false), "frame 3 (still loading): rebuild")
	# Once chain finishes loading, prev_complete becomes true on the next call.
	t.assert_true(WeaponCache.can_reuse_cache(7, 7, true), "frame 4 (loaded): reuse")
