import Foundation
import notify

/// macOS Game Mode has no public API. gamepolicyd publishes its state as a Darwin notification;
/// checked on macOS 27.0 by forcing Game Mode on with `gamepolicyctl game-mode set on` (state 1) and back (0).
public final class GameMode {
    private static let name = "com.apple.system.game_mode_status_changed"
    private var token: Int32 = NOTIFY_TOKEN_INVALID

    public init(onChange: @escaping (Bool) -> Void) {
        notify_register_dispatch(Self.name, &token, .main) { [weak self] _ in onChange(self?.isOn ?? false) }
    }

    public var isOn: Bool {
        var state: UInt64 = 0
        return notify_is_valid_token(token) && notify_get_state(token, &state) == NOTIFY_STATUS_OK && state != 0
    }

    deinit { if notify_is_valid_token(token) { notify_cancel(token) } }
}
