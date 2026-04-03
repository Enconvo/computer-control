import { EnconvoResponse, ChatMessageContent } from "@enconvo/api";
import { captureScreenshot } from "./_helper.js";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

/** Screenshot parameters */
interface ScreenshotParams {
    /** Image format @default "png" */
    format?: "png" | "jpg";
}

/**
 * Capture a screenshot of the entire screen and return as a displayable image
 * @param {Request} request - Request object, body is {@link ScreenshotParams}
 * @returns Screenshot image displayed in chat
 */
export default async function main(request: Request) {
    const params = (await request.json()) as ScreenshotParams;
    const format = params.format || "png";

    const tmpDir = path.join(os.tmpdir(), "enconvo_screenshots");
    if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
    const filePath = path.join(tmpDir, `screenshot_${Date.now()}.${format}`);

    try {
        await captureScreenshot({ filePath, format });
        return EnconvoResponse.content([ChatMessageContent.imageUrl({ url: filePath })]);
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
