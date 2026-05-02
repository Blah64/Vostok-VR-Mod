extends RefCounted

# grenade.gd
# Slot-4 pin/throw flow. The game uses two separate mouse clicks for
# grenades; the mod maps trigger=pull pin / right-grip release=throw and
# auto-holsters after the throw.

var autoload: Node

# Subsystem-owned state. The autoload no longer holds _grenade_pin_pulled;
# call sites read/write via pin_pulled here (or autoload.is_grenade_pin_pulled()
# / autoload.set_grenade_pin_pulled() while the legacy getter shims still exist).
var pin_pulled: bool = false


func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(_frame: Dictionary, _delta: float) -> void:
	# Repeating buzz while the grenade pin is pulled, until grip release
	# triggers grenade_throw_tap(). Reads weapon_hand from the snapshot.
	if not pin_pulled:
		return
	var hand: String = autoload._get_weapon_hand()
	var ctrl: XRController3D = autoload._get_controller(hand)
	if ctrl and ctrl.get_is_active():
		ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)


func grenade_auto_holster() -> void:
	if autoload._holster_state == autoload.HolsterState.DRAWN and autoload._weapon_slot == 4:
		autoload._holster_weapon()


func clear_grenade_state() -> void:
	if pin_pulled:
		Input.action_release("fire")
		Input.action_release("left_mouse")
		autoload._inject_action("fire", false)
		autoload._inject_action("left_mouse", false)
		autoload._inject_mouse_button(MOUSE_BUTTON_LEFT, false)
	pin_pulled = false


func grenade_tap_release() -> void:
	autoload._inject_mouse_button(MOUSE_BUTTON_LEFT, false)
	autoload._inject_action("fire", false)
	autoload._inject_action("left_mouse", false)
	Input.action_release("fire")
	Input.action_release("left_mouse")


func grenade_replace_pin() -> void:
	pin_pulled = false
	autoload._inject_mouse_button(MOUSE_BUTTON_RIGHT, true)
	autoload.get_tree().create_timer(autoload.GRENADE_TAP_SEC).timeout.connect(Callable(self, "grenade_replace_pin_release"))


func grenade_replace_pin_release() -> void:
	autoload._inject_mouse_button(MOUSE_BUTTON_RIGHT, false)


func grenade_throw_tap() -> void:
	pin_pulled = false
	autoload._inject_mouse_button(MOUSE_BUTTON_LEFT, true)
	autoload._inject_action("fire", true)
	autoload._inject_action("left_mouse", true)
	Input.action_press("fire", 1.0)
	Input.action_press("left_mouse", 1.0)
	autoload.get_tree().create_timer(autoload.GRENADE_TAP_SEC).timeout.connect(Callable(self, "grenade_tap_release"))
	autoload.get_tree().create_timer(autoload.GRENADE_AUTO_HOLSTER_SEC).timeout.connect(Callable(self, "grenade_auto_holster"))
