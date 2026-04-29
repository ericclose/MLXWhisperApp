import sys
import argparse
import json
import os
import re

# Enable hf-xet for faster downloads if available
try:
    import hf_xet
    os.environ["HF_XET_HIGH_PERFORMANCE"] = "1"
except ImportError:
    pass

import mlx_whisper
import mlx.core as mx
from huggingface_hub import snapshot_download

def get_model_dtype(model_path):
    """
    Automatically detect the model's preferred precision from config.json.
    Defaults to float16 for MLX models if not specified.
    """
    try:
        config_path = os.path.join(model_path, "config.json")
        if os.path.exists(config_path):
            with open(config_path, "r") as f:
                config = json.load(f)
                # Check torch_dtype or any MLX specific dtype fields
                dtype_str = config.get("torch_dtype", "float16")
                if "float32" in dtype_str:
                    return mx.float32
        return mx.float16
    except:
        return mx.float16

# --- MONKEY PATCH TO FIX MLX-WHISPER DTYPE BUG ---
import mlx_whisper.decoding as decoding

def _patched_get_audio_features(self, mel):
    """
    A robust replacement for mlx_whisper.decoding.DecodingTask._get_audio_features.
    It performs the encoder forward pass and automatically ensures the output 
    dtype matches the model's expected dtype, bypassing the buggy internal check.
    """
    # 1. Ensure input mel matches requested precision
    if self.options.fp16:
        mel = mel.astype(mx.float16)
    
    # 2. Perform encoder forward pass
    audio_features = self.model.encoder(mel)
    
    # 3. FIX: Determine target dtype based on options (same logic as mlx_whisper uses)
    # This bypasses the crash while maintaining the intended precision
    target_dtype = mx.float16 if self.options.fp16 else mx.float32
    
    if audio_features.dtype != target_dtype:
        audio_features = audio_features.astype(target_dtype)
        
    return audio_features

# Inject the robust patch
decoding.DecodingTask._get_audio_features = _patched_get_audio_features
# ------------------------------------------------

class SubprocessReporter:
    def __init__(self):
        self.stdout_buf = ""
        self.stderr_buf = ""
        self.real_stdout = sys.__stdout__
        # Regex for tqdm: matches percentage, current size/total size, time, and speed
        # Example: 45%|████▍     | 1.25GB/2.87GB [00:15<00:18, 85.2MB/s]
        self.tqdm_re = re.compile(r"(\d+)%\|.*\|?\s*([\d\.]+[kMG]?B)?/?([\d\.]+[kMG]?B)?\s*\[.*,\s*([\d\.]+[kMG]?B/s)\]")
        self.last_percent = 0

    def write_stdout(self, text):
        for char in text:
            if char == '\n':
                self.parse_stdout_line(self.stdout_buf)
                self.stdout_buf = ""
            elif char != '\r':
                self.stdout_buf += char

    def write_stderr(self, text):
        for char in text:
            if char == '\r' or char == '\n':
                line = self.stderr_buf.strip()
                if line:
                    self.parse_stderr_line(line)
                self.stderr_buf = ""
            else:
                self.stderr_buf += char

    def parse_stdout_line(self, line):
        if line.startswith("[") and "-->" in line:
            self.emit("segment_text", line)

    def parse_stderr_line(self, line):
        # 1. Look for global progress: "Fetching 12 files:  25%|..."
        global_match = re.search(r"Fetching \d+ files:\s+(\d+)%", line)
        if global_match:
            percent = int(global_match.group(1))
            if percent >= self.last_percent:
                self.last_percent = percent
                self.emit("download_progress", {"percent": percent, "raw": line})
            return

        # 2. Look for standard tqdm file progress or hf-xet progress
        # Example: 45%|████▍     | 1.25GB/2.87GB [00:15<00:18, 85.2MB/s]
        # Or: downloading model.safetensors:  10%
        match = self.tqdm_re.search(line)
        if not match:
            # Fallback regex for simpler percentage lines often seen in hf-xet or simplified logs
            match = re.search(r"(\d+)%", line)
            
        if match:
            try:
                percent = int(match.group(1))
                # Only update if it's download context
                if any(kw in line.lower() for kw in ["download", "fetching", "byte", " b", " b/s"]):
                    # To prevent jumping back during multi-file downloads, 
                    # we only report progress if it's higher than last_percent.
                    # Note: We reset last_percent when a new stage starts (in main)
                    if percent > self.last_percent:
                        self.last_percent = percent
                        self.emit("download_progress", {"percent": percent, "raw": line})
                else:
                    self.emit("transcription_progress", {"percent": percent, "raw": line})
            except:
                pass
            return

        # 3. Final fallback for lines containing percentage markers
        if "%|" in line:
            if any(unit in line for unit in ["B/s", "Fetching", "kB/s", "MB/s", "GB/s"]):
                self.emit("download_progress", {"raw": line})
            else:
                self.emit("transcription_progress", {"raw": line})

    def emit(self, msg_type, data):
        print(json.dumps({"type": msg_type, "data": data}), file=self.real_stdout, flush=True)

    def flush(self):
        pass

reporter = SubprocessReporter()

# Keep original stderr for tracebacks
original_stderr = sys.stderr

class StdoutWrapper:
    def write(self, text):
        reporter.write_stdout(text)
    def flush(self):
        original_stderr.flush()

class StderrWrapper:
    def write(self, text):
        reporter.write_stderr(text)
        # Still write to original stderr so Swift can capture it as raw text if needed
        original_stderr.write(text)
    def flush(self):
        original_stderr.flush()

sys.stdout = StdoutWrapper()
sys.stderr = StderrWrapper()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", type=str, required=True, help="Path to the audio file")
    parser.add_argument("--model", type=str, required=True, help="Hugging Face model ID")
    parser.add_argument("--temperature", type=float, default=0.0, help="Temperature for sampling")
    parser.add_argument("--logprob_threshold", type=float, default=-1.0, help="Log probability threshold")
    parser.add_argument("--compression_ratio_threshold", type=float, default=2.4, help="Compression ratio threshold")
    
    args = parser.parse_args()

    try:
        # Explicitly check/download model first to show better progress
        reporter.last_percent = 0
        reporter.emit("status", "Checking model...")
        # snapshot_download will use the redirected stderr, which our reporter will parse
        model_path = snapshot_download(repo_id=args.model)
        
        # Automatically determine if we should use fp16 based on model config
        model_dtype = get_model_dtype(model_path)
        use_fp16 = (model_dtype == mx.float16)
        
        reporter.last_percent = 0
        reporter.emit("status", "Transcribing...")
        result = mlx_whisper.transcribe(
            args.audio,
            path_or_hf_repo=model_path,
            temperature=args.temperature,
            logprob_threshold=args.logprob_threshold,
            compression_ratio_threshold=args.compression_ratio_threshold,
            verbose=False,
            fp16=use_fp16
        )

        reporter.emit("success", result)

    except Exception as e:
        import traceback
        error_info = traceback.format_exc()
        reporter.emit("error", error_info)
        original_stderr.write(f"\nFATAL ERROR:\n{error_info}\n")
        original_stderr.flush()
        sys.exit(1)

if __name__ == "__main__":
    main()
