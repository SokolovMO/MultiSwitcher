"""Cut actual recorded takes; write one cue sheet from the animation's frame schedule."""
import sys,json,subprocess,math,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SKILL=Path(os.environ.get('REAL_SFX_SCRIPTS',str(Path.home()/'.codex/skills/real-sfx/scripts')))
sys.path.insert(0,str(SKILL))
from common import clean_hits,analyse_sound,onset_time
AUDIO=ROOT/'public/audio';WORK=ROOT/'work';SOURCE=WORK/'sources'
AUDIO.mkdir(exist_ok=True,parents=True)
t=json.loads((ROOT/'src/timing.json').read_text());fps=t['fps']
def cut(name,source,start,duration):
 out=AUDIO/name
 filters=f'atrim=start={start}:duration={duration},asetpts=PTS-STARTPTS,highpass=f=65,afade=t=in:d=0.001,afade=t=out:st={duration-.012}:d=0.012'
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(source),'-af',filters,'-ar','48000','-ac','2','-c:a','pcm_s24le',str(out)],check=True)
 return out
hits,_=clean_hits(SOURCE/'scissor.mp3',max_len=.15)
hits=[h for h in hits if h['clean'] and h['level_db']>-18]
key_takes=hits[:9]
if len(key_takes)<8:
 raise RuntimeError('not enough isolated scissor-key takes')
# Actual scissor-switch recordings; keep their natural attacks and short releases.
for i,h in enumerate(key_takes):cut(f'key-{i:02}.wav',SOURCE/'scissor.mp3',h['start'],.10)
option_take=key_takes[0]
cut('option.wav',SOURCE/'scissor.mp3',option_take['start'],.13)

for i,start in enumerate([.056,.584,2.610]):cut(f'click-{i}.wav',SOURCE/'click.mp3',start,.18)
cut('whoosh.wav',SOURCE/'whoosh.mp3',0,.40)
cut('cable.wav',SOURCE/'cable.mp3',.075,.52)
cut('impact.wav',SOURCE/'impact.mp3',.52,.55)
cues=[]
for i,frame in enumerate(t['firstKeys']+t['continuationKeys']):
 cues.append({'frame':frame,'t':frame/fps,'visual_t':frame/fps,'label':f'key-{i:02}','file':str(AUDIO/f'key-{i%len(key_takes):02}.wav'),'role':'key','anchor':'arrive','gain_db':[-5,-4,-6,-3,-5,-4][i%6],'max_dur':.10,'fade_in':.001,'fade_out':.012})
for frame,label in [(t['optionPress'],'option-press'),(t['selectionPress'],'selection-option')]:
 cues.append({'frame':frame,'t':frame/fps,'label':label,'file':str(AUDIO/'option.wav'),'role':'click','anchor':'start','gain_db':1,'max_dur':.13,'fade_in':.001,'fade_out':.018})
for i,(frame,label) in enumerate([(t['menuClick'],'tray-open'),(t['menuControl'],'menu-control'),(t['menuSettings'],'menu-settings'),(t['githubEnter'],'github-enter')]):
 cues.append({'frame':frame,'t':frame/fps,'label':label,'file':str(AUDIO/f'click-{i%3}.wav'),'role':'ui','anchor':'start','gain_db':-7,'max_dur':.18,'fade_in':.001,'fade_out':.012})
for frame,name,role in [(t['continuationStart'],'whoosh.wav','whoosh'),(t['menuClick'],'cable.wav','whoosh'),(t['selectionStart'],'click-1.wav','ui'),(t['privacyStart'],'whoosh.wav','whoosh'),(t['endStart'],'impact.wav','hit')]:
 cues.append({'frame':frame,'t':frame/fps,'label':f'cut-{frame}','file':str(AUDIO/name),'role':role,'anchor':'peak' if role!='ui' else 'start','gain_db':-12 if role!='hit' else -16,'max_dur':.55 if role=='hit' else .52 if name=='cable.wav' else .4,'fade_in':.005,'fade_out':.03})
cues.sort(key=lambda c:c['t'])
sheet={'duration':t['duration']/fps,'fps':fps,'keep_audio':'no','cues':cues}
(WORK/'cues.json').write_text(json.dumps(sheet,indent=2)+'\n')
# An explicit project-only library keeps the installed skill configuration untouched.
config={'libraries':[{'name':'recorded-cc0','path':str(AUDIO),'tier':'main'}],'uisfx':{'path':str(SKILL.parent/'vendor/node_modules/uisfx'),'default_pack':'studio'},'index_path':str(WORK/'library-index.json'),'skip_dir_names':[]}
(WORK/'real-sfx-config.json').write_text(json.dumps(config,indent=2))
print(json.dumps({'cues':len(cues),'distinctRecordedKeyTakes':len(key_takes),'fps':fps,'duration':t['duration']/fps,'sources':{n:analyse_sound(AUDIO/n) for n in ['option.wav','click-0.wav','whoosh.wav']}},indent=2))
