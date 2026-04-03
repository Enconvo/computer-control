import { sendHelperCommand } from "./_helper.js";

/** Element at point parameters */
interface ElementAtParams {
    /** X coordinate (screen pixels from left) @required */
    x: number;
    /** Y coordinate (screen pixels from top) @required */
    y: number;
}

/**
 * Identify what element is at a specific screen coordinate. Returns full metadata: role, name, value, position, size, actions, and owning app.
 * @param {Request} request - Request object, body is {@link ElementAtParams}
 * @returns Element metadata at the given point
 */
export default async function main(request: Request) {
    const params = (await request.json()) as ElementAtParams;
    return Response.json(await sendHelperCommand("elementAt", params));
}
