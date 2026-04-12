#include "weapon_detector.h"

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

WeaponDetector::WeaponDetector() {
    // Default weapon keywords.
    keywords_.push_back("rifle");
    keywords_.push_back("pistol");
    keywords_.push_back("gun");
    keywords_.push_back("weapon");
    keywords_.push_back("ak");
    keywords_.push_back("m4");
    keywords_.push_back("shotgun");
    keywords_.push_back("sniper");
    keywords_.push_back("knife");
    keywords_.push_back("smg");
    keywords_.push_back("revolver");
    keywords_.push_back("grenade");
    keywords_.push_back("launcher");
    keywords_.push_back("firearm");
}

TypedArray<Node3D> WeaponDetector::scan_for_weapons(Node *p_root) {
    TypedArray<Node3D> results;
    if (p_root == nullptr) {
        return results;
    }
    scan_recursive_(p_root, results);
    return results;
}

Node3D *WeaponDetector::find_held_weapon(Node *p_root) {
    if (p_root == nullptr) {
        return nullptr;
    }
    return find_held_recursive_(p_root);
}

void WeaponDetector::set_weapon_keywords(const PackedStringArray &p_keywords) {
    keywords_ = p_keywords;
}

PackedStringArray WeaponDetector::get_weapon_keywords() const {
    return keywords_;
}

void WeaponDetector::_bind_methods() {
    ClassDB::bind_method(D_METHOD("scan_for_weapons", "root"), &WeaponDetector::scan_for_weapons);
    ClassDB::bind_method(D_METHOD("find_held_weapon", "root"), &WeaponDetector::find_held_weapon);
    ClassDB::bind_method(D_METHOD("set_weapon_keywords", "keywords"), &WeaponDetector::set_weapon_keywords);
    ClassDB::bind_method(D_METHOD("get_weapon_keywords"), &WeaponDetector::get_weapon_keywords);

    ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "weapon_keywords"), "set_weapon_keywords", "get_weapon_keywords");
}

void WeaponDetector::scan_recursive_(Node *p_node, TypedArray<Node3D> &r_results) const {
    Node3D *node_3d = Object::cast_to<Node3D>(p_node);
    if (node_3d != nullptr && matches_keywords_(p_node->get_name())) {
        r_results.push_back(node_3d);
    }

    int child_count = p_node->get_child_count();
    for (int i = 0; i < child_count; ++i) {
        scan_recursive_(p_node->get_child(i), r_results);
    }
}

bool WeaponDetector::matches_keywords_(const String &p_name) const {
    String name_lower = p_name.to_lower();
    for (int i = 0; i < keywords_.size(); ++i) {
        if (name_lower.contains(String(keywords_[i]).to_lower())) {
            return true;
        }
    }
    return false;
}

Node3D *WeaponDetector::find_held_recursive_(Node *p_node) const {
    Node3D *node_3d = Object::cast_to<Node3D>(p_node);
    if (node_3d != nullptr && matches_keywords_(p_node->get_name())) {
        // Check if the node is visible and likely held by the player.
        if (node_3d->is_visible_in_tree()) {
            // Check if an ancestor has a player-related name (camera, body, player).
            Node *parent = p_node->get_parent();
            while (parent != nullptr) {
                String parent_name = String(parent->get_name()).to_lower();
                if (parent_name.contains("camera") || parent_name.contains("player") ||
                    parent_name.contains("body") || parent_name.contains("hand") ||
                    parent_name.contains("arm") || parent_name.contains("fps")) {
                    return node_3d;
                }
                parent = parent->get_parent();
            }
        }
    }

    int child_count = p_node->get_child_count();
    for (int i = 0; i < child_count; ++i) {
        Node3D *result = find_held_recursive_(p_node->get_child(i));
        if (result != nullptr) {
            return result;
        }
    }
    return nullptr;
}

} // namespace rtv_vr
