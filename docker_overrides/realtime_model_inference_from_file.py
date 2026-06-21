import argparse
import copy
import glob
import os
import threading
import time
import traceback

import torch
from transformers.cache_utils import DynamicCache
from transformers.modeling_outputs import BaseModelOutputWithPast
from transformers.utils import logging

from vibevoice.modular.modeling_vibevoice_streaming_inference import VibeVoiceStreamingForConditionalGenerationInference
from vibevoice.processor.vibevoice_streaming_processor import VibeVoiceStreamingProcessor

logging.set_verbosity_info()
logger = logging.get_logger(__name__)


def clock(seconds):
    total_seconds = max(0, int(round(seconds)))
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60
    if hours:
        return f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


class GenerationHeartbeat:
    def __init__(self, phase, estimated_seconds, interval=2.0):
        self.phase = phase
        self.estimated_seconds = max(1.0, float(estimated_seconds))
        self.interval = interval
        self.started_at = None
        self.stop_event = threading.Event()
        self.thread = None

    def start(self):
        self.started_at = time.time()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()
        self.emit()

    def stop(self, phase="finalizing", progress=0.96):
        self.stop_event.set()
        if self.thread is not None:
            self.thread.join(timeout=1.0)
        self.emit(phase=phase, progress=progress)

    def emit(self, phase=None, progress=None):
        if self.started_at is None:
            elapsed = 0.0
        else:
            elapsed = time.time() - self.started_at
        fraction = progress if progress is not None else min(0.95, elapsed / self.estimated_seconds)
        print(
            "Fonim progress: "
            f"phase={phase or self.phase} "
            f"elapsed={clock(elapsed)} "
            f"estimated={clock(self.estimated_seconds)} "
            f"progress={fraction * 100:.2f}%",
            flush=True,
        )

    def _run(self):
        while not self.stop_event.wait(self.interval):
            self.emit()


def estimate_generation_seconds(input_tokens, ddpm_steps, text):
    word_count = max(1, len(text.split()))
    token_component = max(8.0, float(input_tokens) * 0.75)
    word_component = float(word_count) * 1.5
    ddpm_multiplier = max(0.6, float(ddpm_steps) / 8.0)
    return max(12.0, (token_component + word_component) * ddpm_multiplier)


class VoiceMapper:
    """Maps speaker names to voice file paths."""

    def __init__(self):
        self.setup_voice_presets()

    def setup_voice_presets(self):
        voices_dir = os.path.join(os.path.dirname(__file__), "voices/streaming_model")

        if not os.path.exists(voices_dir):
            print(f"Warning: Voices directory not found at {voices_dir}")
            self.voice_presets = {}
            self.available_voices = {}
            return

        self.voice_presets = {}
        pt_files = glob.glob(os.path.join(voices_dir, "**", "*.pt"), recursive=True)

        for pt_file in pt_files:
            name = os.path.splitext(os.path.basename(pt_file))[0].lower()
            full_path = os.path.abspath(pt_file)
            self.voice_presets[name] = full_path

        self.voice_presets = dict(sorted(self.voice_presets.items()))
        self.available_voices = {
            name: path for name, path in self.voice_presets.items()
            if os.path.exists(path)
        }

        print(f"Found {len(self.available_voices)} voice files in {voices_dir}")
        print(f"Available voices: {', '.join(self.available_voices.keys())}")

    def get_voice_path(self, speaker_name: str) -> str:
        speaker_name = speaker_name.lower()
        if speaker_name in self.voice_presets:
            return self.voice_presets[speaker_name]

        matched_path = None
        for preset_name, path in self.voice_presets.items():
            if preset_name.lower() in speaker_name or speaker_name in preset_name.lower():
                if matched_path is not None:
                    raise ValueError(f"Multiple voice presets match the speaker name '{speaker_name}', please make the speaker_name more specific.")
                matched_path = path
        if matched_path is not None:
            return matched_path

        default_voice = list(self.voice_presets.values())[0]
        print(f"Warning: No voice preset found for '{speaker_name}', using default voice: {default_voice}")
        return default_voice


def parse_args():
    parser = argparse.ArgumentParser(description="VibeVoiceStreaming Processor TXT Input Test")
    parser.add_argument(
        "--model_path",
        type=str,
        default="microsoft/VibeVoice-Realtime-0.5B",
        help="Path to the HuggingFace model directory",
    )
    parser.add_argument(
        "--txt_path",
        type=str,
        default="demo/text_examples/1p_vibevoice.txt",
        help="Path to the txt file containing the script",
    )
    parser.add_argument(
        "--speaker_name",
        type=str,
        default="Wayne",
        help="Single speaker name (e.g., --speaker_name Wayne)",
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="./outputs",
        help="Directory to save output audio files",
    )
    parser.add_argument(
        "--device",
        type=str,
        default=("cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")),
        help="Device for inference: cuda | mps | cpu",
    )
    parser.add_argument(
        "--cfg_scale",
        type=float,
        default=1.5,
        help="CFG (Classifier-Free Guidance) scale for generation (default: 1.5)",
    )
    parser.add_argument(
        "--ddpm_inference_steps",
        "--inference_steps",
        dest="ddpm_inference_steps",
        type=int,
        default=5,
        help="DDPM inference steps for generation (default: 5)",
    )

    return parser.parse_args()


def main():
    args = parse_args()

    if args.ddpm_inference_steps <= 0:
        raise ValueError("--ddpm_inference_steps must be greater than 0")

    if args.device.lower() == "mpx":
        print("Note: device 'mpx' detected, treating it as 'mps'.")
        args.device = "mps"

    if args.device == "mps" and not torch.backends.mps.is_available():
        print("Warning: MPS not available. Falling back to CPU.")
        args.device = "cpu"

    print(f"Using device: {args.device}")

    voice_mapper = VoiceMapper()

    if not os.path.exists(args.txt_path):
        print(f"Error: txt file not found: {args.txt_path}")
        return

    print(f"Reading script from: {args.txt_path}")
    with open(args.txt_path, "r", encoding="utf-8") as f:
        scripts = f.read().strip()

    if not scripts:
        print("Error: No valid scripts found in the txt file")
        return

    full_script = scripts.replace("’", "'").replace("“", '"').replace("”", '"')

    print(f"Loading processor & model from {args.model_path}")
    processor = VibeVoiceStreamingProcessor.from_pretrained(args.model_path)

    if args.device == "mps":
        load_dtype = torch.float32
        attn_impl_primary = "sdpa"
    elif args.device == "cuda":
        load_dtype = torch.bfloat16
        attn_impl_primary = "flash_attention_2"
    else:
        load_dtype = torch.float32
        attn_impl_primary = "sdpa"

    print(f"Using device: {args.device}, torch_dtype: {load_dtype}, attn_implementation: {attn_impl_primary}")

    try:
        if args.device == "mps":
            model = VibeVoiceStreamingForConditionalGenerationInference.from_pretrained(
                args.model_path,
                torch_dtype=load_dtype,
                attn_implementation=attn_impl_primary,
                device_map=None,
            )
            model.to("mps")
        elif args.device == "cuda":
            model = VibeVoiceStreamingForConditionalGenerationInference.from_pretrained(
                args.model_path,
                torch_dtype=load_dtype,
                device_map="cuda",
                attn_implementation=attn_impl_primary,
            )
        else:
            model = VibeVoiceStreamingForConditionalGenerationInference.from_pretrained(
                args.model_path,
                torch_dtype=load_dtype,
                device_map="cpu",
                attn_implementation=attn_impl_primary,
            )
    except Exception as e:
        if attn_impl_primary == "flash_attention_2":
            print(f"[ERROR] : {type(e).__name__}: {e}")
            print(traceback.format_exc())
            print("Error loading the model. Trying to use SDPA. However, note that only flash_attention_2 has been fully tested, and using SDPA may result in lower audio quality.")
            model = VibeVoiceStreamingForConditionalGenerationInference.from_pretrained(
                args.model_path,
                torch_dtype=load_dtype,
                device_map=(args.device if args.device in ("cuda", "cpu") else None),
                attn_implementation="sdpa",
            )
            if args.device == "mps":
                model.to("mps")
        else:
            raise e

    model.eval()
    model.set_ddpm_inference_steps(num_steps=args.ddpm_inference_steps)
    print(f"Using DDPM inference steps: {args.ddpm_inference_steps}")

    if hasattr(model.model, "language_model"):
        print(f"Language model attention: {model.model.language_model.config._attn_implementation}")

    target_device = args.device if args.device != "cpu" else "cpu"
    voice_sample = voice_mapper.get_voice_path(args.speaker_name)
    print(f"Using voice preset for {args.speaker_name}: {voice_sample}")
    with torch.serialization.safe_globals([BaseModelOutputWithPast, DynamicCache]):
        all_prefilled_outputs = torch.load(voice_sample, map_location=target_device, weights_only=True)

    inputs = processor.process_input_with_cached_prompt(
        text=full_script,
        cached_prompt=all_prefilled_outputs,
        padding=True,
        return_tensors="pt",
        return_attention_mask=True,
    )

    for k, v in inputs.items():
        if torch.is_tensor(v):
            inputs[k] = v.to(target_device)

    input_tokens = inputs["tts_text_ids"].shape[1]
    estimated_generation_seconds = estimate_generation_seconds(input_tokens, args.ddpm_inference_steps, full_script)
    print(f"Starting generation with cfg_scale: {args.cfg_scale}, ddpm_inference_steps: {args.ddpm_inference_steps}")
    print(
        "Fonim progress: "
        f"phase=starting_generation elapsed=00:00 estimated={clock(estimated_generation_seconds)} progress=0.00%",
        flush=True,
    )

    start_time = time.time()
    heartbeat = GenerationHeartbeat("generation", estimated_generation_seconds)
    heartbeat.start()
    try:
        outputs = model.generate(
            **inputs,
            max_new_tokens=None,
            cfg_scale=args.cfg_scale,
            tokenizer=processor.tokenizer,
            generation_config={"do_sample": False},
            verbose=True,
            show_progress_bar=True,
            all_prefilled_outputs=copy.deepcopy(all_prefilled_outputs) if all_prefilled_outputs is not None else None,
        )
    finally:
        heartbeat.stop()
    generation_time = time.time() - start_time
    print(f"Generation time: {generation_time:.2f} seconds")

    if outputs.speech_outputs and outputs.speech_outputs[0] is not None:
        sample_rate = 24000
        audio_samples = outputs.speech_outputs[0].shape[-1] if len(outputs.speech_outputs[0].shape) > 0 else len(outputs.speech_outputs[0])
        audio_duration = audio_samples / sample_rate
        rtf = generation_time / audio_duration if audio_duration > 0 else float("inf")

        print(f"Generated audio duration: {audio_duration:.2f} seconds")
        print(f"RTF (Real Time Factor): {rtf:.2f}x")
    else:
        print("No audio output generated")
        return

    output_tokens = outputs.sequences.shape[1]
    generated_tokens = output_tokens - input_tokens - all_prefilled_outputs["tts_lm"]["last_hidden_state"].size(1)

    print(f"Prefilling text tokens: {input_tokens}")
    print(f"Generated speech tokens: {generated_tokens}")
    print(f"Total tokens: {output_tokens}")

    txt_filename = os.path.splitext(os.path.basename(args.txt_path))[0]
    output_path = os.path.join(args.output_dir, f"{txt_filename}_generated.wav")
    os.makedirs(args.output_dir, exist_ok=True)

    processor.save_audio(
        outputs.speech_outputs[0],
        output_path=output_path,
    )
    print(f"Saved output to {output_path}")

    print("\n" + "=" * 50)
    print("GENERATION SUMMARY")
    print("=" * 50)
    print(f"Input file: {args.txt_path}")
    print(f"Output file: {output_path}")
    print(f"Speaker names: {args.speaker_name}")
    print(f"CFG scale: {args.cfg_scale}")
    print(f"DDPM inference steps: {args.ddpm_inference_steps}")
    print(f"Prefilling text tokens: {input_tokens}")
    print(f"Generated speech tokens: {generated_tokens}")
    print(f"Total tokens: {output_tokens}")
    print(f"Generation time: {generation_time:.2f} seconds")
    print(f"Audio duration: {audio_duration:.2f} seconds")
    print(f"RTF (Real Time Factor): {rtf:.2f}x")
    print("=" * 50)


if __name__ == "__main__":
    main()
