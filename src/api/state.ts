import { sendHelperCommand } from "./_helper.js";

/**
 * List every running app with its windows, positions, and sizes. Provides a unified view of the entire desktop state.
 * @param {Request} _request - Request object (no parameters needed)
 * @returns All running apps with their windows
 */
export default async function main(_request: Request) {
    return Response.json(await sendHelperCommand("state", {}));
}
