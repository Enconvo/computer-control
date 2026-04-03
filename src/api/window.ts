import { sendHelperCommand } from "./_helper.js";

/** Window management parameters */
interface WindowParams {
    /** Action to perform @required */
    action: "list" | "minimize" | "maximize" | "restore" | "close" | "move" | "resize" | "fullscreen";
    /** Target application name. If omitted, uses the frontmost app */
    appName?: string;
    /** Window title substring to match. If omitted, targets the first window */
    window?: string;
    /** X position for move action */
    x?: number;
    /** Y position for move action */
    y?: number;
    /** Width for resize action */
    width?: number;
    /** Height for resize action */
    height?: number;
}

/**
 * Manage application windows: list, minimize, maximize, restore, close, move, or resize any window.
 * @param {Request} request - Request object, body is {@link WindowParams}
 * @returns Action result or window list
 */
export default async function main(request: Request) {
    const params = (await request.json()) as WindowParams;
    return Response.json(await sendHelperCommand("window", params));
}
