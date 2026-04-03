import { openApp } from "./_helper.js";

/** Open app parameters */
interface OpenAppParams {
    /** Application name to open (e.g. "Finder", "Safari", "System Settings") @required */
    appName: string;
}

/**
 * Open (activate) a macOS application by name. If already running, brings it to the foreground.
 * @param {Request} request - Request object, body is {@link OpenAppParams}
 * @returns Result with success status
 */
export default async function main(request: Request) {
    const params = (await request.json()) as OpenAppParams;
    return Response.json(await openApp(params.appName));
}
