"""Generate original, short notification tones; no external recordings used."""
import math
from pathlib import Path
import struct
import wave

RATE = 44100
ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'sounds'
TONES = {
    'soft_chime': (1.5, [(0.02, 659.25, 0.48), (0.30, 880.0, 0.58)], 'bell'),
    'clear_bell': (1.6, [(0.02, 880.0, 0.40), (0.24, 1174.66, 0.43), (0.48, 1396.91, 0.50)], 'bell'),
    'warm_keys': (1.8, [(0.02, 523.25, 0.65), (0.30, 659.25, 0.70)], 'keys'),
    'wood_tap': (1.0, [(0.02, 392.0, 0.14), (0.24, 523.25, 0.16)], 'wood'),
}

def generate():
    ROOT.mkdir(parents=True, exist_ok=True)
    for name, (duration, notes, kind) in TONES.items():
        values = []
        for index in range(round(RATE * duration)):
            t = index / RATE
            value = 0.0
            for start, freq, decay in notes:
                age = t - start
                if age < 0:
                    continue
                envelope = min(age / 0.012, 1) * math.exp(-age / decay)
                envelope *= min(max((duration - t) / 0.08, 0), 1)
                phase = math.tau * freq * age
                if kind == 'bell':
                    tone = math.sin(phase) + 0.20 * math.sin(phase * 2.76) + 0.06 * math.sin(phase * 4.2)
                elif kind == 'keys':
                    tone = math.sin(phase) + 0.25 * math.sin(phase * 2) + 0.09 * math.sin(phase * 3)
                else:
                    tone = math.sin(phase) + 0.25 * math.sin(phase * 3)
                value += envelope * tone
            values.append(value)
        peak = max(abs(value) for value in values)
        data = b''.join(struct.pack('<h', round(value / peak * 0.35 * 32767)) for value in values)
        with wave.open(str(ROOT / f'{name}.wav'), 'wb') as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(data)
        print(f'{name}: {duration}s, {len(data)} bytes PCM')

if __name__ == '__main__':
    generate()
