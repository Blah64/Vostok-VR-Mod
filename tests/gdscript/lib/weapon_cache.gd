extends RefCounted

# weapon_cache.gd
#
# Pure cache-policy helpers for the per-weapon_rig runtime cache used by
# weapon_sync.ensure_weapon_cache(). Production reuses the cache only when
# (a) the weapon_rig instance id matches the previously cached id AND
# (b) the chain was complete on the previous build. An incomplete chain
# means the game was still loading the weapon — keep retrying every frame
# until everything resolves.
#
# Mirrors weapon_sync.gd:185-221.


# Decide whether the existing cache may be reused for the current frame.
#
# current_id     : weapon_rig.get_instance_id() this frame
# cached_id      : weapon_cache_id stored from the previous build
# prev_complete  : "chain_complete" key from the previous cache (false if
#                  no cache yet)
static func can_reuse_cache(current_id: int, cached_id: int, prev_complete: bool) -> bool:
	return current_id == cached_id and prev_complete


# Decide whether to carry over the prev_arms_hidden flag during a rebuild.
# Production keeps it only when the weapon_rig identity is unchanged
# (otherwise we have a fresh weapon and arms must be re-hidden).
static func should_carry_arms_hidden(current_id: int, cached_id: int) -> bool:
	return current_id == cached_id


# Walk a candidate chain and decide whether it's complete. The chain is
# complete iff every name in chain_names resolves to a Node3D from the
# weapon_rig downward. Used by tests that build a fake scene; matches
# weapon_sync.gd:194-203.
#
# get_child_fn : Callable(node: Node, name: String) -> Variant (Node or null)
static func walk_chain(weapon_rig, chain_names: Array, get_child_fn: Callable) -> Dictionary:
	var chain := {}
	var current = weapon_rig
	var complete := true
	for chain_name in chain_names:
		var child = get_child_fn.call(current, chain_name)
		if child == null:
			complete = false
			break
		chain[chain_name] = child
		current = child
	return {"chain": chain, "chain_complete": complete}
