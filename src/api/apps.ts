import { listRunningApps } from "./_helper.js";

/**
 * List all running foreground applications with their name, PID, frontmost status, and visibility
 * @param {Request} _request - Request object (no parameters needed)
 * @returns Array of running applications
 */
export default async function main(_request: Request) {
    try {
        const apps = await listRunningApps();
        return Response.json({ success: true, apps });
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
