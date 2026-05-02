extends RefCounted

# grenade.gd
#
# Slot-4 pin/throw flow. The game uses two separate mouse clicks for
# grenades: click 1 = pull pin, click 2 = throw. The mod maps this to a
# VR-friendly sequence:
#
#   Trigger (pin not pulled) -> pull pin (left mouse tap), haptic buzz
#   Trigger (pin pulled)     -> replace pin (right mouse tap)
#   Grip release (pin pulled) -> throw (left mouse tap), auto-holster 0.5s later
#
# This subsystem owns its state (pin_pulled) and reaches the rest of the
# system only through the explicit Callable ports passed at _init time. There
# is no `autoload: Node` back-reference — that's the proven-out template the
# rest of Phase 4 should adopt next.
#
# Port contract:
#   tree                    : SceneTree         (used to schedule timer-based mouse releases)
#   inject_action           : Callable(name, pressed, strength)  -> void
#   inject_mouse            : Callable(button, pressed)          -> void
#   get_weapon_controller   : Callable() -> XRController3D       (current weapon-hand controller; may be null)
#   is_drawn_grenade        : Callable() -> bool                 (true iff state == DRAWN AND slot == 4)
#   request_holster         : Callable() -> void                 (asks the holster system to holster the current weapon)
#   log                     : Callable(msg) -> void              (optional; ignored if invalid)


const GRENADE_TAP_SEC = 0.080
const GRENADE_AUTO_HOLSTER_SEC = 0.5


var pin_pulled: bool = false


# Ports
var _tree: SceneTree
var _inject_action: Callable
var _inject_mouse: Callable
var _get_weapon_controller: Callable
var _is_drawn_grenade: Callable
var _request_holster: Callable
var _log_fn: Callable


func _init(tree: SceneTree, ports: Dictionary) -> void:
	_tree = tree
	_inject_action = ports["inject_action"]
	_inject_mouse = ports["inject_mouse"]
	_get_weapon_controller = ports["get_weapon_controller"]
	_is_drawn_grenade = ports["is_drawn_grenade"]
	_request_holster = ports["request_holster"]
	_log_fn = ports.get("log", Callable())


func _log(msg: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(msg)


# Per-frame work — repeating buzz while the pin is pulled until grip release.
func process(_frame: Dictionary, _delta: float) -> void:
	if not pin_pulled:
		return
	var ctrl = _get_weapon_controller.call()
	if ctrl and ctrl.get_is_active():
		ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)


# Trigger pressed while DRAWN + slot 4 + no pin pulled -> tap fire (left mouse).
# Schedules the release tap via _tree so the game sees a clean click.
func pull_pin() -> void:
	if pin_pulled:
		return
	_inject_mouse.call(MOUSE_BUTTON_LEFT, true)
	_inject_action.call("fire", true, 1.0)
	_inject_action.call("left_mouse", true, 1.0)
	Input.action_press("fire", 1.0)
	Input.action_press("left_mouse", 1.0)
	_tree.create_timer(GRENADE_TAP_SEC).timeout.connect(Callable(self, "tap_release"))
	pin_pulled = true
	var ctrl = _get_weapon_controller.call()
	if ctrl:
		ctrl.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.1, 0.0)
	_log("[VR Mod] Grenade pin pulled")


# Trigger pressed again with pin already pulled -> right mouse tap (cancel).
func replace_pin() -> void:
	pin_pulled = false
	_inject_mouse.call(MOUSE_BUTTON_RIGHT, true)
	_tree.create_timer(GRENADE_TAP_SEC).timeout.connect(Callable(self, "replace_pin_release"))


func replace_pin_release() -> void:
	_inject_mouse.call(MOUSE_BUTTON_RIGHT, false)


# Grip release with pin pulled -> tap left mouse (throw) + schedule auto-holster.
func throw_tap() -> void:
	pin_pulled = false
	_inject_mouse.call(MOUSE_BUTTON_LEFT, true)
	_inject_action.call("fire", true, 1.0)
	_inject_action.call("left_mouse", true, 1.0)
	Input.action_press("fire", 1.0)
	Input.action_press("left_mouse", 1.0)
	_tree.create_timer(GRENADE_TAP_SEC).timeout.connect(Callable(self, "tap_release"))
	_tree.create_timer(GRENADE_AUTO_HOLSTER_SEC).timeout.connect(Callable(self, "auto_holster"))


# Timer callback: release the left-mouse press scheduled by pull_pin or throw_tap.
func tap_release() -> void:
	_inject_mouse.call(MOUSE_BUTTON_LEFT, false)
	_inject_action.call("fire", false, 1.0)
	_inject_action.call("left_mouse", false, 1.0)
	Input.action_release("fire")
	Input.action_release("left_mouse")


# Timer callback (0.5s after throw_tap): holster slot 4 if still DRAWN.
func auto_holster() -> void:
	if _is_drawn_grenade.call():
		_request_holster.call()


# Called from holster transitions / level transitions / draw paths to make
# sure no stale "fire" press leaks across weapon swap. Safe to call when
# pin_pulled is false (no-op).
func clear_state() -> void:
	if pin_pulled:
		Input.action_release("fire")
		Input.action_release("left_mouse")
		_inject_action.call("fire", false, 1.0)
		_inject_action.call("left_mouse", false, 1.0)
		_inject_mouse.call(MOUSE_BUTTON_LEFT, false)
	pin_pulled = false
