import { EnconvoResponse, ChatMessageContent } from "@enconvo/api";
import { sendHelperCommand } from "./_helper.js";

/** Annotated screenshot parameters */
interface AnnotatedScreenshotParams {
    /** Target application name. If omitted, uses the frontmost application */
    appName?: string;
    /** Maximum number of element labels @default 50 */
    maxLabels?: number;
}

/**
 * Capture a screenshot with numbered Set-of-Marks labels drawn on interactive elements (zero ML, instant). Returns the annotated image and a text index with click coordinates.
 * @param {Request} request - Request object, body is {@link AnnotatedScreenshotParams}
 * @returns Annotated screenshot image with numbered labels and text index
 */
export default async function main(request: Request) {
    const params = (await request.json()) as AnnotatedScreenshotParams;

    try {
        const result = await sendHelperCommand("annotate", {
            appName: params.appName,
            maxLabels: params.maxLabels,
        });

        if (result.success && result.filePath) {
            return EnconvoResponse.content([
                ChatMessageContent.imageUrl({ url: result.filePath }),
                ChatMessageContent.text({ text: result.index || "" }),
            ]);
        }

        return Response.json(result);
    } catch (e: any) {
        return Response.json({ success: false, error: e.message });
    }
}
