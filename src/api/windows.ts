import { listWindows } from "./_helper.js";

/** Window list parameters */
interface WindowsParams {
    /** Application name. If omitted, lists windows of the frontmost app */
    appName?: string;
}

/**
 * List all windows of an application with their index, title, position, size, and minimized status
 * @param {Request} request - Request object, body is {@link WindowsParams}
 * @returns Array of windows
 */
export default async function main(request: Request) {
    const params = (await request.json()) as WindowsParams;
    try {
        const windows = await listWindows(params.appName);
        return Response.json({ success: true, windows });
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
