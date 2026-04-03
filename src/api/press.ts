import { pressKey } from "./_helper.js";

/** Keyboard shortcut parameters */
interface PressParams {
    /** Key to press. Single character ("a", "1") or named key ("return", "escape", "tab", "space", "delete", "up", "down", "left", "right", "f1"-"f12", "home", "end", "pageup", "pagedown") @required */
    key: string;
    /** Modifier keys to hold. Array of: "command"/"cmd", "shift", "option"/"alt", "control"/"ctrl" */
    modifiers?: string[];
}

/**
 * Press a keyboard key or shortcut (e.g. Cmd+C, Enter, Escape). Works globally — sends to the frontmost application.
 * @param {Request} request - Request object, body is {@link PressParams}
 * @returns Press result with success status, key, and modifiers
 */
export default async function main(request: Request) {
    const params = (await request.json()) as PressParams;
    const { key, modifiers = [] } = params;

    try {
        const result = await pressKey(key, modifiers);
        return Response.json({ success: true, ...result });
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
