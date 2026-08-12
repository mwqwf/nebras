"""Compress assets/images/app_icon.png while preserving visual quality.

Source : tools/app_icon_master.png   (1024x1024 RGB, ~348 KB — the
         original high-res artwork, kept outside Flutter assets so it
         is not bundled into the AAB but remains available for
         `flutter_launcher_icons` and for re-running this script).
Output : assets/images/app_icon.png  (384x384 indexed-color, <=80 KB —
         bundled in-app, used when the UI needs to draw the logo).

Strategy:
1. Down-scale master to 384x384 with LANCZOS (highest-quality resampler).
   384 > xxxhdpi launcher (192x192) so `flutter_launcher_icons` would
   still resize cleanly *if it were pointed here*, but the canonical
   source for that tool is now the master.
2. Try `optimize=True` PNG first (keeps full colour fidelity).
3. Fall back to an adaptive palette PNG with NO dither (flat-colour
   art quantises far better without dithering noise) and walk down
   256 -> 64 colours until the result fits the target.

Idempotent: running twice produces the same output, because we always
start from the master.
"""

from pathlib import Path
from PIL import Image

MASTER = Path("tools/app_icon_master.png")
DST = Path("assets/images/app_icon.png")
TARGET_KB = 80
MAX_SIZE = 384

assert MASTER.exists(), (
    f"Missing {MASTER}. Restore from git: "
    "`python -c \"import subprocess;open('tools/app_icon_master.png','wb')"
    ".write(subprocess.run(['git','cat-file','-p',"
    "'HEAD:tools/app_icon_master.png'],capture_output=True).stdout)\"`"
)

src = Image.open(MASTER)
print(f"Source: {src.size} mode={src.mode}")

if max(src.size) > MAX_SIZE:
    src = src.resize((MAX_SIZE, MAX_SIZE), Image.LANCZOS)

trial = DST.with_suffix(".trial.png")
src.save(trial, format="PNG", optimize=True)
size_kb = trial.stat().st_size / 1024
print(f"  {MAX_SIZE}x{MAX_SIZE} optimized -> {size_kb:.1f} KB (mode={src.mode})")

if size_kb <= TARGET_KB:
    trial.replace(DST)
    print(f"{DST} -> {DST.stat().st_size/1024:.1f} KB")
    raise SystemExit(0)

trial.unlink(missing_ok=True)
for n in [256, 192, 160, 128, 96, 64]:
    pal = src.convert("RGB").convert(
        "P", palette=Image.Palette.ADAPTIVE, colors=n, dither=Image.Dither.NONE
    )
    pal.save(trial, format="PNG", optimize=True)
    size_kb = trial.stat().st_size / 1024
    print(f"  {MAX_SIZE}x{MAX_SIZE} palette {n:3d} -> {size_kb:.1f} KB")
    if size_kb <= TARGET_KB:
        trial.replace(DST)
        print(f"{DST} -> {DST.stat().st_size/1024:.1f} KB")
        raise SystemExit(0)
    trial.unlink(missing_ok=True)

raise SystemExit(f"Could not reduce <= {TARGET_KB}KB at {MAX_SIZE}x{MAX_SIZE}.")
