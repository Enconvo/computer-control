import { Commander } from "@enconvo/api";

/** Record audio parameters */
interface RecordAudioParams {
    /** Action to perform on the audio recording session @required */
    action: "start" | "pause" | "resume" | "stop" | "cancel" | "status";
    /** Output file path without extension. Only used by "start". Defaults to ~/Documents/.enconvo/MeetingRecordings/Recording-<timestamp> */
    outputPath?: string;
    /** Bundle IDs of apps to include in system audio capture. Empty array records all running apps. Only used by "start" and only when recordSystemAudio is true. */
    includingApplications?: string[];
    /** Capture the microphone. Only used by "start". @default true */
    recordMicrophone?: boolean;
    /** Capture system audio via ScreenCaptureKit. Only used by "start". @default true */
    recordSystemAudio?: boolean;
    /** When true, "start" blocks until the user clicks stop/cancel in the audio bar UI (or another caller issues stop/cancel), then returns the final result. Set to false to return immediately after recording begins. Only used by "start". @default true */
    waitForCompletion?: boolean;
}

/** Response returned by the native audio recorder. Shape depends on action. */
interface RecordAudioResponse {
    data: {
        success?: boolean;
        error?: string;
        isRecording?: boolean;
        isPaused?: boolean;
        duration?: number;
        /** WAV file path. Populated on stop when recording succeeded. */
        path?: string;
        /** True when the recording ended via cancel. Only set when "start" was called with waitForCompletion=true. */
        cancelled?: boolean;
    };
}

/**
 * Record system audio + microphone to a WAV file.
 *
 * Flow: call with `action: "start"` to begin, then optionally `pause` / `resume`,
 * and finally `stop` to receive the WAV file path. Use `cancel` to discard,
 * or `status` to query the current session.
 *
 * @param {Request} request - Request object, body is {@link RecordAudioParams}
 * @returns {@link RecordAudioResponse}
 */
export default async function main(request: Request) {
    const params = (await request.json()) as RecordAudioParams;
    console.log('record audio ', params.action)

    const payload: Record<string, any> = { action: params.action };
    if (params.outputPath !== undefined) payload.outputPath = params.outputPath;
    if (params.includingApplications !== undefined) {
        payload.includingApplications = params.includingApplications;
    }
    if (params.recordMicrophone !== undefined) {
        payload.recordMicrophone = params.recordMicrophone;
    }
    if (params.recordSystemAudio !== undefined) {
        payload.recordSystemAudio = params.recordSystemAudio;
    }
    if (params.waitForCompletion !== undefined) {
        payload.waitForCompletion = params.waitForCompletion;
    }

    const result = (await Commander.send("recordAudio", payload)) as RecordAudioResponse;
    return Response.json(result.data ?? {});
}
