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

import time

class SubprocessReporter:
    def __init__(self):
        self.stdout_buf = ""
        self.stderr_buf = ""
        self.real_stdout = sys.__stdout__
        # Regex for tqdm: matches percentage, current size/total size, time, and speed
        # Example: 45%|████▍     | 1.25GB/2.87GB [00:15<00:18, 85.2MB/s]
        self.tqdm_re = re.compile(r"(\d+)%\|.*\|?\s*([\d\.]+[kMG]?B)?/?([\d\.]+[kMG]?B)?\s*\[.*,\s*([\d\.]+[kMG]?B/s)\]")
        self.last_percent = -1
        self.last_time = time.time()
        self.last_bytes = 0
        self.speed_history = []

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

    def _parse_size(self, size_str):
        if not size_str: return 0
        s = size_str.upper().strip()
        try:
            # Use 1000-base for consistency with Activity Monitor / Stats
            if "GB" in s: return float(s.replace("GB", "").strip()) * 1000 * 1000 * 1000
            if "MB" in s: return float(s.replace("MB", "").strip()) * 1000 * 1000
            if "KB" in s: return float(s.replace("KB", "").strip()) * 1000
            if "B" in s: return float(s.replace("B", "").strip())
        except: pass
        return 0

    def parse_stderr_line(self, line):
        # Try robust parsing first
        match = self.tqdm_re.search(line)
        if match:
            percent = int(match.group(1))
            raw_speed = match.group(4)
            current_size_str = match.group(2)
            
            # Use provided speed but refine it if possible
            # Identify if it's download or transcription based on context
            if "B" in line and ("B/s" in line or "/" in line):
                msg_type = "download_progress"
                
                # Custom speed calculation for better accuracy/smoothing
                now = time.time()
                current_bytes = self._parse_size(current_size_str)
                if current_bytes > 0 and self.last_bytes > 0:
                    dt = now - self.last_time
                    if dt > 0.1:
                        db = current_bytes - self.last_bytes
                        if db >= 0:
                            instant_speed = db / dt
                            self.speed_history.append(instant_speed)
                            if len(self.speed_history) > 5:
                                self.speed_history.pop(0)
                            
                            avg_speed = sum(self.speed_history) / len(self.speed_history)
                            if avg_speed > 1000 * 1000:
                                raw_speed = f"{avg_speed / (1000*1000):.1f} MB/s"
                            elif avg_speed > 1000:
                                raw_speed = f"{avg_speed / 1000:.1f} KB/s"
                            else:
                                raw_speed = f"{avg_speed:.0f} B/s"
                
                self.last_bytes = current_bytes
                self.last_time = now
            else:
                msg_type = "transcription_progress"
                
            self.emit(msg_type, {"percent": percent, "speed": raw_speed, "raw": line})
            return

        # Fallback for simpler lines
        if "%|" in line:
            if any(unit in line for unit in ["B/s", "Fetching", "kB/s", "MB/s", "GB/s"]):
                self.emit("download_progress", {"raw": line})
            else:
                self.emit("transcription_progress", {"raw": line})
        elif "Fetching" in line:
            self.emit("download_progress", {"raw": line})

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
        reporter.emit("status", "Checking model...")
        # snapshot_download will use the redirected stderr, which our reporter will parse
        model_path = snapshot_download(repo_id=args.model)
        
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
