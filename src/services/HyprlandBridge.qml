import QtQuick
import Quickshell.Io
import Quickshell.Hyprland
import "../js/validation.js" as Validation

// The bridge owns all Hyprland process invocations. Every argument is a
// separate Process argument and window addresses are validated before they are
// ever handed to hyprctl; no user-controlled shell string is evaluated.
QtObject {
    id: root

    signal commandFinished(string operation, bool success, int exitCode, string errorText)
    signal commandRejected(string operation, string reason)

    property bool busy: dispatchProcess.running || commandQueue.length > 0
    readonly property bool usingLua: Hyprland.usingLua
    property var commandQueue: []
    property var currentCommand: null
    property string lastErrorText: ""
    property string lastOutputText: ""

    function _address(address) {
        const value = String(address || "");
        if (!Validation.isSafeAddress(value))
            return "";
        return Validation.normalizeAddress(value);
    }

    function _integer(value, fallback = null) {
        const number = Number(value);
        return Number.isFinite(number) ? Math.round(number) : fallback;
    }

    function _coordinate(value) {
        const number = _integer(value);
        if (number === null || number < -10000000 || number > 10000000)
            return null;
        return number;
    }

    function _size(value) {
        const number = _integer(value);
        if (number === null || number < 1 || number > 10000000)
            return null;
        return number;
    }

    function _luaWindowSelector(safe) {
        // _address() only permits a hexadecimal Hyprland address, so this
        // selector is safe to place inside a Lua string literal.
        return "\"address:" + safe + "\"";
    }

    function _legacyBatch(commands) {
        // hyprctl receives one --batch argument. It is not passed through a
        // shell, and every interpolated token is bounded or validated.
        return ["hyprctl", "--batch", commands.join(" ; ")];
    }

    function _luaBatch(commands) {
        // Lua-mode hyprctl dispatch parses hl.dsp expressions, not legacy
        // dispatcher strings. One eval request keeps the move/resize sequence
        // together and still gives Process an exit code and error stream.
        return ["hyprctl", "eval", commands.join("; ")];
    }

    function _enqueue(operation, command) {
        if (!Array.isArray(command) || command.length < 2)
            return false;
        root.commandQueue = root.commandQueue.concat([
            {
                operation: operation,
                command: command
            }
        ]);
        root._pump();
        return true;
    }

    function _pump() {
        if (dispatchProcess.running || root.commandQueue.length === 0)
            return;
        const next = root.commandQueue[0];
        root.commandQueue = root.commandQueue.slice(1);
        root.currentCommand = next;
        root.lastErrorText = "";
        root.lastOutputText = "";
        dispatchProcess.command = next.command;
        dispatchProcess.running = true;
    }

    function place(address, rect, options = ({})) {
        const safe = _address(address);
        if (!safe || !rect) {
            root.commandRejected("place", "Window address or rectangle is invalid");
            return false;
        }
        const x = _coordinate(rect.x);
        const y = _coordinate(rect.y);
        const width = _size(rect.width);
        const height = _size(rect.height);
        const mode = String(options && options.mode || "none");
        if (x === null || y === null || width === null || height === null) {
            root.commandRejected("place", "Window rectangle is invalid");
            return false;
        }
        if (!["none", "floating", "tiled"].includes(mode)) {
            root.commandRejected("place", "Window placement mode is invalid");
            return false;
        }
        if (root.usingLua) {
            const selector = root._luaWindowSelector(safe);
            const commands = [];
            if (mode === "floating")
                commands.push("hl.dispatch(hl.dsp.window.float({ action = \"set\", window = " + selector + " }))");
            commands.push("hl.dispatch(hl.dsp.window.resize({ x = " + String(width) + ", y = " + String(height) + ", \"exact\", window = " + selector + " }))");
            commands.push("hl.dispatch(hl.dsp.window.move({ x = " + String(x) + ", y = " + String(y) + ", \"exact\", window = " + selector + " }))");
            // Keep a tiled placement tiled after pixel operations. Restore of
            // an already tiled window uses retile() below and skips pixels.
            if (mode === "tiled")
                commands.push("hl.dispatch(hl.dsp.window.float({ action = \"unset\", window = " + selector + " }))");
            return _enqueue("place", root._luaBatch(commands));
        }

        const commands = [];
        if (mode === "floating")
            commands.push("dispatch setfloating address:" + safe);
        commands.push("dispatch resizewindowpixel exact " + String(width) + " " + String(height) + ",address:" + safe);
        commands.push("dispatch movewindowpixel exact " + String(x) + " " + String(y) + ",address:" + safe);
        // A tiled placement must finish with settiled; pixel operations run
        // first so we never set tiled and then try to resize it.
        if (mode === "tiled")
            commands.push("dispatch settiled address:" + safe);
        return _enqueue("place", root._legacyBatch(commands));
    }

    function retile(address) {
        const safe = _address(address);
        if (!safe) {
            root.commandRejected("retile", "Window address is invalid");
            return false;
        }
        if (root.usingLua) {
            const selector = root._luaWindowSelector(safe);
            return _enqueue("retile", ["hyprctl", "eval", "hl.dispatch(hl.dsp.window.float({ action = \"unset\", window = " + selector + " }))",]);
        }
        return _enqueue("retile", ["hyprctl", "--batch", "dispatch settiled address:" + safe,]);
    }

    property Process dispatchProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: root.lastOutputText = String(text || "")
        }
        stderr: StdioCollector {
            onStreamFinished: root.lastErrorText = String(text || "")
        }

        onExited: (exitCode, _exitStatus) => {
            const command = root.currentCommand;
            root.currentCommand = null;
            const stderrText = String(root.lastErrorText || "").trim();
            const stdoutText = String(root.lastOutputText || "").trim();
            const reportedError = stderrText || (/^(error|exception|failed)\b/i.test(stdoutText) ? stdoutText : "");
            root.commandFinished(command?.operation || "unknown", exitCode === 0 && !reportedError, exitCode, reportedError);
            Qt.callLater(root._pump);
        }
    }
}
