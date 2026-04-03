import { sendHelperCommand } from "./_helper.js";

/**
 * Get orientation context: frontmost app, window title, focused element. Helps agents understand the current state before acting.
 * @param {Request} _request - Request object (no parameters needed)
 * @returns Context with app info, window title, and focused element
 */
export default async function main(_request: Request) {
    try {
        const context = await sendHelperCommand("context", {});
        return Response.json(context);
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
