# Critique, round 1

| axis | score | basis |
|---|---|---|
| hook | 10.0 | first sound at 0.20s |
| sync | 9.5 | 16/17 sounds on their frame (peaks, arrivals, or first onsets for clicks) |
| coverage | n/a | not measured (pass --moments) |
| pacing | 10.0 | 7.5 weighted events per 10 s, longest silence 1.8 s; 11.0 gestures per 10 s (the references run up to 15.11; this film has no sound of its own, so too busy is judged by that number); 2 runs of typing/ticks count once (18 sounds) |
| variety | 5.8 | 4 source recordings, 4 families in 6 sounds (runs and interface sounds not counted) |
| hierarchy | 10.0 | 10.1 dB between the loud and the quiet sounds |
| headroom | 10.0 | true peak -2.4 dBTP |
| loudness | 4.0 | final -27.9 LUFS; target -18 LUFS not reached: the file measures -27.9 LUFS (sparse sound; going further would need heavy limiting) |
| mono | 10.0 | the SFX track loses 0.3 dB when folded to mono (0 = the channels agree, 3 = unrelated, 6+ = parts cancel); 0 of 29 sounds lose more than 6 dB |

**FIX**: lowest axis 4.0 (every axis must reach 8; ok to show)

Three worst problems, fix only these, re-render, run again:
1. sync: 'tray-open' at 3.63s peaks -46 ms from the moment

Listen to these 2 moments, on headphones and then once on a phone speaker. This script cannot hear: they are the places where the numbers above are least certain, and none of them says that it sounds good:
  1.    0.20s  'key-00': brought 6 dB up to the perceived level of its role; the first sound of the film: the hook. Listen for: a thin recording lifted that far can turn harsh: is it clean? / does it land with the picture at once, and is it clearly there under the music or the voice?
  2.    3.63s  'tray-open': its peak sits -46 ms from the moment; also 'key-09' at 2.28s: the highest peak of the film (-7 dBFS before the master). Listen for: does it feel early or late against the picture? / is it big without hurting on headphones, and does the music under it pump?
  (--listen-out FILE.wav cuts them into one file of the film's own sound)

(The sound of this film is only SFX: --style clean-sfx-refs sets it against nine finished SFX reels, numbers only, no scores.)

Still to judge by eye on review.png: character fit (each sound suits its picture), cleanliness (no mud in the low end under music/voice, nothing masks speech), taste (designed, not sprayed on).