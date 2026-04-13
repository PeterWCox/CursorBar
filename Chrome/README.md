# I'd Like To Make

Small MVP for running the local Cursor Agent CLI from a Chrome extension and streaming the response into an in-tab panel.

## What it does

- Clicking the extension action toggles a floating `+` button on the current page.
- Clicking `+` opens an in-tab panel where you can enter:
  - an absolute project path
  - a Cursor model
  - a prompt describing the code change
- The extension sends the request to a local bridge server, which runs `agent` in headless mode and streams JSON events back over SSE.
- The panel shows assistant text, thinking output, and tool activity as the run happens.

## Project layout

```text
bridge/server.js      Local HTTP + SSE bridge to the Cursor Agent CLI
extension/            Chrome extension files (Manifest V3, content script UI)
package.json          Start scripts for the local bridge
```

## Run it

1. Start the local bridge:

   ```bash
   npm start
   ```

2. Open `chrome://extensions`.
3. Turn on **Developer mode**.
4. Click **Load unpacked** and select the `extension/` folder from this project.
5. Open any normal web page.
6. Click the extension icon.
7. Use the injected panel to choose a project path, model, and prompt.

## Notes

- The bridge listens on `http://127.0.0.1:4317`.
- Each prompt is also written into the target workspace's `.metro/tasks.json` so the request appears in Metro-style project metadata.
- Follow-up prompts reuse the last streamed session ID until you click **New chat**.
- This is a local-only MVP, so Chrome talks to a localhost bridge rather than using native messaging.
