"""Read earshot's objective meters and event alignment without loading semantic models."""
import json
from pathlib import Path
from earshot import audio,features
from earshot.timeline import detect_events,sync,level_envs
root=Path(__file__).resolve().parents[1]
path=root/'public/audio/sfx-master.wav'
x=audio.load(str(path))
cues=json.loads((root/'work/cues.json').read_text())
events=detect_events(x)
expected=[{'t':c['frame']/cues['fps'],'kind':c['role'],'id':c['label']} for c in cues['cues']]
result={'mode':'earshot objective meters and waveform event alignment; no semantic models','measure':features.measure(str(path)), 'sync':sync(expected,events,frame_s=1/60,levels=level_envs(x))}

keys=[item for item in result['sync']['items'] if item.get('id','').startswith('key-')]
result['typing_sync']={'count':len(keys),'within_1_frame':sum(abs(item['offset_ms'])<=1000/60 for item in keys),'max_abs_offset_ms':max(abs(item['offset_ms']) for item in keys)}
(root/'work/earshot-final.json').write_text(json.dumps(result,indent=2))
print(json.dumps({'lufs':result['measure']['lufs'],'true_peak_dbtp':result['measure']['true_peak_dbtp'],'clipped_samples':result['measure']['clipped_samples'],'sync':result['sync']['stats']},indent=2))
