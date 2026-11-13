"""Restore the public-domain source recordings for optional SFX re-editing."""
import json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=root/'work/sources';source.mkdir(parents=True,exist_ok=True)
for item in json.loads((root/'audio-sources.json').read_text()):
 target=source/(item['id']+'.mp3')
 if not target.exists():
  subprocess.run(['curl','-L','--fail','--retry','2','--max-time','120',item['media'],'-o',str(target)],check=True)
# Scissor keys are cut directly from scissor.mp3; no mechanical-keyboard excerpt is needed.
