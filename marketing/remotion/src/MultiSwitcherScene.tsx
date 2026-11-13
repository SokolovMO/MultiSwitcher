import React from "react";
import {
  AbsoluteFill,
  Img,
  Interactive,
  Sequence,
  Track,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Audio } from "@remotion/media";
import timing from "./timing.json";

// Same font renderer as SystemTypography.swift: NSFont.systemFont on macOS.
// No webfonts, raster brand marks with uppercase letters or CSS animation clocks.
export const systemFont =
  '-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif';
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const kick = (frame: number, fps: number, length = 16) =>
  spring({
    frame,
    fps,
    durationInFrames: length,
    config: { stiffness: 720, damping: 17, mass: 0.42 },
  });
const countAt = (frames: number[], frame: number) =>
  frames.filter((at) => at <= frame).length;

const Caret = ({ lastKey = -100 }: { lastKey?: number }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const active = frame - lastKey < fps * 0.23;
  return (
    <span
      aria-hidden
      style={{
        display: "inline-block",
        width: 5,
        height: 140,
        marginLeft: 9,
        verticalAlign: "-.12em",
        background: "currentColor",
        opacity:
          active || Math.floor((frame - lastKey) / (fps * 0.35)) % 2 === 0
            ? 1
            : 0,
      }}
    />
  );
};

const OptionKey = ({ at }: { at: number }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const entrance = kick(frame - at + 10, fps, 12);
  const press = interpolate(frame, [at - 1, at + 2, at + 8], [0, 1, 0], clamp);
  return (
    <div
      style={{
        position: "absolute",
        right: 165,
        bottom: 175,
        display: "flex",
        alignItems: "center",
        gap: 24,
        padding: "28px 38px",
        borderRadius: 25,
        background: press > 0.2 ? "#d8d8d6" : "#ececea",
        border: "2px solid #d2d2cf",
        boxShadow: `0 ${9 - press * 7}px 0 #c1c1be`,
        opacity: frame >= at - 10 ? 1 : 0,
        scale: entrance * (1 - press * 0.09),
        translate: `0px ${press * 8}px`,
        fontSize: 72,
        fontWeight: 450,
      }}
    >
      <span>⌥</span>
      <span style={{ fontSize: 36 }}>option</span>
    </div>
  );
};

const Frame = ({
  children,
  dark = false,
}: {
  children: React.ReactNode;
  dark?: boolean;
}) => (
  <AbsoluteFill
    style={{
      fontFamily: systemFont,
      background: dark ? "#181818" : "#f8f8f6",
      color: dark ? "#f8f8f6" : "#191919",
      overflow: "hidden",
      textTransform: "lowercase",
    }}
  >
    {children}
  </AbsoluteFill>
);

const Typing = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const corrected = frame >= timing.correction;
  const continueCount = countAt(timing.continuationKeys, frame);
  const text = corrected
    ? "привет" + ", продолжим?".slice(0, continueCount)
    : "ghbdtn".slice(0, countAt(timing.firstKeys, frame));
  const lastKey = Math.max(
    0,
    ...[
      ...timing.firstKeys,
      ...timing.continuationKeys,
      timing.optionPress,
    ].filter((at) => at <= frame),
  );
  const snap = kick(frame - timing.correction, fps, 13);
  const punch = frame >= timing.correction ? 1 + 0.065 * (1 - snap) : 1;
  const shot = frame >= timing.continuationStart;
  return (
    <Frame>
      <Interactive.Div
        name="титр"
        style={{
          position: "absolute",
          left: 150,
          top: 108,
          fontSize: 76,
          fontWeight: 570,
          letterSpacing: "-.045em",
          scale: interpolate(frame, [0, 10], [0.94, 1], {
            ...clamp,
            easing: undefined,
          }),
        }}
      >
        {corrected ? "не перепечатывай." : "не та раскладка?"}
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          left: 150,
          top: shot ? 390 : 420,
          scale: shot ? 1.035 : punch,
          transformOrigin: "left center",
          translate: `${shot ? 0 : interpolate(frame, [0, 9], [22, 0], clamp)}px 0px`,
          whiteSpace: "nowrap",
        }}
      >
        <div
          style={{
            fontSize: shot ? 135 : 164,
            fontWeight: 440,
            letterSpacing: "-.055em",
            lineHeight: 1.12,
          }}
        >
          {text}
          <Caret lastKey={lastKey} />
        </div>
      </div>
      {frame >= 74 && frame < timing.continuationStart && (
        <OptionKey at={timing.optionPress} />
      )}
      {shot && (
        <Interactive.Div
          name="продолжение мысли"
          style={{
            position: "absolute",
            left: 155,
            bottom: 157,
            fontSize: 46,
            color: "#676763",
            translate: `0px ${24 * (1 - kick(frame - timing.continuationStart - 2, fps, 13))}px`,
          }}
        >
          и пиши дальше.
        </Interactive.Div>
      )}
    </Frame>
  );
};

/** Actual NSMenu pixels; one row is re-typeset to obey the lowercase brief.
 * The mask covers the original uppercase input-source badge. No uppercase logo is used. */
export const LowercaseNativeMenu = () => (
  <div
    style={{
      position: "relative",
      width: 774,
      height: 711,
      overflow: "hidden",
      borderRadius: 36,
    }}
  >
    <Img
      name="настоящее меню"
      src={staticFile("menu-real.png")}
      style={{
        position: "absolute",
        width: 1224,
        maxWidth: "none",
        left: -225,
        top: -225,
      }}
    />
    <div
      style={{
        position: "absolute",
        left: 82,
        top: 91,
        width: 655,
        height: 65,
        background: "#b9b9b9",
        fontSize: 42,
        lineHeight: "65px",
        fontWeight: 400,
        letterSpacing: 0,
      }}
    >
      раскладка: ая
      <span style={{ float: "right", paddingRight: 25, fontSize: 52 }}>›</span>
    </div>
  </div>
);

const Menu = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const clickAt = timing.menuClick - timing.menuStart;
  const firstHover = timing.menuControl - timing.menuStart;
  const secondHover = timing.menuSettings - timing.menuStart;
  const open = kick(frame - clickAt, fps, 14);
  const zoom = interpolate(frame, [0, 110], [1, 1.035], clamp);
  return (
    <Frame>
      <Interactive.Div
        name="рядом"
        style={{
          position: "absolute",
          left: 150,
          top: 130,
          width: 600,
          fontSize: 112,
          fontWeight: 570,
          lineHeight: 1.04,
          letterSpacing: "-.055em",
          translate: `${-50 * (1 - kick(frame, fps, 12))}px 0px`,
        }}
      >
        всегда
        <br />
        рядом.
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          right: 150,
          top: 55,
          width: 820,
          height: 68,
          background: "#e5e5e2",
          borderRadius: 24,
          display: "flex",
          justifyContent: "flex-end",
          alignItems: "center",
          paddingRight: 30,
          fontSize: 34,
          fontWeight: 500,
        }}
      >
        <span
          style={{
            padding: "5px 14px",
            borderRadius: 10,
            background: frame >= clickAt ? "#ccccca" : "transparent",
          }}
        >
          ая
        </span>
        <span style={{ marginLeft: 26, fontSize: 27 }}>09:41</span>
      </div>
      <div
        style={{
          position: "absolute",
          right: 174,
          top: 137,
          transformOrigin: "95% 0%",
          scale: Math.max(0.01, open) * zoom,
          translate: `0px ${-24 * (1 - open)}px`,
          opacity: frame >= clickAt ? 1 : 0,
        }}
      >
        <LowercaseNativeMenu />
        {frame >= firstHover && (
          <div
            style={{
              position: "absolute",
              left: 30,
              right: 28,
              top: frame < secondHover ? 174 : 414,
              height: 66,
              background: "#0000000d",
              borderRadius: 9,
            }}
          />
        )}
      </div>
      <Interactive.Div
        name="контроль"
        style={{
          position: "absolute",
          left: 156,
          bottom: 175,
          fontSize: 43,
          lineHeight: 1.3,
          color: "#686864",
        }}
      >
        автоконверсия.
        <br />
        пауза. твои правила.
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          right: 395,
          top:
            95 +
            243 * kick(frame - firstHover + 10, fps, 10) +
            252 * kick(frame - secondHover + 10, fps, 10),
          fontSize: 52,
          scale: frame >= clickAt ? 1.2 : 1,
          color: "#202020",
        }}
      >
        ↖
      </div>
    </Frame>
  );
};

const Selection = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const correctedAt = timing.selectionCorrection - timing.selectionStart;
  const done = frame >= correctedAt;
  const reveal = kick(frame, fps, 12);
  return (
    <Frame>
      <Interactive.Div
        name="выделенный текст"
        style={{
          position: "absolute",
          left: 150,
          top: 120,
          fontSize: 76,
          fontWeight: 560,
          letterSpacing: "-.045em",
          translate: `${24 * (1 - reveal)}px 0px`,
        }}
      >
        и выделенный текст.
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          left: 150,
          top: 410,
          fontSize: 150,
          fontWeight: 430,
          letterSpacing: "-.05em",
          scale: done ? 1 + 0.05 * (1 - kick(frame - correctedAt, fps, 12)) : 1,
          transformOrigin: "left center",
        }}
      >
        <span
          style={{
            background: done ? "transparent" : "#c4dcff",
            padding: "4px 13px",
          }}
        >
          {done ? "как дела?" : "rfr ltkf?"}
        </span>
        {done && <Caret lastKey={correctedAt} />}
      </div>
      <OptionKey at={timing.selectionPress - timing.selectionStart} />
    </Frame>
  );
};

const Privacy = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = kick(frame, fps, 13);
  return (
    <Frame dark>
      <Interactive.Div
        name="локальная обработка"
        style={{
          position: "absolute",
          left: 150,
          top: 240,
          fontSize: 130,
          fontWeight: 550,
          lineHeight: 1.03,
          letterSpacing: "-.055em",
          scale: 0.9 + 0.1 * p,
          translate: `0px ${36 * (1 - p)}px`,
        }}
      >
        твой текст.
        <br />
        на твоём mac.
      </Interactive.Div>
      <div
        style={{
          position: "absolute",
          left: 155,
          bottom: 170,
          fontSize: 42,
          color: "#b6b6b2",
        }}
      >
        без отправки слов в облако.
      </div>
    </Frame>
  );
};

const End = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const first = kick(frame, fps, 14);
  const githubAt = timing.githubEnter - timing.endStart;
  const second = kick(frame - githubAt, fps, 14);
  return (
    <Frame>
      <Interactive.Div
        name="название"
        style={{
          position: "absolute",
          left: 150,
          top: 130,
          fontSize: 60,
          fontWeight: 600,
          letterSpacing: "-.035em",
          translate: `0px ${30 * (1 - first)}px`,
        }}
      >
        multiswitcher
      </Interactive.Div>
      <Interactive.Div
        name="обещание"
        style={{
          position: "absolute",
          left: 145,
          top: 320,
          fontSize: 174,
          lineHeight: 0.98,
          fontWeight: 570,
          letterSpacing: "-.06em",
          scale: 0.92 + 0.08 * first,
          transformOrigin: "left center",
        }}
      >
        пиши дальше.
      </Interactive.Div>
      <Interactive.Div
        name="адрес репозитория"
        style={{
          position: "absolute",
          left: 155,
          bottom: 186,
          fontSize: 46,
          fontWeight: 450,
          letterSpacing: "-.02em",
          opacity: frame >= githubAt ? 1 : 0,
          translate: `0px ${24 * (1 - second)}px`,
        }}
      >
        sokolovmo/multiswitcher{" "}
        <span
          style={{
            display: "inline-block",
            marginLeft: 22,
            translate: `${8 * (1 - kick(frame - 48, fps, 12))}px 0px`,
          }}
        >
          ↗
        </span>
      </Interactive.Div>
    </Frame>
  );
};

export const MultiSwitcherScene = () => (
  <>
    <Track name="монтаж">
      <Sequence name="ошибка и продолжение" durationInFrames={timing.menuStart}>
        <Typing />
      </Sequence>
      <Sequence
        name="меню в строке macos"
        from={timing.menuStart}
        durationInFrames={timing.selectionStart - timing.menuStart}
      >
        <Menu />
      </Sequence>
      <Sequence
        name="конвертация выделения"
        from={timing.selectionStart}
        durationInFrames={timing.privacyStart - timing.selectionStart}
      >
        <Selection />
      </Sequence>
      <Sequence
        name="локально"
        from={timing.privacyStart}
        durationInFrames={timing.endStart - timing.privacyStart}
      >
        <Privacy />
      </Sequence>
      <Sequence
        name="финал"
        from={timing.endStart}
        durationInFrames={timing.duration - timing.endStart}
      >
        <End />
      </Sequence>
    </Track>
    <Audio
      name="записанные звуки — синхронный мастер"
      src={staticFile("audio/sfx-scissor-master.wav")}
      volume={1}
    />
  </>
);
