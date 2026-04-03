import { getCacheInfo, listRunningApps } from "./_helper.js";

/**
 * Get the current status of the computer control module: cached element count, target app, and running apps summary
 * @param {Request} _request - Request object (no parameters needed)
 * @returns Status information
 */
export default async function main(_request: Request) {
    const cacheInfo = getCacheInfo();

    let frontmostApp = "";
    try {
        const apps = await listRunningApps();
        const front = apps.find((a: any) => a.frontmost);
        frontmostApp = front?.name || "";
    } catch {
        // ignore
    }

    return Response.json({
        success: true,
        cachedApp: cacheInfo.app,
        cachedPid: cacheInfo.pid,
        cachedElementCount: cacheInfo.count,
        frontmostApp,
        hint: cacheInfo.count === 0
            ? "No elements cached. Run snapshot first to populate element references."
            : `${cacheInfo.count} elements cached for "${cacheInfo.app}". Use @e0 through @e${cacheInfo.count - 1} for actions.`,
    });
}
