#include "comfort_options.h"

#include <godot_cpp/classes/sphere_mesh.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/xr_camera3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

// ---------------------------------------------------------------------------
// Vignette shader source -- renders as an inverted sphere around the camera.
// The shader darkens edges of view based on a uniform alpha parameter.
// ---------------------------------------------------------------------------
static const char *VIGNETTE_SHADER_CODE = R"(
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, skip_vertex_transform;

uniform float vignette_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_radius : hint_range(0.0, 1.0) = 0.4;
uniform float vignette_softness : hint_range(0.01, 1.0) = 0.3;

void vertex() {
    // Place vignette in view space so it follows the camera
    VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // Compute vignette based on screen UV distance from center
    vec2 uv = SCREEN_UV * 2.0 - 1.0;
    float dist = length(uv);
    float vignette = smoothstep(vignette_radius, vignette_radius + vignette_softness, dist);
    ALBEDO = vec3(0.0);
    ALPHA = vignette * vignette_alpha;
}
)";

ComfortOptions::ComfortOptions() {}

ComfortOptions::~ComfortOptions() {
    // Nodes owned by the tree are freed by the tree.
}

// ---------------------------------------------------------------------------
// initialize - Create the vignette mesh and attach to XR camera
// ---------------------------------------------------------------------------
void ComfortOptions::initialize(XROrigin3D *origin) {
    if (initialized_) {
        UtilityFunctions::print_rich("[color=yellow][RTV-VR] ComfortOptions already initialized.[/color]");
        return;
    }

    if (!origin) {
        UtilityFunctions::print_rich("[color=red][RTV-VR] ComfortOptions::initialize - origin is null.[/color]");
        return;
    }

    create_vignette_mesh(origin);
    initialized_ = true;
    UtilityFunctions::print_rich("[color=green][RTV-VR] ComfortOptions initialized.[/color]");
}

// ---------------------------------------------------------------------------
// create_vignette_mesh - Build a small inverted sphere with the vignette shader
// ---------------------------------------------------------------------------
void ComfortOptions::create_vignette_mesh(XROrigin3D *origin) {
    // Find the XRCamera3D child of the origin to parent the vignette to
    XRCamera3D *camera = nullptr;
    int child_count = origin->get_child_count();
    for (int i = 0; i < child_count; ++i) {
        camera = Object::cast_to<XRCamera3D>(origin->get_child(i));
        if (camera) {
            break;
        }
    }

    if (!camera) {
        UtilityFunctions::print_rich("[color=red][RTV-VR] ComfortOptions - No XRCamera3D found under origin.[/color]");
        return;
    }

    // Create sphere mesh (small, close to camera)
    Ref<SphereMesh> sphere = memnew(SphereMesh);
    sphere->set_radius(0.15f);
    sphere->set_height(0.3f);
    sphere->set_radial_segments(32);
    sphere->set_rings(16);

    // Create shader material
    Ref<Shader> shader = memnew(Shader);
    shader->set_code(VIGNETTE_SHADER_CODE);

    vignette_material_.instantiate();
    vignette_material_->set_shader(shader);
    vignette_material_->set_shader_parameter("vignette_alpha", 0.0f);
    vignette_material_->set_shader_parameter("vignette_radius", 0.4f);
    vignette_material_->set_shader_parameter("vignette_softness", 0.3f);

    // Create mesh instance
    vignette_mesh_ = memnew(MeshInstance3D);
    vignette_mesh_->set_name("RTV_VignetteOverlay");
    vignette_mesh_->set_mesh(sphere);
    vignette_mesh_->set_material_override(vignette_material_);

    // Disable shadow casting and make sure it renders on top
    vignette_mesh_->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
    vignette_mesh_->set_layer_mask(1); // render on layer 1

    camera->add_child(vignette_mesh_);

    // Start hidden if vignette is disabled
    vignette_mesh_->set_visible(vignette_enabled_);
}

// ---------------------------------------------------------------------------
// process_turn - Handle snap or smooth turning
// ---------------------------------------------------------------------------
void ComfortOptions::process_turn(double delta, float input_x, XROrigin3D *origin) {
    if (!origin) {
        return;
    }

    if (turn_type_ == TURN_SNAP) {
        // Snap turn with debounce
        float abs_input = Math::abs(input_x);

        if (abs_input > SNAP_DEADZONE) {
            if (!snap_triggered_) {
                snap_triggered_ = true;

                float direction = input_x > 0.0f ? 1.0f : -1.0f;
                float angle_rad = Math::deg_to_rad(snap_angle_ * direction);

                Transform3D t = origin->get_transform();
                // Rotate around the Y axis at the origin's position
                Basis rotation = Basis(Vector3(0, 1, 0), -angle_rad);
                t.basis = rotation * t.basis;
                origin->set_transform(t);

                UtilityFunctions::print_rich(
                    String("[color=cyan][RTV-VR] Snap turn: {0} degrees[/color]").format(
                        Array::make(snap_angle_ * direction)));
            }
        } else {
            // Input returned to deadzone, allow next snap
            snap_triggered_ = false;
        }
    } else {
        // Smooth turn
        if (Math::abs(input_x) > 0.1f) {
            float angle_rad = Math::deg_to_rad(-input_x * smooth_speed_ * static_cast<float>(delta));

            Transform3D t = origin->get_transform();
            Basis rotation = Basis(Vector3(0, 1, 0), angle_rad);
            t.basis = rotation * t.basis;
            origin->set_transform(t);
        }
    }
}

// ---------------------------------------------------------------------------
// update_vignette - Smoothly fade vignette based on movement
// ---------------------------------------------------------------------------
void ComfortOptions::update_vignette(double delta, bool is_moving) {
    if (!vignette_enabled_ || !vignette_mesh_) {
        return;
    }

    float target = is_moving ? vignette_intensity_ : 0.0f;
    float speed = is_moving ? VIGNETTE_FADE_IN_SPEED : VIGNETTE_FADE_OUT_SPEED;

    current_vignette_ = Math::lerp(current_vignette_, target, static_cast<float>(delta) * speed);

    // Clamp to avoid floating point drift
    if (Math::abs(current_vignette_ - target) < 0.001f) {
        current_vignette_ = target;
    }

    update_vignette_material(current_vignette_);
}

// ---------------------------------------------------------------------------
// update_vignette_material
// ---------------------------------------------------------------------------
void ComfortOptions::update_vignette_material(float alpha) {
    if (vignette_material_.is_valid()) {
        vignette_material_->set_shader_parameter("vignette_alpha", alpha);
    }
}

// ---------------------------------------------------------------------------
// Turn settings
// ---------------------------------------------------------------------------
void ComfortOptions::set_turn_type(TurnType type) {
    turn_type_ = type;
    snap_triggered_ = false; // reset debounce on mode switch
}

ComfortOptions::TurnType ComfortOptions::get_turn_type() const {
    return turn_type_;
}

void ComfortOptions::set_snap_angle(float degrees) {
    snap_angle_ = CLAMP(degrees, 5.0f, 180.0f);
}

float ComfortOptions::get_snap_angle() const {
    return snap_angle_;
}

void ComfortOptions::set_smooth_speed(float degrees_per_second) {
    smooth_speed_ = CLAMP(degrees_per_second, 10.0f, 360.0f);
}

float ComfortOptions::get_smooth_speed() const {
    return smooth_speed_;
}

// ---------------------------------------------------------------------------
// Vignette settings
// ---------------------------------------------------------------------------
void ComfortOptions::set_vignette_enabled(bool enabled) {
    vignette_enabled_ = enabled;
    if (vignette_mesh_) {
        vignette_mesh_->set_visible(enabled);
    }
    if (!enabled) {
        current_vignette_ = 0.0f;
        update_vignette_material(0.0f);
    }
}

bool ComfortOptions::get_vignette_enabled() const {
    return vignette_enabled_;
}

void ComfortOptions::set_vignette_intensity(float intensity) {
    vignette_intensity_ = CLAMP(intensity, 0.0f, 1.0f);
}

float ComfortOptions::get_vignette_intensity() const {
    return vignette_intensity_;
}

// ---------------------------------------------------------------------------
// _bind_methods
// ---------------------------------------------------------------------------
void ComfortOptions::_bind_methods() {
    // Enum constants
    BIND_ENUM_CONSTANT(TURN_SNAP);
    BIND_ENUM_CONSTANT(TURN_SMOOTH);

    // Methods
    ClassDB::bind_method(D_METHOD("initialize", "origin"), &ComfortOptions::initialize);
    ClassDB::bind_method(D_METHOD("process_turn", "delta", "input_x", "origin"), &ComfortOptions::process_turn);
    ClassDB::bind_method(D_METHOD("update_vignette", "delta", "is_moving"), &ComfortOptions::update_vignette);

    // Turn settings
    ClassDB::bind_method(D_METHOD("set_turn_type", "type"), &ComfortOptions::set_turn_type);
    ClassDB::bind_method(D_METHOD("get_turn_type"), &ComfortOptions::get_turn_type);

    ClassDB::bind_method(D_METHOD("set_snap_angle", "degrees"), &ComfortOptions::set_snap_angle);
    ClassDB::bind_method(D_METHOD("get_snap_angle"), &ComfortOptions::get_snap_angle);

    ClassDB::bind_method(D_METHOD("set_smooth_speed", "degrees_per_second"), &ComfortOptions::set_smooth_speed);
    ClassDB::bind_method(D_METHOD("get_smooth_speed"), &ComfortOptions::get_smooth_speed);

    // Vignette settings
    ClassDB::bind_method(D_METHOD("set_vignette_enabled", "enabled"), &ComfortOptions::set_vignette_enabled);
    ClassDB::bind_method(D_METHOD("get_vignette_enabled"), &ComfortOptions::get_vignette_enabled);

    ClassDB::bind_method(D_METHOD("set_vignette_intensity", "intensity"), &ComfortOptions::set_vignette_intensity);
    ClassDB::bind_method(D_METHOD("get_vignette_intensity"), &ComfortOptions::get_vignette_intensity);

    // Properties
    ADD_GROUP("Turn Settings", "");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "turn_type", PROPERTY_HINT_ENUM, "Snap,Smooth"),
        "set_turn_type", "get_turn_type");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "snap_angle", PROPERTY_HINT_RANGE, "5.0,180.0,5.0"),
        "set_snap_angle", "get_snap_angle");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "smooth_speed", PROPERTY_HINT_RANGE, "10.0,360.0,5.0"),
        "set_smooth_speed", "get_smooth_speed");

    ADD_GROUP("Vignette", "vignette_");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "vignette_enabled"),
        "set_vignette_enabled", "get_vignette_enabled");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "vignette_intensity", PROPERTY_HINT_RANGE, "0.0,1.0,0.05"),
        "set_vignette_intensity", "get_vignette_intensity");
}

} // namespace rtv_vr
