#ifndef RTV_VR_WEAPON_DETECTOR_H
#define RTV_VR_WEAPON_DETECTOR_H

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace rtv_vr {

class WeaponDetector : public godot::RefCounted {
    GDCLASS(WeaponDetector, godot::RefCounted)

public:
    WeaponDetector();
    ~WeaponDetector() override = default;

    /// Recursively searches for Node3D nodes whose names contain weapon keywords.
    godot::TypedArray<godot::Node3D> scan_for_weapons(godot::Node *p_root);

    /// Finds the weapon currently held/active by the player.
    godot::Node3D *find_held_weapon(godot::Node *p_root);

    /// Override default keyword list.
    void set_weapon_keywords(const godot::PackedStringArray &p_keywords);

    /// Get current keywords.
    godot::PackedStringArray get_weapon_keywords() const;

protected:
    static void _bind_methods();

private:
    void scan_recursive_(godot::Node *p_node, godot::TypedArray<godot::Node3D> &r_results) const;
    bool matches_keywords_(const godot::String &p_name) const;
    godot::Node3D *find_held_recursive_(godot::Node *p_node) const;

    godot::PackedStringArray keywords_;
};

} // namespace rtv_vr

#endif // RTV_VR_WEAPON_DETECTOR_H
