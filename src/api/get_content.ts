import { buildSnapshotAndCache as buildSnapshot } from "./_helper.js";

/** Get content parameters */
interface GetContentParams {
    /** Target application name. If omitted, uses the frontmost application */
    appName?: string;
    /** Include the full accessibility tree @default true */
    includeTree?: boolean;
}

/**
 * Get the text content of the current window from the frontmost (or specified) application. Returns app name, window title, and all visible text.
 * @param {Request} request - Request object, body is {@link GetContentParams}
 * @returns Window content with app info and extracted text
 */
export default async function main(request: Request) {
    const params = (await request.json()) as GetContentParams;
    const includeTree = params.includeTree ?? true;

    try {
        const snapshot = await buildSnapshot({
            appName: params.appName,
            interactiveOnly: false,
            maxDepth: 10,
        });

        return Response.json({
            success: true,
            app: snapshot.app,
            pid: snapshot.pid,
            windowTitle: snapshot.windowTitle,
            tree: includeTree ? snapshot.tree : undefined,
            interactiveCount: snapshot.interactiveCount,
        });
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
