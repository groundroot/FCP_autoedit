"""화자 분리 (Speaker Diarization)

resemblyzer VoiceEncoder + SpectralClustering 조합.
HuggingFace 토큰 불필요, Apple Silicon CPU 동작.
"""
from __future__ import annotations

import wave
from typing import List, Optional, Tuple

import numpy as np


def _read_wav_float(path: str, file_start: float = 0.0, file_end: float = None,
                    sr: int = 16000) -> np.ndarray:
    """WAV 파일의 지정 구간을 float32[-1,1] 배열로 읽기."""
    with wave.open(path) as w:
        n_channels = w.getnchannels()
        sampwidth = w.getsampwidth()
        framerate = w.getframerate()
        total_frames = w.getnframes()

        start_frame = int(file_start * framerate)
        end_frame = int(file_end * framerate) if file_end is not None else total_frames
        end_frame = min(end_frame, total_frames)
        n_frames = max(0, end_frame - start_frame)

        w.setpos(start_frame)
        raw = w.readframes(n_frames)

    dtype = {1: np.int8, 2: np.int16, 4: np.int32}.get(sampwidth, np.int16)
    arr = np.frombuffer(raw, dtype=dtype).astype(np.float32)
    if sampwidth == 1:
        arr = (arr - 128) / 128.0
    else:
        arr = arr / float(2 ** (8 * sampwidth - 1))

    if n_channels > 1:
        arr = arr.reshape(-1, n_channels).mean(axis=1)

    # resemblyzer 요구 sr=16000
    if framerate != sr:
        try:
            from scipy.signal import resample_poly
            from math import gcd
            g = gcd(sr, framerate)
            arr = resample_poly(arr, sr // g, framerate // g).astype(np.float32)
        except ImportError:
            pass

    return arr


def _best_n_speakers(embeds_norm: np.ndarray, sim: np.ndarray,
                     min_sp: int, max_sp: int) -> int:
    """실루엣 점수로 최적 화자 수 결정."""
    from sklearn.cluster import SpectralClustering
    from sklearn.metrics import silhouette_score

    n_samples = len(embeds_norm)
    best_n, best_score = min_sp, -1.0
    for n in range(min_sp, min(max_sp + 1, n_samples)):
        try:
            labels = SpectralClustering(
                n_clusters=n, affinity="precomputed", random_state=0,
                n_init=10,
            ).fit_predict(np.clip(sim, 0, 1))
            if len(set(labels)) < 2:
                continue
            score = silhouette_score(embeds_norm, labels, metric="cosine")
            if score > best_score:
                best_n, best_score = n, score
        except Exception:
            continue
    return best_n


def diarize_audio(
    wav_path: str,
    file_start: float = 0.0,
    file_end: float = None,
    *,
    num_speakers: Optional[int] = None,
    min_speakers: int = 2,
    max_speakers: int = 4,
    win_sec: float = 1.5,
    step_sec: float = 0.5,
    log=None,
) -> List[Tuple[float, float, int]]:
    """
    오디오 파일의 [file_start, file_end] 구간에서 화자를 분리한다.

    Returns
    -------
    list of (start_sec, end_sec, speaker_id)
        시간은 file_start 기준 절대 초(파일 내 위치).
        speaker_id: 0, 1, 2, ...  (발화량 순으로 재정렬됨)
    """
    def _log(msg):
        if log:
            log(msg)

    try:
        from resemblyzer import VoiceEncoder
        from sklearn.cluster import SpectralClustering
        from sklearn.preprocessing import normalize
    except ImportError as e:
        _log(f"[diarize] 라이브러리 없음, 화자 분리 건너뜀: {e}")
        return []

    wav = _read_wav_float(wav_path, file_start, file_end)
    SR = 16000
    if len(wav) < SR * win_sec:
        _log("[diarize] 오디오 너무 짧음, 화자 분리 건너뜀")
        return []

    enc = VoiceEncoder("cpu")

    win = int(win_sec * SR)
    step = int(step_sec * SR)
    times, embeds = [], []
    for s in range(0, len(wav) - win, step):
        seg = wav[s:s + win]
        if np.abs(seg).max() < 0.015:   # 무음 구간 제외
            continue
        times.append(file_start + s / SR)
        embeds.append(enc.embed_utterance(seg))

    if len(embeds) < max(2, min_speakers):
        _log("[diarize] 임베딩 샘플 부족, 화자 분리 건너뜀")
        return []

    embeds_arr = np.array(embeds)
    emb_n = normalize(embeds_arr)
    sim = np.clip(emb_n @ emb_n.T, 0, 1)

    if num_speakers is not None:
        n = max(min_speakers, min(num_speakers, max_speakers, len(embeds)))
    else:
        n = _best_n_speakers(emb_n, sim, min_speakers, min(max_speakers, len(embeds)))

    _log(f"[diarize] 화자 {n}명으로 분류 (임베딩 {len(embeds)}개)")

    labels = SpectralClustering(
        n_clusters=n, affinity="precomputed", random_state=0, n_init=10,
    ).fit_predict(sim)

    # 발화 시간이 많은 순서로 speaker_id 재정렬 (SPEAKER_0 = 가장 많이 발화)
    counts = {}
    for lbl in labels:
        counts[lbl] = counts.get(lbl, 0) + 1
    rank = {orig: new for new, (orig, _) in
            enumerate(sorted(counts.items(), key=lambda x: -x[1]))}
    labels = [rank[l] for l in labels]

    # 윈도우 레이블 → 구간 병합 (같은 화자 연속이면 합치기)
    segments: List[Tuple[float, float, int]] = []
    seg_start = times[0]
    seg_spk = labels[0]
    for t, lbl in zip(times[1:], labels[1:]):
        if lbl != seg_spk:
            segments.append((seg_start, t, seg_spk))
            seg_start, seg_spk = t, lbl
    segments.append((seg_start, times[-1] + step_sec, seg_spk))

    _log(f"[diarize] 화자 구간 {len(segments)}개 감지")
    return segments


def assign_speaker(chunk_start: float, chunk_end: float,
                   diar_segs: List[Tuple[float, float, int]]) -> Optional[int]:
    """자막 chunk 시간 범위의 지배적 화자 ID 반환. 겹침 없으면 None."""
    overlap: dict = {}
    for s, e, spk in diar_segs:
        ov = min(chunk_end, e) - max(chunk_start, s)
        if ov > 0:
            overlap[spk] = overlap.get(spk, 0.0) + ov
    if not overlap:
        return None
    return max(overlap, key=overlap.get)


def speaker_role_name(speaker_id: Optional[int]) -> Optional[str]:
    """speaker_id → FCP role 이름 (Dialogue 서브롤)."""
    if speaker_id is None:
        return None
    return f"Dialogue.화자{speaker_id + 1}"
