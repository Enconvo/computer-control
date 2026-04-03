import { executeElementAction, typeText } from "./_helper.js";

/** Type text parameters */
interface TypeParams {
    /** Text to type @required */
    text: string;
    /** Element index to focus before typing. If omitted, types into the currently focused element */
    index?: number;
    /** Delay between keystrokes in milliseconds. 0 for instant. @default 0 */
    delay?: number;
}

/**
 * Type text character by character using keyboard events. Optionally focus an element first by @eN index.
 * @param {Request} request - Request object, body is {@link TypeParams}
 * @returns Type result with success status
 */
export default async function main(request: Request) {
    const params = (await request.json()) as TypeParams;
    const { text, index, delay: delayMs = 0 } = params;

    // Focus element first if index provided
    if (index !== undefined) {
        const focusResult = await executeElementAction(index, "setFocused");
        if (!focusResult.success) {
            // Try clicking to focus instead
            await executeElementAction(index, "click");
        }
    }

    return Response.json(await typeText(text, delayMs));
}
