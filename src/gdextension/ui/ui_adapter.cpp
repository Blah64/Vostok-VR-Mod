#include "ui_adapter.h"

#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/viewport_texture.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/classes/xr_controller3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

namespace rtv_vr {

UIAdapter::UIAdapter() = default;

UIAdapter::~UIAdapter() {
    restore_ui();
}

void UIAdapter::_bind_methods() {
    // Methods
    ClassDB::bind_method(D_METHOD("adapt_ui", "scene_root"), &UIAdapter::adapt_ui);
    ClassDB::bind_method(D_METHOD("restore_ui"), &UIAdapter::restore_ui);

    ClassDB::bind_method(D_METHOD("set_anchor_mode", "mode"), &UIAdapter::set_anchor_mode);
    ClassDB::bind_method(D_METHOD("get_anchor_mode"), &UIAdapter::get_anchor_mode);

    ClassDB::bind_method(D_METHOD("set_camera", "camera"), &UIAdapter::set_camera);
    ClassDB::bind_method(D_METHOD("get_camera"), &UIAdapter::get_camera);

    ClassDB::bind_method(D_METHOD("set_distance", "meters"), &UIAdapter::set_distance);
    ClassDB::bind_method(D_METHOD("get_distance"), &UIAdapter::get_distance);

    ClassDB::bind_method(D_METHOD("set_ui_scale", "scale"), &UIAdapter::set_scale);
    ClassDB::bind_method(D_METHOD("get_ui_scale"), &UIAdapter::get_scale);

    ClassDB::bind_method(D_METHOD("set_opacity", "opacity"), &UIAdapter::set_opacity);
    ClassDB::bind_method(D_METHOD("get_opacity"), &UIAdapter::get_opacity);

    // Properties
    ADD_PROPERTY(PropertyInfo(Variant::INT, "anchor_mode", PROPERTY_HINT_ENUM,
                     "HeadLocked,WristAttached,WorldFixed"),
            "set_anchor_mode", "get_anchor_mode");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "distance", PROPERTY_HINT_RANGE, "0.3,5.0,0.1"),
            "set_distance", "get_distance");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ui_scale", PROPERTY_HINT_RANGE, "0.1,3.0,0.1"),
            "set_ui_scale", "get_ui_scale");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "opacity", PROPERTY_HINT_RANGE, "0.0,1.0,0.05"),
            "set_opacity", "get_opacity");

    // Enum constants
    BIND_ENUM_CONSTANT(ANCHOR_HEAD_LOCKED);
    BIND_ENUM_CONSTANT(ANCHOR_WRIST_ATTACHED);
    BIND_ENUM_CONSTANT(ANCHOR_WORLD_FIXED);

    // Signals
    ADD_SIGNAL(MethodInfo("ui_adapted", PropertyInfo(Variant::INT, "panel_count")));
    ADD_SIGNAL(MethodInfo("ui_restored"));
}

bool UIAdapter::adapt_ui(Node *p_scene_root) {
    if (!p_scene_root) {
        UtilityFunctions::push_warning("UIAdapter: scene_root is null.");
        return false;
    }

    restore_ui();

    // Find all CanvasLayer nodes in the scene tree.
    Vector<CanvasLayer *> canvas_layers;
    collect_canvas_layers(p_scene_root, canvas_layers);

    for (int i = 0; i < canvas_layers.size(); i++) {
        CanvasLayer *layer = canvas_layers[i];
        // Gather Control children (snapshot the list before reparenting).
        Vector<Control *> controls;
        for (int c = 0; c < layer->get_child_count(); c++) {
            Control *ctrl = Object::cast_to<Control>(layer->get_child(c));
            if (ctrl) {
                controls.push_back(ctrl);
            }
        }

        for (int c = 0; c < controls.size(); c++) {
            Control *ctrl = controls[c];
            Vector2 size = ctrl->get_size();
            if (size.x < 1.0f || size.y < 1.0f) {
                size = Vector2(1024, 768);
            }

            // Create SubViewport.
            SubViewport *vp = memnew(SubViewport);
            vp->set_size(Vector2i((int)size.x, (int)size.y));
            vp->set_transparent_background(true);
            vp->set_update_mode(SubViewport::UPDATE_ALWAYS);
            add_child(vp);

            // Reparent Control into the SubViewport.
            ctrl->get_parent()->remove_child(ctrl);
            vp->add_child(ctrl);

            // Create the 3D quad.
            Ref<QuadMesh> quad_mesh;
            quad_mesh.instantiate();
            float aspect = size.x / size.y;
            float quad_height = (size.y / 1000.0f) * ui_scale_;
            float quad_width = quad_height * aspect;
            quad_mesh->set_size(Vector2(quad_width, quad_height));

            // Material with viewport texture.
            Ref<StandardMaterial3D> mat;
            mat.instantiate();
            mat->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA);
            mat->set_shading_mode(StandardMaterial3D::SHADING_MODE_UNSHADED);
            mat->set_flag(StandardMaterial3D::FLAG_DISABLE_DEPTH_TEST, false);
            mat->set_albedo(Color(1.0f, 1.0f, 1.0f, ui_opacity_));
            Ref<ViewportTexture> vp_tex = vp->get_texture();
            mat->set_texture(StandardMaterial3D::TEXTURE_ALBEDO, Ref<Texture2D>(vp_tex));
            mat->set_cull_mode(StandardMaterial3D::CULL_DISABLED);

            MeshInstance3D *mesh_inst = memnew(MeshInstance3D);
            mesh_inst->set_mesh(quad_mesh);
            mesh_inst->set_surface_override_material(0, mat);
            add_child(mesh_inst);

            // Store record.
            AdaptedPanel panel;
            panel.original = ctrl;
            panel.viewport = vp;
            panel.quad = mesh_inst;
            panel.source_canvas_layer = layer;
            panel.original_size = size;
            panels_.push_back(panel);
        }
    }

    first_frame_ = true;

    if (!panels_.is_empty()) {
        emit_signal("ui_adapted", panels_.size());
        UtilityFunctions::print("UIAdapter: adapted ", panels_.size(), " panel(s).");
    }

    return !panels_.is_empty();
}

void UIAdapter::restore_ui() {
    for (int i = 0; i < panels_.size(); i++) {
        AdaptedPanel &panel = panels_.write[i];

        // Reparent Control back to its original CanvasLayer.
        if (panel.original && panel.viewport && panel.source_canvas_layer) {
            panel.viewport->remove_child(panel.original);
            panel.source_canvas_layer->add_child(panel.original);
        }

        // Free viewport and quad.
        if (panel.viewport && panel.viewport->is_inside_tree()) {
            panel.viewport->queue_free();
        }
        if (panel.quad && panel.quad->is_inside_tree()) {
            panel.quad->queue_free();
        }
    }
    panels_.clear();
    emit_signal("ui_restored");
}

void UIAdapter::set_anchor_mode(AnchorMode p_mode) {
    anchor_mode_ = p_mode;
    first_frame_ = true;
}

UIAdapter::AnchorMode UIAdapter::get_anchor_mode() const {
    return anchor_mode_;
}

void UIAdapter::set_camera(XRCamera3D *p_camera) {
    camera_ = p_camera;
}

XRCamera3D *UIAdapter::get_camera() const {
    return camera_;
}

void UIAdapter::set_distance(float p_meters) {
    ui_distance_ = CLAMP(p_meters, 0.3f, 5.0f);
}

float UIAdapter::get_distance() const {
    return ui_distance_;
}

void UIAdapter::set_scale(float p_scale) {
    ui_scale_ = CLAMP(p_scale, 0.1f, 3.0f);
}

float UIAdapter::get_scale() const {
    return ui_scale_;
}

void UIAdapter::set_opacity(float p_opacity) {
    ui_opacity_ = CLAMP(p_opacity, 0.0f, 1.0f);

    // Update existing panel materials.
    for (int i = 0; i < panels_.size(); i++) {
        MeshInstance3D *quad = panels_[i].quad;
        if (!quad) {
            continue;
        }
        Ref<StandardMaterial3D> mat = quad->get_surface_override_material(0);
        if (mat.is_valid()) {
            mat->set_albedo(Color(1.0f, 1.0f, 1.0f, ui_opacity_));
        }
    }
}

float UIAdapter::get_opacity() const {
    return ui_opacity_;
}

void UIAdapter::_process(double p_delta) {
    if (panels_.is_empty() || !camera_) {
        return;
    }

    switch (anchor_mode_) {
        case ANCHOR_HEAD_LOCKED:
            update_head_locked(p_delta);
            break;
        case ANCHOR_WRIST_ATTACHED:
            update_wrist_attached(p_delta);
            break;
        case ANCHOR_WORLD_FIXED:
            // Panels stay where they are.
            break;
    }
}

void UIAdapter::update_head_locked(double p_delta) {
    Transform3D cam_xform = camera_->get_global_transform();
    Vector3 forward = -cam_xform.basis.get_column(2).normalized();
    Vector3 target_pos = cam_xform.origin + forward * ui_distance_;

    Transform3D target;
    target.origin = target_pos;
    target.basis = cam_xform.basis;

    if (first_frame_) {
        smoothed_transform_ = target;
        first_frame_ = false;
    } else {
        float follow_speed = 5.0f;
        float t = CLAMP((float)(follow_speed * p_delta), 0.0f, 1.0f);
        smoothed_transform_.origin = smoothed_transform_.origin.lerp(target.origin, t);
        Quaternion current_q(smoothed_transform_.basis);
        Quaternion target_q(target.basis);
        smoothed_transform_.basis = Basis(current_q.slerp(target_q, t));
    }

    // Arrange panels side by side with small gaps.
    float gap = 0.05f;
    float total_width = 0.0f;
    for (int i = 0; i < panels_.size(); i++) {
        Ref<Mesh> mesh = panels_[i].quad->get_mesh();
        if (mesh.is_valid()) {
            total_width += mesh->get_aabb().get_size().x;
        }
    }
    total_width += gap * (panels_.size() - 1);

    float x_offset = -total_width * 0.5f;
    for (int i = 0; i < panels_.size(); i++) {
        MeshInstance3D *quad = panels_[i].quad;
        Ref<Mesh> mesh = quad->get_mesh();
        float w = mesh.is_valid() ? mesh->get_aabb().get_size().x : 0.5f;
        x_offset += w * 0.5f;

        Transform3D panel_xform = smoothed_transform_;
        panel_xform.origin += smoothed_transform_.basis.get_column(0).normalized() * x_offset;
        quad->set_global_transform(panel_xform);

        x_offset += w * 0.5f + gap;
    }
}

void UIAdapter::update_wrist_attached(double p_delta) {
    // Attach panels to left controller wrist area.
    Node *parent = get_parent();
    if (!parent) {
        return;
    }

    // Try to find an XRController3D in siblings named with "left" or tracker "_left".
    XRController3D *left_ctrl = nullptr;
    for (int i = 0; i < parent->get_child_count(); i++) {
        XRController3D *ctrl = Object::cast_to<XRController3D>(parent->get_child(i));
        if (ctrl && ctrl->get_tracker().to_lower().contains("left")) {
            left_ctrl = ctrl;
            break;
        }
    }

    if (!left_ctrl) {
        // Fallback to head-locked.
        update_head_locked(p_delta);
        return;
    }

    Transform3D wrist = left_ctrl->get_global_transform();
    // Small offset above and slightly in front of the wrist.
    Vector3 offset = wrist.basis.get_column(1).normalized() * 0.08f +
                     wrist.basis.get_column(2).normalized() * -0.05f;

    for (int i = 0; i < panels_.size(); i++) {
        Transform3D panel_xform = wrist;
        panel_xform.origin += offset;
        // Tilt panel to face the user roughly.
        panel_xform.basis = panel_xform.basis.rotated(panel_xform.basis.get_column(0).normalized(), -Math::deg_to_rad(45.0f));
        panels_[i].quad->set_global_transform(panel_xform);
    }
}

void UIAdapter::collect_canvas_layers(Node *p_node, Vector<CanvasLayer *> &r_layers) {
    CanvasLayer *layer = Object::cast_to<CanvasLayer>(p_node);
    if (layer) {
        r_layers.push_back(layer);
    }
    for (int i = 0; i < p_node->get_child_count(); i++) {
        collect_canvas_layers(p_node->get_child(i), r_layers);
    }
}

} // namespace rtv_vr
