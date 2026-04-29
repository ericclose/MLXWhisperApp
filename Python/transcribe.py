import sys
import argparse
import json
import os
import re

# Enable hf_transfer for faster downloads if available
try:
    import hf_transfer
    os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
except ImportError:
    pass

import mlx_whisper
from huggingface_hub import snapshot_download

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

        # 2. Look for standard tqdm file progress or hf_transfer progress
        # Example: 45%|████▍     | 1.25GB/2.87GB [00:15<00:18, 85.2MB/s]
        # Or: downloading model.safetensors:  10%
        match = self.tqdm_re.search(line)
        if not match:
            # Fallback regex for simpler percentage lines often seen in hf_transfer or simplified logs
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
        
        reporter.last_percent = 0
        reporter.emit("status", "Transcribing...")
        result = mlx_whisper.transcribe(
            args.audio,
            path_or_hf_repo=model_path,
            temperature=args.temperature,
            logprob_threshold=args.logprob_threshold,
            compression_ratio_threshold=args.compression_ratio_threshold,
            verbose=False
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
