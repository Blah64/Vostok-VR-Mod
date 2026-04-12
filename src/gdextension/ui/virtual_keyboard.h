#ifndef RTV_VR_VIRTUAL_KEYBOARD_H
#define RTV_VR_VIRTUAL_KEYBOARD_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/sub_viewport.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/grid_container.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace rtv_vr {

class VRKeyboard : public godot::Node3D {
    GDCLASS(VRKeyboard, godot::Node3D)

public:
    VRKeyboard();
    ~VRKeyboard() override;

    void initialize();

    void show(const godot::Vector3 &p_position);
    void hide();
    bool is_visible() const;

    godot::String get_text() const;
    void clear();

protected:
    static void _bind_methods();

private:
    void on_key_pressed(const godot::String &p_key);
    void build_keyboard_layout();
    godot::Button *make_key(const godot::String &p_label, const godot::Vector2 &p_min_size);

    godot::SubViewport *keyboard_viewport_ = nullptr;
    godot::MeshInstance3D *keyboard_quad_ = nullptr;
    godot::Label *text_display_ = nullptr;
    bool is_visible_ = false;
    godot::String current_text_;
};

} // namespace rtv_vr

#endif // RTV_VR_VIRTUAL_KEYBOARD_H
