#!/usr/bin/env python3
"""Record a tight-paced Blushcraft round demo (MP4 + GIF) for the README.

Prereqs:
  1. Serve the app on :7357, e.g.
       flutter build web --debug
       python3 -m http.server 7357 --directory build/web
  2. Playwright Chromium available (tool uses /tmp/blush_capture_venv if present).

Usage (from repo root):
  python3 tool/record_round_demo.py
  ./tool/extract_store_screenshots.sh
"""

from __future__ import annotations

import asyncio
import subprocess
import sys
from pathlib import Path

from playwright.async_api import Page, async_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "screenshots"
URL = "http://127.0.0.1:7357/?demo=tight"
PHONE = {"width": 390, "height": 844}

BEAT = 0.22
SETTLE = 0.38
SWIPE_STEP_MS = 14


async def enable_semantics(page: Page) -> None:
    await page.wait_for_timeout(1100)
    await page.evaluate(
        "() => document.querySelector('flt-semantics-placeholder')?.click()"
    )
    await page.wait_for_timeout(300)


async def list_labels(page: Page) -> list[str]:
    return await page.evaluate(
        """() => [...document.querySelectorAll('flt-semantics,[role=button]')]
          .map(n => (n.getAttribute('aria-label') || n.innerText || '').trim())
          .filter(t => t && !t.includes('\\n'))"""
    )


async def wait_label(page: Page, needle: str, timeout_ms: int = 7000) -> bool:
    deadline = asyncio.get_event_loop().time() + timeout_ms / 1000
    while asyncio.get_event_loop().time() < deadline:
        labels = await list_labels(page)
        if any(needle == L or needle in L for L in labels):
            return True
        await page.wait_for_timeout(100)
    return False


async def tap(page: Page, label: str) -> bool:
    try:
        btn = page.get_by_role("button", name=label, exact=True)
        if await btn.count():
            await btn.first.click(timeout=2000, force=True)
            await page.wait_for_timeout(int(BEAT * 1000))
            return True
    except Exception:
        pass

    ok = await page.evaluate(
        """(label) => {
      const nodes = [...document.querySelectorAll('flt-semantics,[role=button]')];
      let el = nodes.find((n) => {
        const a = (n.getAttribute('aria-label') || '').trim();
        const t = (n.innerText || '').trim();
        return a === label || t === label;
      });
      if (!el) {
        el = nodes.find((n) => {
          const a = (n.getAttribute('aria-label') || '').trim();
          const t = (n.innerText || '').trim();
          return a.includes(label) || t.includes(label);
        });
      }
      if (!el) return false;
      const r = el.getBoundingClientRect();
      const x = (r.width > 1 ? r.left + r.width / 2 : 195);
      const y = (r.height > 1 ? r.top + r.height / 2 : 650);
      const view = document.querySelector('flutter-view')
        || document.querySelector('flt-glass-pane');
      const target = view || el;
      for (const type of ['pointerdown', 'pointerup', 'click']) {
        target.dispatchEvent(new PointerEvent(type, {
          bubbles: true, cancelable: true, clientX: x, clientY: y,
          pointerType: 'mouse', buttons: type.includes('down') ? 1 : 0,
        }));
      }
      return true;
    }""",
        label,
    )
    await page.wait_for_timeout(int(BEAT * 1000))
    return bool(ok)


async def choice_labels(page: Page) -> list[str]:
    labels = await list_labels(page)
    return [L for L in labels if L.startswith("CHOICE")]


async def swipe_hand(page: Page, dx: float = -240) -> None:
    box = page.viewport_size or PHONE
    y = box["height"] - 135
    x0 = box["width"] * 0.82
    x1 = max(40, x0 + dx)
    await page.mouse.move(x0, y)
    await page.mouse.down()
    steps = 10
    for i in range(1, steps + 1):
        await page.mouse.move(x0 + (x1 - x0) * (i / steps), y)
        await page.wait_for_timeout(SWIPE_STEP_MS)
    await page.mouse.up()
    await page.wait_for_timeout(int(BEAT * 1000))


async def pick_and_submit(page: Page, index: int = 0) -> None:
    choices = await choice_labels(page)
    if not choices:
        raise RuntimeError(f"no CHOICE labels: {await list_labels(page)}")
    label = choices[min(index, len(choices) - 1)]
    assert await tap(page, label), f"failed tapping {label}"
    await page.wait_for_timeout(120)
    assert await tap(page, "Submit face-down"), "submit failed"


def ffmpeg_mp4(webm: Path, mp4: Path) -> None:
    r = subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-ss",
            "1.8",
            "-i",
            str(webm),
            "-vf",
            "fps=30,format=yuv420p",
            "-c:v",
            "libx264",
            "-preset",
            "fast",
            "-crf",
            "23",
            "-movflags",
            "+faststart",
            "-an",
            str(mp4),
        ],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        print(r.stderr[-800:], file=sys.stderr)
        raise SystemExit(r.returncode)


def ffmpeg_gif(mp4: Path, gif: Path) -> None:
    r = subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(mp4),
            "-vf",
            "fps=12,scale=390:-1:flags=lanczos",
            "-loop",
            "0",
            "-gifflags",
            "+transdiff",
            str(gif),
        ],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        print(r.stderr[-800:], file=sys.stderr)
        raise SystemExit(r.returncode)


async def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    video_dir = OUT / "_video_tmp"
    video_dir.mkdir(exist_ok=True)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            viewport=PHONE,
            device_scale_factor=2,
            record_video_dir=str(video_dir),
            record_video_size=PHONE,
        )
        page = await context.new_page()
        await page.goto(URL, wait_until="networkidle")
        await enable_semantics(page)
        await page.wait_for_timeout(int(SETTLE * 1000))

        # Linger on home so game-mode chips are visible in the demo.
        await page.wait_for_timeout(700)
        await tap(page, "Fresh Start")
        await page.wait_for_timeout(450)
        await tap(page, "Romantic Partner")
        await page.wait_for_timeout(350)

        assert await tap(page, "Practice on this device")
        assert await wait_label(page, "Start game")
        await page.wait_for_timeout(int(SETTLE * 1000))

        assert await tap(page, "Start game")
        assert await wait_label(page, "Submit face-down")
        await page.wait_for_timeout(int(SETTLE * 1000))

        await swipe_hand(page, dx=-220)
        await swipe_hand(page, dx=-160)
        await pick_and_submit(page, index=1)
        assert await wait_label(page, "Pick a card for Partner")
        await page.wait_for_timeout(int(SETTLE * 1000))

        await swipe_hand(page, dx=-120)
        await pick_and_submit(page, index=0)
        assert await wait_label(page, "Reaction check"), await list_labels(page)
        await page.wait_for_timeout(int(SETTLE * 1000))

        assert await tap(page, "Reaction check")
        assert await wait_label(page, "wins the round")
        await page.wait_for_timeout(int(SETTLE * 1000))

        labels = await list_labels(page)
        vote = next(L for L in labels if "wins the round" in L)
        assert await tap(page, vote)
        await page.wait_for_timeout(int(BEAT * 1000))

        labels = await list_labels(page)
        if any("wins the round" in L for L in labels):
            await tap(page, next(L for L in labels if "wins the round" in L))

        assert await wait_label(page, "Next round")
        await page.wait_for_timeout(750)

        video_path = await page.video.path() if page.video else None
        await context.close()
        await browser.close()

        if not video_path:
            raise SystemExit("no video recorded")

        webm = OUT / "round-demo.webm"
        mp4 = OUT / "round-demo.mp4"
        gif = OUT / "round-demo.gif"
        Path(video_path).replace(webm)

        ffmpeg_mp4(webm, mp4)
        ffmpeg_gif(mp4, gif)
        webm.unlink(missing_ok=True)
        for pth in video_dir.glob("*"):
            if pth.is_file():
                pth.unlink(missing_ok=True)
        try:
            video_dir.rmdir()
        except OSError:
            pass

        dur = subprocess.check_output(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=nw=1:nk=1",
                str(mp4),
            ],
            text=True,
        ).strip()
        print(f"wrote {mp4} duration={dur}s size={mp4.stat().st_size}")
        print(f"wrote {gif} size={gif.stat().st_size}")


if __name__ == "__main__":
    asyncio.run(main())
