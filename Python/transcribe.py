import sys
import argparse
import json
import mlx_whisper

class SubprocessReporter:
    def __init__(self):
        self.stdout_buf = ""
        self.stderr_buf = ""
        self.real_stdout = sys.__stdout__

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
        if "%|" in line:
            if "B/s" in line or "Fetching" in line or "kB/s" in line or "MB/s" in line:
                self.emit("download_progress", line)
            else:
                self.emit("transcription_progress", line)
        elif "Fetching" in line:
            self.emit("download_progress", line)

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
        # Still try to parse progress from stderr
        reporter.write_stderr(text)
        # BUT ALSO write to original stderr so Swift can capture it as raw text
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

    reporter.emit("status", "Loading model...")

    try:
        reporter.emit("status", "Transcribing...")
        result = mlx_whisper.transcribe(
            args.audio,
            path_or_hf_repo=args.model,
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
        # Also write to real stderr just in case
        original_stderr.write(f"\nFATAL ERROR:\n{error_info}\n")
        original_stderr.flush()
        sys.exit(1)

if __name__ == "__main__":
    main()
