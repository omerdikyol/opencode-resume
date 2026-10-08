#!/usr/bin/env python3
"""Render a captured oc-resume TUI frame into a PNG (Chrome + transparent crop).

Usage:
    tmux new-session -d -s shot -x 100 -y 26 && tmux send-keys -t shot './oc-resume' Enter
    tmux capture-pane -p -t shot > /tmp/frame.txt
    python3 docs/_render.py /tmp/frame.txt docs/picker.png
"""
import html
import subprocess
import sys
from pathlib import Path

import tempfile

from PIL import Image

FONT = "'SF Mono','SFMono-Regular',Menlo,'DejaVu Sans Mono',monospace"

TPL = """<!doctype html><meta charset="utf-8">
<style>
  html,body{{margin:0;padding:0;background:transparent}}
  .win{{margin:14px;border-radius:11px;overflow:hidden;
        background:#14161c;box-shadow:0 18px 44px rgba(0,0,0,.45);
        width:{w}ch}}
  .bar{{height:34px;background:#1e212a;display:flex;align-items:center;
        padding:0 13px;gap:8px;border-bottom:1px solid #0b0d11}}
  .d{{width:11px;height:11px;border-radius:50%}}
  .r{{background:#ff5f57}} .y{{background:#febc2e}} .g{{background:#28c840}}
  .t{{flex:1;text-align:center;font:{fs}px/1 {FONT};
      color:#7d8590;letter-spacing:.02em;margin-right:52px}}
  pre{{margin:0;padding:16px 18px 18px;font:{fs}px/1.42 {FONT};
      color:#d6dae1;white-space:pre;tab-size:8}}
</style>
<div class="win">
  <div class="bar">
    <div class="d r"></div><div class="d y"></div><div class="d g"></div>
    <div class="t">{title}</div>
  </div>
  <pre>{body}</pre>
</div>
"""


def render(text: str, out: Path, title: str = "oc-resume", font_size: int = 13) -> None:
    cols = max(len(line) for line in text.splitlines())
    page = TPL.format(w=cols, body=html.escape(text), fs=font_size, FONT=FONT, title=title)
    with tempfile.TemporaryDirectory() as td:
        hp = Path(td) / "p.html"
        hp.write_text(page)
        raw = Path(td) / "s.png"
        subprocess.run(
            [
                "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                "--headless",
                "--disable-gpu",
                "--hide-scrollbars",
                "--force-device-scale-factor=2",
                "--default-background-color=00000000",
                f"--screenshot={raw}",
                "--window-size=1200,900",
                f"file://{hp}",
            ],
            check=True,
            capture_output=True,
        )
        im = Image.open(raw).convert("RGBA")
    im = im.crop(im.getbbox())  # drop empty canvas
    im.save(out, optimize=True)
    print(f"{out} {im.size[0]//2}x{im.size[1]//2} css px")


if __name__ == "__main__":
    src, dst = sys.argv[1], Path(sys.argv[2])
    title = sys.argv[3] if len(sys.argv) > 3 else "oc-resume"
    render(Path(src).read_text().rstrip("\n"), dst, title)