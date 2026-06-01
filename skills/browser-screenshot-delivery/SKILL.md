---
name: browser-screenshot-delivery
description: Capture browser-visible pages, QR codes, receipts, checkout pages, confirmations, error states, dashboards, or any remote UI that the user needs returned as an image file. Use when the user asks to screenshot, send the image/file, remote-transfer a browser view, return a QR code, show what the browser displays, 截图, 发图片, 传文件, 远程传输文件, or otherwise needs a browser result delivered back into chat.
---

# Browser Screenshot Delivery

## Goal

Return the exact browser-visible UI as a user-accessible image file. Always save the image into the current workspace `outputs` directory and include a Markdown image plus a file link in the response.

This skill is about delivery reliability: tool-emitted screenshots are useful for inspection, but the user may not receive them as files. A delivered screenshot must exist on disk under `outputs/`.

## Preferred Browser Path

Use the Chrome skill for profile-dependent or already-open browser pages:

1. Connect to the extension browser.
2. Name the session.
3. List open tabs with `browser.user.openTabs()`.
4. Claim the exact tab with `browser.user.claimTab(tabInfo)`.
5. Wait briefly for the page state to settle.
6. Use `tab.screenshot({ clip, fullPage: false })` for the visible viewport or `tab.screenshot({ fullPage: true })` only for ordinary pages where full-page capture is safe.

Do not guess tab ids. Do not reopen a dynamic payment URL just to screenshot it; claim the current live tab whenever possible.

## Region Capture

For QR codes, receipts, payment confirmations, modal dialogs, and compact UI states, crop the relevant visible region. Locate the region with DOM bounding boxes:

```js
const targets = await tab.playwright.evaluate(() => {
  return Array.from(document.querySelectorAll("canvas,img,[role='dialog'],.modal"))
    .map((el, i) => {
      const r = el.getBoundingClientRect();
      return {
        i,
        tag: el.tagName,
        text: (el.innerText || el.alt || "").slice(0, 120),
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
      };
    })
    .filter((r) => r.width > 0 && r.height > 0);
}, undefined, { timeoutMs: 10000 });
```

Then capture a padded clip:

```js
const target = targets.find((r) => r.width >= 120 && r.height >= 120);
const clip = {
  x: Math.max(0, Math.floor(target.x - 50)),
  y: Math.max(0, Math.floor(target.y - 60)),
  width: Math.ceil(target.width + 120),
  height: Math.ceil(target.height + 120),
};
const png = await tab.screenshot({ clip, fullPage: false });
```

For canvas-rendered QR codes, screenshot pixels. Do not depend on `canvas.toDataURL()`: some browser wrappers expose a read-only object without canvas methods.

## Save And Deliver

Use this Node pattern after capturing bytes:

```js
const { mkdir, writeFile, stat } = await import("node:fs/promises");
const { join } = await import("node:path");
const outDir = join(nodeRepl.cwd, "outputs");
await mkdir(outDir, { recursive: true });
const filePath = join(outDir, `browser-capture-${Date.now()}.png`);
await writeFile(filePath, Buffer.from(png));
nodeRepl.write(JSON.stringify({ filePath, bytes: (await stat(filePath)).size }));
```

Before answering, verify the saved file when possible:

```powershell
Get-Item "C:\absolute\path\to\outputs\browser-capture.png" | Select-Object FullName,Length
```

Use `view_image` for visual QA if available. The final response must include the absolute output path:

```markdown
![Screenshot](C:\absolute\path\to\outputs\browser-capture.png)

File: [browser-capture.png](C:\absolute\path\to\outputs\browser-capture.png)
```

## If Screenshot Fails

- Retry once with a smaller `clip` and `fullPage: false`.
- Make sure the target is in the viewport; scroll or use the visible part of the page instead of refreshing dynamic pages.
- Reclaim the live tab if the handle went stale.
- For dynamic payment pages, avoid reload unless the user says the code expired, because reload can rotate or invalidate the code.
- If browser screenshot remains unavailable, use a system-level screenshot only when the target browser window is visibly foregrounded and doing so does not conflict with the active automation policy. Save the result to `outputs/`, crop if needed, and visually verify it before delivery.

## Closeout

After browser work, call `browser.tabs.finalize({ keep })`. Keep a tab only when the user needs a live handoff page, such as a QR page waiting for payment, a confirmation page, or an unfinished workflow.
