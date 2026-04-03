import { execFile } from "child_process";

/** Run script parameters */
interface RunScriptParams {
    /** The script to execute @required */
    script: string;
    /** Script language @default "applescript" */
    language?: "applescript" | "jxa";
    /** Execution timeout in milliseconds @default 30000 */
    timeout?: number;
}

function runScript(script: string, language: string, timeout: number): Promise<string> {
    const args = language === "jxa" ? ["-l", "JavaScript", "-e", script] : ["-e", script];
    return new Promise((resolve, reject) => {
        execFile("/usr/bin/osascript", args, { timeout, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
            if (err) reject(new Error(stderr?.trim() || err.message));
            else resolve(stdout.trim());
        });
    });
}

/**
 * Execute an AppleScript or JXA (JavaScript for Automation) script and return the result
 * @param {Request} request - Request object, body is {@link RunScriptParams}
 * @returns Script execution result
 */
export default async function main(request: Request) {
    const params = (await request.json()) as RunScriptParams;
    const { script, language = "applescript", timeout = 30000 } = params;

    try {
        const result = await runScript(script, language, timeout);
        try {
            return Response.json({ success: true, result: JSON.parse(result) });
        } catch {
            return Response.json({ success: true, result });
        }
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
