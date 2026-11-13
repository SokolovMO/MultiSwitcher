import { Composition } from "remotion";
import { MultiSwitcherScene } from "./MultiSwitcherScene";

export const RemotionRoot = () => (
  <Composition
    id="multiswitcher"
    component={MultiSwitcherScene}
    width={1920}
    height={1080}
    fps={60}
    durationInFrames={600}
  />
);
