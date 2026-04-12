#ifndef RTV_VR_COMFORT_OPTIONS_H
#define RTV_VR_COMFORT_OPTIONS_H

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/xr_origin3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>

namespace rtv_vr {

class ComfortOptions : public godot::Node3D {
    GDCLASS(ComfortOptions, godot::Node3D)

public:
    enum TurnType {
        TURN_SNAP = 0,
        TURN_SMOOTH = 1,
    };

    ComfortOptions();
    ~ComfortOptions();

    void initialize(godot::XROrigin3D *origin);

    void process_turn(double delta, float input_x, godot::XROrigin3D *origin);
    void update_vignette(double delta, bool is_moving);

    // Turn settings
    void set_turn_type(TurnType type);
    TurnType get_turn_type() const;

    void set_snap_angle(float degrees);
    float get_snap_angle() const;

    void set_smooth_speed(float degrees_per_second);
    float get_smooth_speed() const;

    // Vignette settings
    void set_vignette_enabled(bool enabled);
    bool get_vignette_enabled() const;

    void set_vignette_intensity(float intensity);
    float get_vignette_intensity() const;

protected:
    static void _bind_methods();

private:
    void create_vignette_mesh(godot::XROrigin3D *origin);
    void update_vignette_material(float alpha);

    // Turn state
    TurnType turn_type_ = TURN_SNAP;
    float snap_angle_ = 45.0f;
    float smooth_speed_ = 120.0f;
    bool snap_triggered_ = false; // debounce flag for snap turn
    static constexpr float SNAP_DEADZONE = 0.6f;

    // Vignette state
    bool vignette_enabled_ = true;
    float vignette_intensity_ = 0.6f;
    float current_vignette_ = 0.0f;
    static constexpr float VIGNETTE_FADE_IN_SPEED = 8.0f;
    static constexpr float VIGNETTE_FADE_OUT_SPEED = 4.0f;

    godot::MeshInstance3D *vignette_mesh_ = nullptr;
    godot::Ref<godot::ShaderMaterial> vignette_material_;
    bool initialized_ = false;
};

} // namespace rtv_vr

VARIANT_ENUM_CAST(rtv_vr::ComfortOptions::TurnType)

#endif // RTV_VR_COMFORT_OPTIONS_H
