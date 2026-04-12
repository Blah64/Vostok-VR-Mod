#include "laser_pointer.h"

#include <godot_cpp/classes/cylinder_mesh.hpp>
#include <godot_cpp/classes/sphere_mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

LaserPointer::LaserPointer() = default;
LaserPointer::~LaserPointer() = default;

void LaserPointer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "controller"), &LaserPointer::initialize);

    ClassDB::bind_method(D_METHOD("set_visible", "visible"), &LaserPointer::set_visible);
    ClassDB::bind_method(D_METHOD("get_visible"), &LaserPointer::get_visible);

    ClassDB::bind_method(D_METHOD("set_color", "color"), &LaserPointer::set_color);
    ClassDB::bind_method(D_METHOD("get_color"), &LaserPointer::get_color);

    ClassDB::bind_method(D_METHOD("set_max_length", "meters"), &LaserPointer::set_max_length);
    ClassDB::bind_method(D_METHOD("get_max_length"), &LaserPointer::get_max_length);

    ClassDB::bind_method(D_METHOD("get_hit_info"), &LaserPointer::get_hit_info);

    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "laser_visible"),
            "set_visible", "get_visible");
    ADD_PROPERTY(PropertyInfo(Variant::COLOR, "ray_color"),
            "set_color", "get_color");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_length", PROPERTY_HINT_RANGE, "0.5,20.0,0.5"),
            "set_max_length", "get_max_length");

    ADD_SIGNAL(MethodInfo("hit_detected",
            PropertyInfo(Variant::DICTIONARY, "hit_info")));
}

void LaserPointer::initialize(XRController3D *p_controller) {
    if (!p_controller) {
        UtilityFunctions::push_warning("LaserPointer: controller is null.");
        return;
    }
    controller_ = p_controller;

    // --- Ray mesh (thin cylinder) ---
    Ref<CylinderMesh> cyl;
    cyl.instantiate();
    cyl->set_top_radius(0.002f);
    cyl->set_bottom_radius(0.002f);
    cyl->set_height(max_length_);
    cyl->set_radial_segments(8);
    cyl->set_rings(1);

    Ref<StandardMaterial3D> ray_mat;
    ray_mat.instantiate();
    ray_mat->set_shading_mode(StandardMaterial3D::SHADING_MODE_UNSHADED);
    ray_mat->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA);
    ray_mat->set_albedo(ray_color_);
    ray_mat->set_flag(StandardMaterial3D::FLAG_DISABLE_DEPTH_TEST, false);
    ray_mat->set_cull_mode(StandardMaterial3D::CULL_DISABLED);

    ray_mesh_ = memnew(MeshInstance3D);
    ray_mesh_->set_mesh(cyl);
    ray_mesh_->set_surface_override_material(0, ray_mat);
    add_child(ray_mesh_);

    // The cylinder's axis is along Y by default. Rotate so it points along -Z (forward).
    ray_mesh_->set_rotation(Vector3(Math::deg_to_rad(90.0f), 0.0f, 0.0f));
    // Offset so the cylinder starts at origin and extends forward.
    ray_mesh_->set_position(Vector3(0.0f, 0.0f, -max_length_ * 0.5f));

    // --- Hit marker (small sphere) ---
    Ref<SphereMesh> sphere;
    sphere.instantiate();
    sphere->set_radius(0.01f);
    sphere->set_height(0.02f);
    sphere->set_radial_segments(16);
    sphere->set_rings(8);

    Ref<StandardMaterial3D> marker_mat;
    marker_mat.instantiate();
    marker_mat->set_shading_mode(StandardMaterial3D::SHADING_MODE_UNSHADED);
    marker_mat->set_albedo(Color(1.0f, 1.0f, 1.0f, 0.9f));
    marker_mat->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA);

    MeshInstance3D *marker_mesh = memnew(MeshInstance3D);
    marker_mesh->set_mesh(sphere);
    marker_mesh->set_surface_override_material(0, marker_mat);

    hit_marker_ = memnew(Node3D);
    hit_marker_->add_child(marker_mesh);
    hit_marker_->set_visible(false);
    add_child(hit_marker_);

    // Attach this node to the controller.
    if (get_parent()) {
        get_parent()->remove_child(this);
    }
    controller_->add_child(this);
    set_transform(Transform3D());

    UtilityFunctions::print("LaserPointer: initialized on controller '", controller_->get_name(), "'.");
}

void LaserPointer::_process(double p_delta) {
    if (!controller_ || !visible_) {
        if (ray_mesh_) {
            ray_mesh_->set_visible(false);
        }
        if (hit_marker_) {
            hit_marker_->set_visible(false);
        }
        return;
    }

    ray_mesh_->set_visible(true);

    Transform3D global_xform = get_global_transform();
    Vector3 origin = global_xform.origin;
    Vector3 forward = -global_xform.basis.get_column(2).normalized();
    Vector3 end = origin + forward * max_length_;

    // Raycast.
    PhysicsDirectSpaceState3D *space_state = get_world_3d()->get_direct_space_state();
    if (!space_state) {
        hit_marker_->set_visible(false);
        update_ray_mesh(max_length_);
        return;
    }

    Ref<PhysicsRayQueryParameters3D> query = PhysicsRayQueryParameters3D::create(origin, end);
    query->set_collide_with_areas(true);
    query->set_collide_with_bodies(true);

    Dictionary result = space_state->intersect_ray(query);

    if (!result.is_empty()) {
        Vector3 hit_pos = result["position"];
        float hit_dist = origin.distance_to(hit_pos);

        hit_marker_->set_global_position(hit_pos);
        hit_marker_->set_visible(true);

        update_ray_mesh(hit_dist);

        last_hit_info_ = result;
        emit_signal("hit_detected", result);
    } else {
        hit_marker_->set_visible(false);
        update_ray_mesh(max_length_);
        last_hit_info_ = Dictionary();
    }
}

void LaserPointer::set_visible(bool p_visible) {
    visible_ = p_visible;
    if (ray_mesh_) {
        ray_mesh_->set_visible(p_visible);
    }
    if (hit_marker_ && !p_visible) {
        hit_marker_->set_visible(false);
    }
}

bool LaserPointer::get_visible() const {
    return visible_;
}

void LaserPointer::set_color(const Color &p_color) {
    ray_color_ = p_color;
    if (ray_mesh_) {
        Ref<StandardMaterial3D> mat = ray_mesh_->get_surface_override_material(0);
        if (mat.is_valid()) {
            mat->set_albedo(ray_color_);
        }
    }
}

Color LaserPointer::get_color() const {
    return ray_color_;
}

void LaserPointer::set_max_length(float p_meters) {
    max_length_ = CLAMP(p_meters, 0.5f, 20.0f);
}

float LaserPointer::get_max_length() const {
    return max_length_;
}

Dictionary LaserPointer::get_hit_info() const {
    return last_hit_info_;
}

void LaserPointer::update_ray_mesh(float p_length) {
    if (!ray_mesh_) {
        return;
    }
    Ref<CylinderMesh> cyl = ray_mesh_->get_mesh();
    if (cyl.is_valid()) {
        cyl->set_height(p_length);
    }
    // Reposition so it starts at origin and extends forward along -Z.
    ray_mesh_->set_position(Vector3(0.0f, 0.0f, -p_length * 0.5f));
}

} // namespace rtv_vr
