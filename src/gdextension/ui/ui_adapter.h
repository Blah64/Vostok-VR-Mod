#ifndef RTV_VR_UI_ADAPTER_H
#define RTV_VR_UI_ADAPTER_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/xr_camera3d.hpp>
#include <godot_cpp/classes/canvas_layer.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/templates/vector.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace rtv_vr {

class UIAdapter : public godot::Node3D {
    GDCLASS(UIAdapter, godot::Node3D)

public:
    enum AnchorMode {
        ANCHOR_HEAD_LOCKED,
        ANCHOR_WRIST_ATTACHED,
        ANCHOR_WORLD_FIXED,
    };

    struct AdaptedPanel {
        godot::Control *original = nullptr;
        godot::SubViewport *viewport = nullptr;
        godot::MeshInstance3D *quad = nullptr;
        godot::CanvasLayer *source_canvas_layer = nullptr;
        godot::Vector2 original_size;
    };

    UIAdapter();
    ~UIAdapter() override;

    // Core adaptation
    bool adapt_ui(godot::Node *p_scene_root);
    void restore_ui();

    // Setters
    void set_anchor_mode(AnchorMode p_mode);
    AnchorMode get_anchor_mode() const;

    void set_camera(godot::XRCamera3D *p_camera);
    godot::XRCamera3D *get_camera() const;

    void set_distance(float p_meters);
    float get_distance() const;

    void set_scale(float p_scale);
    float get_scale() const;

    void set_opacity(float p_opacity);
    float get_opacity() const;

    // Godot lifecycle
    void _process(double p_delta) override;

protected:
    static void _bind_methods();

private:
    void update_head_locked(double p_delta);
    void update_wrist_attached(double p_delta);
    void collect_canvas_layers(godot::Node *p_node, godot::Vector<godot::CanvasLayer *> &r_layers);

    godot::Vector<AdaptedPanel> panels_;
    AnchorMode anchor_mode_ = ANCHOR_HEAD_LOCKED;
    float ui_distance_ = 1.5f;
    float ui_scale_ = 1.0f;
    float ui_opacity_ = 0.95f;
    godot::XRCamera3D *camera_ = nullptr;
    godot::Transform3D smoothed_transform_;
    bool first_frame_ = true;
};

} // namespace rtv_vr

VARIANT_ENUM_CAST(rtv_vr::UIAdapter::AnchorMode)

#endif // RTV_VR_UI_ADAPTER_H
