"""Generate Vault Run's recorded-style sounds with the local sfx-lab (Stable Audio Open 1.0).

Run from anywhere with sfx-lab's Python:
  ~/personal/sfx-lab/.venv/bin/python ~/personal/vault-run/tools/make_sounds.py

Loads the model once, then writes sfx/<id>.wav for every clip not already there.
The game (sfx.gd) uses these files in place of its synthesised sounds when present.
"""

import sys
import time
from pathlib import Path

SFX_LAB = Path.home() / "personal" / "sfx-lab"
sys.path.insert(0, str(SFX_LAB))

import soundfile as sf  # noqa: E402
import torch  # noqa: E402
from diffusers import StableAudioPipeline  # noqa: E402
from huggingface_hub import snapshot_download  # noqa: E402
from make_sfx import MODEL, keep_noise_in_range  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "sfx"

# id -> (prompt, seconds)
CLIPS = {
    "roar": ("a single loud powerful tiger roar, close up, wild animal, no music", 3),
    "growl": ("a tiger snarling and growling aggressively, close up, no music", 3),
    "snake": ("a cobra snake hissing loudly, close up, no music", 2),
    "trumpet": ("an elephant trumpeting loudly once, no music", 3),
    "monkey": ("a monkey chattering and screeching, jungle, no music", 3),
    "thunder": ("a loud thunder clap followed by rolling rumble, no music", 5),
    "punch": ("a single hard punch impact hit, cartoon fight, no music", 1),
    "crumble": ("stone blocks crumbling and rocks falling down a cliff, no music", 3),
    "boulder": ("a huge heavy stone boulder rolling over stone floor, rumbling, no music", 3),
    "rain": ("steady heavy rain falling on jungle leaves, continuous, no thunder, no music", 8),
    "amb_day": ("tropical jungle ambience in daytime, many birds singing, insects, gentle wind, no music", 12),
    "amb_night": ("jungle at night ambience, crickets and frogs, calm, no music", 10),
}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    todo = {k: v for k, v in CLIPS.items() if not (OUT / f"{k}.wav").exists()}
    if not todo:
        print("all clips present", flush=True)
        return
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    started = time.time()
    folder = snapshot_download(MODEL, ignore_patterns=["model.safetensors", "*.ckpt"])
    pipe = StableAudioPipeline.from_pretrained(folder, torch_dtype=torch.float32).to(device)
    keep_noise_in_range(pipe.scheduler.config.sigma_min)
    print(f"loaded in {time.time() - started:.0f} s on {device}; {len(todo)} clips to make", flush=True)
    for name, (prompt, seconds) in todo.items():
        audio = pipe(
            prompt,
            negative_prompt="low quality, music, speech, distortion",
            num_inference_steps=60,
            audio_end_in_s=float(seconds),
            num_waveforms_per_prompt=1,
            generator=torch.Generator("cpu").manual_seed(0),
        ).audios[0]
        sf.write(OUT / f"{name}.wav", audio.T.float().cpu().numpy(), pipe.vae.sampling_rate)
        print(f"{name}.wav ({time.time() - started:.0f} s)", flush=True)
        if device == "mps":
            torch.mps.empty_cache()
    print("done", flush=True)


if __name__ == "__main__":
    main()
