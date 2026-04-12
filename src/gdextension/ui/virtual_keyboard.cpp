#include "virtual_keyboard.h"

#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/viewport_texture.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/classes/v_box_container.hpp>
#include <godot_cpp/classes/h_box_container.hpp>
#include <godot_cpp/classes/panel.hpp>
#include <godot_cpp/classes/style_box_flat.hpp>
#include <godot_cpp/classes/theme.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/callable.hpp>

using namespace godot;

namespace rtv_vr {

VRKeyboard::VRKeyboard() = default;
VRKeyboard::~VRKeyboard() = default;

void VRKeyboard::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize"), &VRKeyboard::initialize);
    ClassDB::bind_method(D_METHOD("show", "position"), &VRKeyboard::show);
    ClassDB::bind_method(D_METHOD("hide"), &VRKeyboard::hide);
    ClassDB::bind_method(D_METHOD("is_visible"), &VRKeyboard::is_visible);
    ClassDB::bind_method(D_METHOD("get_text"), &VRKeyboard::get_text);
    ClassDB::bind_method(D_METHOD("clear"), &VRKeyboard::clear);

    // Internal callback (bound so it can be used as a Callable target).
    ClassDB::bind_method(D_METHOD("_on_key_pressed", "key"), &VRKeyboard::on_key_pressed);

    ADD_SIGNAL(MethodInfo("text_submitted", PropertyInfo(Variant::STRING, "text")));
    ADD_SIGNAL(MethodInfo("text_changed", PropertyInfo(Variant::STRING, "text")));
}

void VRKeyboard::initialize() {
    // --- SubViewport ---
    keyboard_viewport_ = memnew(SubViewport);
    keyboard_viewport_->set_size(Vector2i(800, 300));
    keyboard_viewport_->set_transparent_background(true);
    keyboard_viewport_->set_update_mode(SubViewport::UPDATE_ALWAYS);
    add_child(keyboard_viewport_);

    // Build the keyboard UI inside the viewport.
    build_keyboard_layout();

    // --- 3D quad ---
    Ref<QuadMesh> quad_mesh;
    quad_mesh.instantiate();
    quad_mesh->set_size(Vector2(0.8f, 0.3f));

    Ref<StandardMaterial3D> mat;
    mat.instantiate();
    mat->set_shading_mode(StandardMaterial3D::SHADING_MODE_UNSHADED);
    mat->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA);
    mat->set_albedo(Color(1.0f, 1.0f, 1.0f, 0.95f));
    Ref<ViewportTexture> vp_tex = keyboard_viewport_->get_texture();
    mat->set_texture(StandardMaterial3D::TEXTURE_ALBEDO, Ref<Texture2D>(vp_tex));
    mat->set_cull_mode(StandardMaterial3D::CULL_DISABLED);

    keyboard_quad_ = memnew(MeshInstance3D);
    keyboard_quad_->set_mesh(quad_mesh);
    keyboard_quad_->set_surface_override_material(0, mat);
    add_child(keyboard_quad_);

    // Start hidden.
    set_visible(false);
    is_visible_ = false;

    UtilityFunctions::print("VRKeyboard: initialized.");
}

void VRKeyboard::build_keyboard_layout() {
    // Background panel.
    Panel *bg = memnew(Panel);
    bg->set_anchors_preset(Control::PRESET_FULL_RECT);
    Ref<StyleBoxFlat> bg_style;
    bg_style.instantiate();
    bg_style->set_bg_color(Color(0.12f, 0.12f, 0.15f, 0.92f));
    bg_style->set_corner_radius_all(6);
    bg->add_theme_stylebox_override("panel", bg_style);
    keyboard_viewport_->add_child(bg);

    VBoxContainer *vbox = memnew(VBoxContainer);
    vbox->set_anchors_preset(Control::PRESET_FULL_RECT);
    vbox->set_offset(Side::SIDE_LEFT, 8.0f);
    vbox->set_offset(Side::SIDE_TOP, 8.0f);
    vbox->set_offset(Side::SIDE_RIGHT, -8.0f);
    vbox->set_offset(Side::SIDE_BOTTOM, -8.0f);
    bg->add_child(vbox);

    // Text display at top.
    text_display_ = memnew(Label);
    text_display_->set_text("");
    text_display_->set_custom_minimum_size(Vector2(0, 40));
    text_display_->set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT);
    text_display_->set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER);
    vbox->add_child(text_display_);

    // Keyboard rows.
    const char *rows[] = {
        "1234567890",
        "QWERTYUIOP",
        "ASDFGHJKL",
        "ZXCVBNM",
    };
    const int row_count = 4;

    Vector2 key_size(52, 44);

    for (int r = 0; r < row_count; r++) {
        HBoxContainer *row_container = memnew(HBoxContainer);
        row_container->set_alignment(BoxContainer::ALIGNMENT_CENTER);
        vbox->add_child(row_container);

        const char *row_str = rows[r];
        for (int c = 0; row_str[c] != '\0'; c++) {
            String key_label = String::chr(row_str[c]);
            Button *btn = make_key(key_label, key_size);
            row_container->add_child(btn);
        }
    }

    // Bottom row: Space, Backspace, Enter.
    HBoxContainer *bottom_row = memnew(HBoxContainer);
    bottom_row->set_alignment(BoxContainer::ALIGNMENT_CENTER);
    vbox->add_child(bottom_row);

    Button *space_btn = make_key("Space", Vector2(300, 44));
    bottom_row->add_child(space_btn);

    Button *bksp_btn = make_key("Bksp", Vector2(80, 44));
    bottom_row->add_child(bksp_btn);

    Button *enter_btn = make_key("Enter", Vector2(80, 44));
    bottom_row->add_child(enter_btn);
}

Button *VRKeyboard::make_key(const String &p_label, const Vector2 &p_min_size) {
    Button *btn = memnew(Button);
    btn->set_text(p_label);
    btn->set_custom_minimum_size(p_min_size);
    btn->connect("pressed", Callable(this, "_on_key_pressed").bind(p_label));
    return btn;
}

void VRKeyboard::on_key_pressed(const String &p_key) {
    if (p_key == "Space") {
        current_text_ += " ";
    } else if (p_key == "Bksp") {
        if (current_text_.length() > 0) {
            current_text_ = current_text_.substr(0, current_text_.length() - 1);
        }
    } else if (p_key == "Enter") {
        emit_signal("text_submitted", current_text_);
        return;
    } else {
        current_text_ += p_key;
    }

    if (text_display_) {
        text_display_->set_text(current_text_);
    }
    emit_signal("text_changed", current_text_);
}

void VRKeyboard::show(const Vector3 &p_position) {
    set_global_position(p_position);
    set_visible(true);
    is_visible_ = true;
}

void VRKeyboard::hide() {
    set_visible(false);
    is_visible_ = false;
}

bool VRKeyboard::is_visible() const {
    return is_visible_;
}

String VRKeyboard::get_text() const {
    return current_text_;
}

void VRKeyboard::clear() {
    current_text_ = "";
    if (text_display_) {
        text_display_->set_text("");
    }
}

} // namespace rtv_vr
