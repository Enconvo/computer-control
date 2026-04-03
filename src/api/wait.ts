import { sendHelperCommand } from "./_helper.js";

/** Wait condition parameters */
interface WaitParams {
    /** Condition to wait for @required */
    condition: "elementExists" | "elementGone" | "titleContains" | "titleChanged" | "delay";
    /** Value to match against (element name, title substring) */
    value?: string;
    /** Target application name */
    appName?: string;
    /** Timeout in seconds @default 30 */
    timeout?: number;
    /** Poll interval in seconds @default 0.5 */
    interval?: number;
}

/**
 * Wait for a condition to be met (element appears/disappears, title changes, or fixed delay). Polls at the specified interval until timeout.
 * @param {Request} request - Request object, body is {@link WaitParams}
 * @returns Whether the condition was met before timeout
 */
export default async function main(request: Request) {
    const params = (await request.json()) as WaitParams;
    const { condition, value, appName, timeout = 30, interval = 0.5 } = params;

    const result = await sendHelperCommand("wait", { condition, value, appName, timeout, interval });
    return Response.json(result);
}
