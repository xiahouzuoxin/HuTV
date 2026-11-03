export type FullscreenMode = 'inline' | 'element' | 'video' | 'viewport';
export type WebkitVideo = HTMLVideoElement & {
  webkitEnterFullscreen?: () => void;
  webkitExitFullscreen?: () => void;
};
// iPhone Safari may only expose fullscreen on the video, not its surrounding controls.
export async function enterFullscreen(
  box: HTMLElement,
  video: WebkitVideo,
): Promise<FullscreenMode> {
  if (box.requestFullscreen) {
    try {
      await box.requestFullscreen({ navigationUI: 'hide' });
      return 'element';
    } catch {
      /* Try the native video API before expanding within the viewport. */
    }
  }
  if (video.webkitEnterFullscreen) {
    try {
      video.webkitEnterFullscreen();
      return 'video';
    } catch {
      /* Unavailable until metadata is loaded, or denied by the browser. */
    }
  }
  return 'viewport';
}
