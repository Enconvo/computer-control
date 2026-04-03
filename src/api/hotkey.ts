import { sendHelperCommand } from "./_helper.js";

/** Hotkey parameters */
interface HotkeyParams {
    /** Key combination as array, last element is the key, rest are modifiers. E.g. ["cmd", "shift", "p"] for Cmd+Shift+P @required */
    keys: string[];
}

/**
 * Press a key combination like Cmd+L, Cmd+Return, Cmd+Shift+P. Modifiers are held while the final key is pressed.
 * @param {Request} request - Request object, body is {@link HotkeyParams}
 * @returns Hotkey result with key and modifiers
 */
export default async function main(request: Request) {
    const params = (await request.json()) as HotkeyParams;
    return Response.json(await sendHelperCommand("hotkey", params));
}
