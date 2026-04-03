import { sendHelperCommand } from "./_helper.js";

/** Batch action definition */
interface BatchAction {
    /** Action name: "click", "type", "fill", "press", "scroll", "mouse", "open_app", "snapshot", "wait" @required */
    action: string;
    /** Action parameters @required */
    params: Record<string, any>;
}

/** Batch parameters */
interface BatchParams {
    /** Array of actions to execute sequentially @required */
    actions: BatchAction[];
    /** Stop execution on first failure @default false */
    stopOnError?: boolean;
}

/**
 * Execute multiple computer control actions in sequence within a single request. Reduces round-trip latency for multi-step workflows.
 * @param {Request} request - Request object, body is {@link BatchParams}
 * @returns Array of results for each action
 */
export default async function main(request: Request) {
    const { actions, stopOnError = false } = (await request.json()) as BatchParams;
    const results: Array<{ action: string; result: any }> = [];

    // Map endpoint action names to Swift helper methods
    const methodMap: Record<string, string> = {
        click: "click", fill: "setValue", type: "type",
        press: "press", scroll: "scroll", mouse: "mouse",
        open_app: "openApp", snapshot: "snapshot", focus: "focus",
    };

    for (const item of actions) {
        let result: any;
        try {
            if (item.action === "wait") {
                const ms = item.params.ms || 1000;
                await new Promise<void>(resolve => setTimeout(resolve, ms));
                result = { success: true, waited: ms };
            } else {
                const method = methodMap[item.action] || item.action;
                result = await sendHelperCommand(method, item.params);
            }
        } catch (e: any) {
            result = { success: false, error: e.message };
        }

        results.push({ action: item.action, result });
        if (stopOnError && result && !result.success) {
            return Response.json({
                success: false, results,
                error: `Action '${item.action}' failed: ${result.error}`,
            });
        }
    }

    return Response.json({ success: true, results });
}
