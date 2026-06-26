"""편집된 FCPXML을 읽어서 자막만 재생성"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from copy import deepcopy
from fractions import Fraction
from pathlib import Path
from typing import Callable, Optional
from urllib.parse import unquote, urlparse

from .transcribe import Transcriber, TranscribedSegment
from .fcpxml import _snap_to_frame, _rational_str, _split_subtitle, _get_frame_info
from .itt import generate_itt
from .vad import extract_audio, detect_speech, split_long_speech_segments


def _parse_time(s: str) -> float:
    """FCPXML 시간 문자열 → 초 (float)"""
    if s is None:
        return 0.0
    s = s.strip()
    if s.endswith("s"):
        s = s[:-1]
    if "/" in s:
        num, den = s.split("/")
        return int(num) / int(den)
    return float(s)


def _find_source_video(tree: ET.ElementTree) -> Optional[Path]:
    """FCPXML에서 원본 영상 경로 추출"""
    for media_rep in tree.iter("media-rep"):
        src = media_rep.get("src", "")
        if src.startswith("file://"):
            parsed = urlparse(src)
            path = Path(unquote(parsed.path))
            if path.exists():
                return path
    return None


def _parse_time_fraction(s: str) -> "Fraction":
    """FCPXML 시간 문자열 → Fraction (정밀도 보존)"""
    from fractions import Fraction as F
    if s is None:
        return F(0)
    s = s.strip().rstrip("s")
    if "/" in s:
        num, den = s.split("/")
        return F(int(num), int(den))
    return F(s)


def _build_asset_start_map(root: ET.Element) -> "dict[str, Fraction]":
    """asset id → 파일 시작 타임코드(Fraction) 맵 구성"""
    result = {}
    for asset in root.iter("asset"):
        asset_id = asset.get("id")
        if asset_id:
            result[asset_id] = _parse_time_fraction(asset.get("start", "0s"))
    return result


import re as _re

# ── 자막 분할 break point 등급 패턴 ───────────────────────────────────────────
# Grade 3 (종결): 문장이 완전히 끝나는 느낌 → 즉시 분할
_SUB_GRADE3 = _re.compile(
    r'(습니다|합니다|됩니다|겠습니다|셨습니다'
    r'|에요|이에요|예요|네요|겠어요|군요|거든요|죠'
    r'|아요|어요|해요|셔요'
    r'|는데요|인데요|잖아요|니까요|나요|까요'
    r'|니다'
    r'|[.!?。]'
    r')$'
)
# Grade 2 (접속): 다음 카드로 자연스럽게 이어짐
_SUB_GRADE2 = _re.compile(
    r'(고|며|하며|이며'
    r'|서|해서|어서|아서|라서|여서'
    r'|지만|하지만|이지만'
    r'|는데|은데|인데'
    r'|니까|으니까|아니까'
    r'|거든|더니|었더니|았더니'
    r'|면서|으면서'
    r'|[,，]'
    r')$'
)
# Grade 1 (조사 뒤): 마지막 수단
_SUB_GRADE1 = _re.compile(
    r'(을|를|이|가|은|는|에서|에게|으로|로'
    r'|와|과|랑|이랑|도|만|까지|부터|마저|조차'
    r')$'
)
# 단독 조사 단어 자체: 이 단어로 끝내면 조사 홀로 남음 → 분할 불가
_SUB_PARTICLE_ONLY = _re.compile(r'^(은|는|이|가|을|를|에|의|로|와|과|도|만|서|랑)$')


def _sub_rank(word_text: str) -> int:
    if _SUB_GRADE3.search(word_text): return 3
    if _SUB_GRADE2.search(word_text): return 2
    if _SUB_GRADE1.search(word_text): return 1
    return 0


def _split_subtitle_longform(words, *, min_chars: int = 8, max_chars: int = 27):
    """롱폼 영상용 자막 분할 — 의미 단위·호흡 우선, 한 줄(줄바꿈 없음) 8~27자.

    각 Caption의 start/end는 forced-alignment 단어 타임스탬프를 그대로 사용한다
    (글자 수로 시간 재분배하지 않음 — start=첫 단어 시작, end=마지막 단어 끝).

    끊는 기준 (Grade 3 > 2 > 1):
    - Grade 3 (종결어미/구두점): 즉시 분할 (min_chars 이상, overflow 없을 때)
    - Grade 2 (접속어미): overflow 시 선호 경계
    - Grade 1 (조사 뒤): 마지막 수단
    overflow 시 max_chars 이내 후보 우선, 분할 후 i를 tail 첫 단어로 롤백.

    핵심 버그 수정: "습니다"/"합니다" 등 종결어미를 Grade 3 즉시분할로 처리.
    이전 코드는 _CLAUSE_END(last_break만 기록)에 "합니다" 포함 → "하였습니다"
    뒤에 "감사합니다"가 오면 두 단어가 한 자막으로 합쳐지는 오류 발생.
    """
    if not words:
        return []

    def mk(ws):
        return {"text": " ".join(w.text for w in ws),
                "start": ws[0].start, "end": ws[-1].end}

    def head_len(idx):
        return len(" ".join(w.text for w in cur[:idx + 1]))

    from dataclasses import dataclass

    @dataclass
    class _BP:
        index: int
        rank: int

    chunks      = []
    cur         = []
    breaks      = []   # _BP 목록
    cur_start_i = 0    # words[] 내 cur[0]의 전역 인덱스

    i = 0
    n = len(words)
    while i < n:
        w       = words[i]
        is_last = (i == n - 1)
        cur.append(w)
        cur_text = " ".join(x.text for x in cur)
        cur_idx  = len(cur) - 1
        r = _sub_rank(w.text)

        # break point 기록 (단독 조사 단어 자체는 제외)
        if r >= 1 and not _SUB_PARTICLE_ONLY.fullmatch(w.text):
            breaks.append(_BP(index=cur_idx, rank=r))

        # ── 1) 길이 초과 (마지막 단어도 포함) ─────────────────────────────────
        if len(cur_text) >= max_chars:
            nxt = words[i + 1].text if not is_last else ""
            # 다음이 단독 조사면 흡수
            if nxt and _SUB_PARTICLE_ONLY.fullmatch(nxt) and len(cur_text) < max_chars + 4:
                i += 1
                continue

            candidates = [b for b in breaks if head_len(b.index) >= min_chars]
            within = [b for b in candidates if head_len(b.index) <= max_chars]
            over   = [b for b in candidates if head_len(b.index) >  max_chars]

            if within or over:
                pool = within if within else over
                best = max(pool, key=lambda b: (b.rank, b.index))
                if best.index == cur_idx:
                    chunks.append(mk(cur))
                    cur = []; breaks = []; cur_start_i = i + 1
                    i += 1
                    if is_last: break
                    continue
                else:
                    head = cur[:best.index + 1]
                    chunks.append(mk(head))
                    i = cur_start_i + best.index + 1  # tail 첫 단어로 롤백
                    cur = []; breaks = []; cur_start_i = i
                    continue
            else:
                chunks.append(mk(cur))
                cur = []; breaks = []; cur_start_i = i + 1
                i += 1
                if is_last: break
                continue

        # ── 2) 종결어미 + 최소 길이 → 즉시 분할 ──────────────────────────────
        if r == 3 and len(cur_text) >= min_chars:
            chunks.append(mk(cur))
            cur = []; breaks = []; cur_start_i = i + 1
            i += 1
            if is_last: break
            continue

        # ── 3) 마지막 단어, overflow/Grade3 없음 → 종료 ───────────────────────
        if is_last:
            chunks.append(mk(cur))
            cur = []
            break

        i += 1

    if cur:
        chunks.append(mk(cur))

    # 겹침 제거 (정렬 오차로 다음 시작이 이전 종료보다 앞설 때)
    for i in range(1, len(chunks)):
        if chunks[i]["start"] < chunks[i - 1]["end"]:
            chunks[i - 1]["end"] = chunks[i]["start"]
    return chunks


def _split_subtitle_variety(words, *, pause_threshold: float = 0.5, min_chars: int = 4):
    """예능 자막 스타일 분할 — 자막 수 최소화, 완결 발화 단위 카드(로직 2).

    분할 조건:
    1. 단어 사이 침묵 > pause_threshold 초 (큰 호흡·포즈)
    2. Grade 3 종결어미 (있어요, 했습니다, 어요, 네요 등) + min_chars 이상
    글자 수 상한 없음 — 하나의 완결된 발화를 하나의 카드로.
    title(시각 자막)과 caption(자막 트랙) 모두 이 조건에서 분리된다.
    """
    if not words:
        return []

    def mk(ws):
        return {"text": " ".join(w.text for w in ws),
                "start": ws[0].start, "end": ws[-1].end}

    chunks = []
    cur = []

    for w in words:
        if cur:
            gap = w.start - cur[-1].end
            cur_text = " ".join(x.text for x in cur)
            # 조건 1: 큰 침묵 → 이전 구절 확정
            if gap > pause_threshold and len(cur_text) >= min_chars:
                chunks.append(mk(cur))
                cur = []

        cur.append(w)

        # 조건 2: 종결어미 → 현재 구절 확정
        cur_text = " ".join(x.text for x in cur)
        if _SUB_GRADE3.search(w.text) and len(cur_text) >= min_chars:
            chunks.append(mk(cur))
            cur = []

    if cur:
        chunks.append(mk(cur))

    # 겹침 제거
    for i in range(1, len(chunks)):
        if chunks[i]["start"] < chunks[i - 1]["end"]:
            chunks[i - 1]["end"] = chunks[i]["start"]

    return chunks


def _bridge_short_gaps(chunks, max_bridge: float = 0.4):
    """자막 사이 짧은 끊김(≤max_bridge초)만 메움 — 읽기 편하게 하되 실제 음성 타이밍 보존.

    - 단어 정렬로 얻은 각 자막의 start/end는 그대로 둠
    - 다음 자막과의 간격이 max_bridge 이하인 미세 쉼만 이어 붙임(깜빡임 방지)
    - 실제 호흡/침묵(긴 간격)은 공백으로 남겨 발화 타이밍에 충실
    """
    for i in range(len(chunks) - 1):
        gap = chunks[i + 1]["start"] - chunks[i]["end"]
        if 0 < gap <= max_bridge:
            chunks[i]["end"] = chunks[i + 1]["start"]
    return chunks


# Basic Title의 화면 위치 — iTT 캡션과 동일하게 하단에 배치
# FCP 좌표: 중앙 (0,0), +Y 위 / -Y 아래. 1080p에서 -440 ≈ 하단 자막 위치.
_TITLE_POSITION_KEY = "9999/999166631/999166633/1/100/101"
_TITLE_POSITION_VALUE = "0 -440"


def _add_subtitle_elements(clip, text, offset_frac, dur_frac, idx,
                           effect_id, caption_role, font_size,
                           speaker_role=None):
    """asset-clip에 title(lane 1) + caption(lane 2) 자막 요소를 추가.

    title은 Basic Title 기본 위치(화면 중앙) 대신 Position 파라미터로
    하단에 배치하여 iTT 캡션과 같은 위치에 표시되도록 한다.
    speaker_role이 있으면 title에 role 속성을 추가한다 (FCP 타임라인 구분용).
    """
    ts_id = f"rts{idx}"
    title_attrs = {
        "ref": effect_id,
        "lane": "1",
        "offset": _rational_str(offset_frac),
        "name": text[:50],
        "start": "3600s",
        "duration": _rational_str(dur_frac),
    }
    if speaker_role:
        title_attrs["role"] = speaker_role
    title_el = ET.SubElement(clip, "title", title_attrs)
    # Position 파라미터 (param*은 text 앞에 와야 DTD 유효)
    ET.SubElement(title_el, "param", {
        "name": "Position",
        "key": _TITLE_POSITION_KEY,
        "value": _TITLE_POSITION_VALUE,
    })
    text_el = ET.SubElement(title_el, "text")
    ts = ET.SubElement(text_el, "text-style", ref=ts_id)
    ts.text = text
    ts_def = ET.SubElement(title_el, "text-style-def", id=ts_id)
    ET.SubElement(ts_def, "text-style", {
        "font": "Helvetica", "fontSize": str(font_size), "fontColor": "1 1 1 1",
        "bold": "1", "shadowColor": "0 0 0 0.75", "shadowOffset": "3 315",
        "alignment": "center",
    })

    cap_ts_id = f"rcts{idx}"
    caption_el = ET.SubElement(clip, "caption", {
        "lane": "2",
        "offset": _rational_str(offset_frac),
        "name": text[:50],
        "start": "3600s",
        "duration": _rational_str(dur_frac),
        "role": caption_role,
    })
    cap_text_el = ET.SubElement(caption_el, "text", placement="bottom")
    cap_ts = ET.SubElement(cap_text_el, "text-style", ref=cap_ts_id)
    cap_ts.text = text
    cap_ts_def = ET.SubElement(caption_el, "text-style-def", id=cap_ts_id)
    ET.SubElement(cap_ts_def, "text-style", {
        "font": ".AppleSystemUIFont", "fontSize": "13", "fontFace": "Regular",
        "fontColor": "1 1 1 1", "backgroundColor": "0 0 0 1",
    })


def _caption_text(cap_el) -> str:
    """caption 요소에서 자막 텍스트 추출."""
    ts = cap_el.find(".//text-style")
    return (ts.text or "") if ts is not None else ""


def _verify_fcpxml(tree, label, log, *, gap_threshold: float = 0.1,
                   expect_contiguous: bool = True):
    """생성된 FCPXML 자막 검증 — 빈 공간/겹침/줄바꿈/빈 자막/클립 경계 점검.

    caption은 clip에 anchored 되므로 절대 타임라인 위치 =
    clip.offset + (caption.offset - clip.start) 로 계산한다.

    expect_contiguous=False(실제 음성 타이밍 모드)면 자막 사이 빈 공간(침묵)은
    정상으로 보고 오류로 표시하지 않는다 (겹침·줄바꿈·경계이탈만 오류).
    반환: 발견된 문제 메시지 리스트 (없으면 빈 리스트).
    """
    root = tree.getroot()
    caps = []          # (abs_start, abs_end, text)
    boundary_viol = 0  # 클립 경계 이탈

    for clip in root.iter("asset-clip"):
        clip_off = _parse_time(clip.get("offset", "0s"))
        clip_start = _parse_time(clip.get("start", "0s"))
        clip_dur = _parse_time(clip.get("duration", "0s"))
        clip_end_tc = clip_start + clip_dur
        for cap in clip.findall("caption"):
            co = _parse_time(cap.get("offset", "0s"))
            cd = _parse_time(cap.get("duration", "0s"))
            if co < clip_start - 1e-6 or co + cd > clip_end_tc + 1e-6:
                boundary_viol += 1
            abs_s = clip_off + (co - clip_start)
            caps.append((abs_s, abs_s + cd, _caption_text(cap)))

    caps.sort(key=lambda x: x[0])
    issues = []

    if not caps:
        issues.append("caption 0개 (자막 없음)")
        log(f"[검증:{label}] ⚠️ " + " / ".join(issues))
        return issues

    multiline = sum(1 for _, _, t in caps if "\n" in t)
    if multiline:
        issues.append(f"줄바꿈 포함 {multiline}개")
    empty = sum(1 for _, _, t in caps if not t.strip())
    if empty:
        issues.append(f"빈 자막 {empty}개")
    if boundary_viol:
        issues.append(f"클립 경계 이탈 {boundary_viol}개")

    gaps = []
    overlaps = 0
    for i in range(1, len(caps)):
        prev_end = caps[i - 1][1]
        cur_start = caps[i][0]
        if cur_start - prev_end > gap_threshold:
            gaps.append((prev_end, cur_start))
        elif prev_end - cur_start > gap_threshold:
            overlaps += 1
    if overlaps:
        issues.append(f"겹침 {overlaps}개")
    # 연속성을 기대하는 경우(무음제거본)에만 빈 공간을 오류로 취급
    if gaps and expect_contiguous:
        ex = gaps[0]
        issues.append(f"자막 사이 빈 공간 {len(gaps)}개 (예: {ex[0]:.1f}s~{ex[1]:.1f}s)")

    gap_info = f", 발화 사이 침묵 {len(gaps)}곳(정상)" if (gaps and not expect_contiguous) else ""
    if issues:
        log(f"[검증:{label}] ⚠️ 문제 발견 — " + " / ".join(issues))
    else:
        log(f"[검증:{label}] ✓ caption {len(caps)}개, 겹침/줄바꿈/경계이탈 없음 "
            f"(자막 {caps[0][0]:.1f}s~{caps[-1][1]:.1f}s{gap_info})")
    return issues


def _build_silence_removed(tree2, clip_records, audio_path, *,
                           min_silence_sec, pad_ms, seq_fn, seq_fd,
                           effect_id, caption_role, font_size, log):
    """무음 제거 버전(Result 2) 트리 구성.

    각 원본 asset-clip을 음성 구간 단위로 분할해 타임라인을 압축하고,
    자막(caption/title)을 압축된 타임라인 위치로 재배치한다.
    영상·오디오는 함께 이동하며 컷 구조는 clip 분할로 유지된다.
    """
    root2 = tree2.getroot()
    spine2 = root2.find(".//spine")
    clips2 = list(spine2.findall("asset-clip"))

    # 무음 제거용 음성 구간 감지 (gap < min_silence는 유지 = 자연 호흡)
    min_silence_ms = int(min_silence_sec * 1000)
    raw_segs = detect_speech(
        audio_path,
        min_silence_ms=min_silence_ms,
        speech_pad_ms=pad_ms,
    )
    log(f"[silence] 음성 구간 {len(raw_segs)}개 (min_silence={min_silence_sec}s, pad={pad_ms}ms)")

    frame = Fraction(seq_fn, seq_fd)
    def snap(x):
        return _snap_to_frame(x, seq_fn, seq_fd)

    # 스파인 비우고 압축 클립으로 재구성
    for ch in list(spine2):
        spine2.remove(ch)

    cursor = None  # 타임라인 누적 위치(Fraction)
    ts_counter = 0
    total_kept = Fraction(0)

    for rec, clip_tmpl in zip(clip_records, clips2):
        file_start = rec["file_start"]
        file_end = rec["file_end"]
        asset_file_start = rec["asset_file_start"]
        chunks = rec["chunks"]
        if cursor is None:
            cursor = snap(_parse_time(clip_tmpl.get("offset", "0s")))

        # 이 클립 범위 내 음성 구간만, 클립 경계로 클램핑
        segs = [(max(s.start, file_start), min(s.end, file_end))
                for s in raw_segs if s.end > file_start and s.start < file_end]
        segs = [(a, b) for a, b in segs if b - a > 0]
        if not segs:
            continue

        # 템플릿 속성 (자막/효과 제외한 자식 보존용)
        tmpl_attrib = dict(clip_tmpl.attrib)
        tmpl_children = [c for c in list(clip_tmpl)
                         if c.tag not in ("title", "caption")]

        for (a, b) in segs:
            a_s = snap(a)
            b_s = snap(b)
            dur = b_s - a_s
            if dur <= 0:
                continue
            clip_start_tc = asset_file_start + a_s

            new_clip = ET.SubElement(spine2, "asset-clip", {
                **tmpl_attrib,
                "offset": _rational_str(cursor),
                "start": _rational_str(clip_start_tc),
                "duration": _rational_str(dur),
            })
            # 비자막 자식(conform-rate 등) 복사
            import copy as _copy
            for c in tmpl_children:
                new_clip.append(_copy.deepcopy(c))

            clip_end_tc = clip_start_tc + dur

            # 이 구간[a,b]과 겹치는 모든 자막을 잘라서 배치 → 구간 전체를 빈틈없이 덮음
            # (자막이 무음으로 잘린 두 구간에 걸치면 양쪽 클립에 이어서 표시됨)
            pieces = []  # [lo_file, hi_file, text, speaker_role]
            for c in chunks:
                lo = max(a, c["start"])
                hi = min(b, c["end"])
                if hi > lo + 1e-9:
                    pieces.append([lo, hi, c["text"], c.get("speaker_role")])
            pieces.sort(key=lambda p: p[0])

            if pieces:
                # 구간 전체 커버: 첫 조각은 a부터, 각 조각 종료는 다음 시작까지, 마지막은 b까지
                pieces[0][0] = a
                for i in range(len(pieces) - 1):
                    pieces[i][1] = pieces[i + 1][0]
                pieces[-1][1] = b

                for lo, hi, txt, spk_role in pieces:
                    cs_tc = max(clip_start_tc, snap(lo) + asset_file_start)
                    ce_tc = min(clip_end_tc, snap(hi) + asset_file_start)
                    if ce_tc <= cs_tc:
                        ce_tc = min(clip_end_tc, cs_tc + frame)
                    ts_counter += 1
                    _add_subtitle_elements(new_clip, txt, cs_tc, ce_tc - cs_tc,
                                           ts_counter, effect_id, caption_role, font_size,
                                           speaker_role=spk_role)

            cursor += dur
            total_kept += dur

    # 시퀀스 duration을 압축된 총 길이로 갱신
    seq2 = root2.find(".//sequence")
    if seq2 is not None and total_kept > 0:
        seq2.set("duration", _rational_str(total_kept))

    # 프로젝트 이름/UID 차별화 (Result 1과 충돌 방지)
    import uuid as _uuid
    for proj in root2.iter("project"):
        proj.set("uid", str(_uuid.uuid4()).upper())
        pname = proj.get("name") or "Project"
        if "무음제거" not in pname:
            proj.set("name", pname + "_무음제거")
    for event in root2.iter("event"):
        event.set("uid", str(_uuid.uuid4()).upper())

    return tree2, float(total_kept)


def _load_script_terms(script_path) -> set:
    """대본(.md)에서 고유명사 후보 토큰(2자 이상) 집합 추출."""
    import re as _re
    try:
        text = Path(script_path).read_text(encoding="utf-8")
    except OSError:
        return set()
    tokens = _re.findall(r"[가-힣A-Za-z0-9]+", text)
    return {t for t in tokens if len(t) >= 2}


def _correct_with_script(text: str, script_terms: set) -> str:
    """대본 어휘로 보수적 교정 (스펙 4단계).

    실제 발화를 바꾸지 않기 위해 매우 보수적으로만 동작:
    - 길이 3자 이상 토큰
    - 대본에 거의 동일한(유사도 0.85+, 같은 길이) 토큰이 있을 때만 치환
    음성 내용 자체를 바꾸지 않고 오타/표기만 맞추는 용도.
    """
    if not script_terms:
        return text
    import difflib
    out = []
    for tok in text.split():
        if len(tok) >= 3 and tok not in script_terms:
            m = difflib.get_close_matches(tok, script_terms, n=1, cutoff=0.85)
            if m and m[0] != tok and len(m[0]) == len(tok):
                out.append(m[0])
                continue
        out.append(tok)
    return " ".join(out)


def retranscribe(
    fcpxml_path: str | Path,
    output_path: Optional[str | Path] = None,
    *,
    language: str = "Korean",
    asr_model: str = "mlx-community/Qwen3-ASR-1.7B-8bit",
    aligner_model: str = "mlx-community/Qwen3-ForcedAligner-0.6B-8bit",
    font_size: int = 42,
    max_subtitle_chars: int = 28,
    min_subtitle_chars: int = 10,
    fill_gaps: bool = True,
    gap_bridge_sec: float = 0.4,
    script_path: Optional[str | Path] = None,
    remove_silence: bool = True,
    min_silence_sec: float = 0.7,
    silence_pad_ms: int = 100,
    export_itt: bool = False,
    language_code: str = "ko",
    num_speakers: Optional[int] = None,
    subtitle_lines: int = 1,
    subtitle_style: str = "longform",
    variety_pause_threshold: float = 0.5,
    corrections_path: Optional[str | Path] = None,
    style_ref_dir: Optional[str | Path] = None,
    on_progress: Optional[Callable[[str], None]] = None,
) -> Path:
    """
    편집된 FCPXML/FCPXMLD를 읽어서 롱폼용 Caption 자막을 재생성.

    기존 클립/오디오/컷편집/프로젝트 구조는 그대로 두고, 각 asset-clip의 시간
    범위로 ASR을 다시 실행하여 새 자막(title + caption)을 생성합니다.

    - 한 줄(줄바꿈 없음) 18~44자 의미 단위 분할 (롱폼)
    - 자막 사이 빈 구간 제거 (공백 메움)
    - 대본(script_path)이 있으면 보수적 오타/고유명사 교정
    """
    def _log(msg: str) -> None:
        if on_progress:
            on_progress(msg)
        else:
            print(msg)

    fcpxml_path = Path(fcpxml_path)

    # .fcpxmld 번들이면 내부 Info.fcpxml 사용
    if fcpxml_path.is_dir():
        info_path = fcpxml_path / "Info.fcpxml"
        if not info_path.exists():
            raise FileNotFoundError(f"Info.fcpxml을 찾을 수 없습니다: {info_path}")
        xml_path = info_path
    else:
        xml_path = fcpxml_path

    if output_path is None:
        # 출력 폴더: 원본 파일과 같은 위치에 프로젝트명 폴더 생성
        # 예) 김시은.fcpxmld → 김시은/김시은_롱폼자막_공백메움.fcpxmld
        if subtitle_style == "variety":
            suffix = "_예능자막_공백메움" if fill_gaps else "_예능자막"
        else:
            suffix = "_롱폼자막_공백메움" if fill_gaps else "_롱폼자막"
        proj_dir = fcpxml_path.parent / fcpxml_path.stem
        proj_dir.mkdir(parents=True, exist_ok=True)
        output_path = proj_dir / (fcpxml_path.stem + suffix + ".fcpxmld")
    output_path = Path(output_path)

    # 1. FCPXML 파싱
    _log(f"[retranscribe] FCPXML 읽기: {xml_path}")
    tree = ET.parse(str(xml_path))
    root = tree.getroot()

    # 1-b. UID 충돌 방지: 새 프로젝트/이벤트 UID 부여 + 이름에 "_자막" 접미사
    #      (동일 UID의 프로젝트가 라이브러리에 이미 있으면 FCP가 임포트를 건너뜀)
    import uuid as _uuid
    _proj_suffix = "_예능자막" if subtitle_style == "variety" else "_롱폼자막"
    for proj in root.iter("project"):
        proj.set("uid", str(_uuid.uuid4()).upper())
        pname = proj.get("name") or "Project"
        if _proj_suffix not in pname:
            proj.set("name", pname + _proj_suffix)
    for event in root.iter("event"):
        event.set("uid", str(_uuid.uuid4()).upper())
        ename = event.get("name") or "Event"
        if "자막" not in ename:
            event.set("name", ename + " 자막")

    # 1-c. stale 보안 스코프 bookmark 제거 — FCP가 src 경로로 새로 생성하게 함
    #      (NAS/SMB 경로를 가리키는 오래된 bookmark가 import 행/실패를 유발)
    for media_rep in root.iter("media-rep"):
        for bm in list(media_rep.findall("bookmark")):
            media_rep.remove(bm)

    # 2. 원본 영상 찾기
    video_path = _find_source_video(tree)
    if video_path is None:
        raise FileNotFoundError("FCPXML에서 원본 영상 경로를 찾을 수 없습니다.")
    _log(f"[retranscribe] 원본 영상: {video_path}")

    # 3. 오디오 추출
    _log("[retranscribe] 오디오 추출 중...")
    audio_path = extract_audio(video_path)

    # 4. spine에서 asset-clip 목록 추출 + 기존 title 제거
    spine = root.find(".//spine")
    if spine is None:
        raise ValueError("FCPXML에 spine이 없습니다.")

    # effect id 찾기 (기존 title의 ref)
    effect_id = None
    for effect in root.iter("effect"):
        if "Title" in (effect.get("name") or ""):
            effect_id = effect.get("id")
            break

    if effect_id is None:
        # effect가 없으면 추가
        resources = root.find(".//resources")
        effect_id = "r_title"
        ET.SubElement(resources, "effect", {
            "id": effect_id,
            "name": "Basic Title",
            "uid": ".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti",
        })

    # 시퀀스 포맷 정보 가져오기
    sequence = root.find(".//sequence")
    seq_format_id = sequence.get("format")
    fmt_el = None
    for f in root.iter("format"):
        if f.get("id") == seq_format_id:
            fmt_el = f
            break

    if fmt_el is not None:
        fd_str = fmt_el.get("frameDuration", "1001/30000s")
        fd_val = _parse_time(fd_str)
        seq_fn = Fraction(fd_str.rstrip("s")).numerator
        seq_fd = Fraction(fd_str.rstrip("s")).denominator
    else:
        seq_fn, seq_fd = 1001, 30000

    # 5. ASR 준비
    transcriber = Transcriber(
        asr_model=asr_model,
        aligner_model=aligner_model,
        language=language,
    )

    # asset 시작 타임코드 맵 (클립 start에서 빼서 파일 내 실제 위치 계산)
    asset_start_map = _build_asset_start_map(root)

    # 단어 교정 사전 로드 (사용자 정의 오인식어 → 정답어)
    from .corrections import load as _load_corrections, apply as _apply_corrections
    _corrections = _load_corrections(corrections_path)
    if _corrections:
        _log(f"[retranscribe] 교정 사전 {len(_corrections)}개 로드"
             + (f": {corrections_path}" if corrections_path else ""))

    # 대본(.md) 교정 어휘 로드 (선택)
    script_terms = set()
    if script_path:
        script_terms = _load_script_terms(script_path)
        _log(f"[retranscribe] 대본 교정 어휘 {len(script_terms)}개 로드: {script_path}")

    # 스타일 참조 폴더 어휘 로드 — script_terms에 병합
    if style_ref_dir:
        from .style_ref import load_style_ref_dir as _load_style_ref
        ref_vocab = _load_style_ref(style_ref_dir, log=_log)
        script_terms |= ref_vocab

    # 6. 각 asset-clip 처리
    clips = list(spine.findall("asset-clip"))
    _log(f"[retranscribe] 클립 {len(clips)}개 발견")

    ts_counter = 0
    all_transcribed_timeline = []  # iTT용 (타임라인 기준 시간)

    # 기존 caption의 role 속성 보존 (새 caption 생성 시 동일 role 사용)
    caption_role = None
    for clip in clips:
        for cap in clip.findall("caption"):
            r = cap.get("role")
            if r:
                caption_role = r
                break
        if caption_role:
            break
    if caption_role is None:
        caption_role = f"iTT?captionFormat=ITT.{language_code}"

    # Result 2(무음제거)용 깨끗한 트리 사본 (Result 1 자막 추가 전)
    import copy as _copy
    tree2 = _copy.deepcopy(tree) if remove_silence else None

    clip_records = []  # 무음제거 버전 재구성용 클립별 데이터

    # 화자 분리 모듈 (resemblyzer 없으면 None으로 폴백)
    _diarize_fn = None
    _assign_fn = None
    _role_fn = None
    try:
        from .diarize import diarize_audio, assign_speaker, speaker_role_name
        _diarize_fn = diarize_audio
        _assign_fn = assign_speaker
        _role_fn = speaker_role_name
        _log("[diarize] 화자 분리 활성화")
    except ImportError:
        _log("[diarize] resemblyzer 없음, 화자 분리 비활성화")

    for clip_idx, clip in enumerate(clips):
        # 기존 title과 caption 제거
        for title in list(clip.findall("title")):
            clip.remove(title)
        for caption in list(clip.findall("caption")):
            clip.remove(caption)

        # 클립 시간 정보
        timeline_offset = _parse_time(clip.get("offset", "0s"))
        src_start_tc = _parse_time(clip.get("start", "0s"))  # 소스 미디어 타임코드 기준
        clip_dur = _parse_time(clip.get("duration", "0s"))

        # 파일 내 실제 위치 = 클립 타임코드 - 에셋 파일 시작 타임코드
        asset_ref = clip.get("ref", "")
        asset_file_start = asset_start_map.get(asset_ref, 0.0)
        file_start = src_start_tc - asset_file_start
        file_end = file_start + clip_dur

        _log(f"[retranscribe] ({clip_idx + 1}/{len(clips)}) 파일 {file_start:.1f}s ~ {file_end:.1f}s (TC {src_start_tc:.1f}s, 에셋 TC오프셋 {float(asset_file_start):.1f}s)")

        # VAD로 클립 내 음성 구간 감지 후 짧게 분할 (aligner 성능 보장)
        _log("[retranscribe] VAD 음성 구간 감지 중...")
        raw_segs = detect_speech(audio_path)
        # 해당 클립 범위 내 구간만 필터링
        clip_segs = [s for s in raw_segs if s.end > file_start and s.start < file_end]
        # 클립 경계로 클램핑
        for s in clip_segs:
            s.start = max(s.start, file_start)
            s.end = min(s.end, file_end)
        if not clip_segs:
            _log("[retranscribe] 음성 구간 없음, 건너뜀")
            continue
        # 15초 이하로 추가 분할
        clip_segs = split_long_speech_segments(audio_path, clip_segs)
        _log(f"[retranscribe] 음성 구간 {len(clip_segs)}개 → ASR 실행")

        # 각 구간별 ASR 실행 후 단어 취합
        from .transcribe import WordTimestamp
        all_words = []
        full_text_parts = []
        for seg in clip_segs:
            seg_result = transcriber.transcribe_segment(audio_path, seg.start, seg.end)
            if seg_result.text:
                full_text_parts.append(seg_result.text)
                all_words.extend(seg_result.words)

        if not full_text_parts:
            continue

        # iTT용: 파일 위치 → 타임라인 시간으로 변환
        timeline_words = []
        for w in all_words:
            tl_start = timeline_offset + (w.start - file_start)
            tl_end = timeline_offset + (w.end - file_start)
            timeline_words.append(WordTimestamp(text=w.text, start=tl_start, end=tl_end))

        all_transcribed_timeline.append(TranscribedSegment(
            seg_start=timeline_offset,
            seg_end=timeline_offset + clip_dur,
            text=" ".join(full_text_parts),
            words=timeline_words,
        ))

        # 자막 분할 (로직 1: 롱폼 / 로직 2: 예능)
        if all_words:
            if subtitle_style == "variety":
                chunks = _split_subtitle_variety(
                    all_words,
                    pause_threshold=variety_pause_threshold,
                )
            else:
                chunks = _split_subtitle_longform(
                    all_words,
                    min_chars=min_subtitle_chars,
                    max_chars=max_subtitle_chars,
                )
        else:
            chunks = [{"text": " ".join(full_text_parts), "start": file_start, "end": file_end}]

        # 두 줄 자막: 각 chunk 텍스트를 단어 중간에서 나눠 \n 삽입
        if subtitle_lines == 2:
            for ch in chunks:
                words_in_chunk = ch["text"].split()
                if len(words_in_chunk) >= 2:
                    mid = len(words_in_chunk) // 2
                    ch["text"] = " ".join(words_in_chunk[:mid]) + "\n" + " ".join(words_in_chunk[mid:])

        # 1순위: 사용자 교정 사전 (정확 치환 — 오인식어 → 정답어)
        if _corrections:
            for ch in chunks:
                ch["text"] = _apply_corrections(ch["text"], _corrections)

        # 2순위: 대본/스타일참조 기반 보수적 교정 (유사도 매칭)
        if script_terms:
            for ch in chunks:
                ch["text"] = _correct_with_script(ch["text"], script_terms)

        # 화자 분리 → 각 chunk에 speaker_role 부여
        if _diarize_fn is not None:
            diar_segs = _diarize_fn(
                str(audio_path), file_start, file_end,
                num_speakers=num_speakers,
                min_speakers=2, max_speakers=4,
                log=_log,
            )
            for ch in chunks:
                spk_id = _assign_fn(ch["start"], ch["end"], diar_segs)
                ch["speaker_role"] = _role_fn(spk_id)
        else:
            for ch in chunks:
                ch["speaker_role"] = None

        # 무음제거 버전(결과물 2)용 — 단어 정렬 시간 그대로(미가공) 저장.
        # 무음제거본은 클립 교집합 분배로 구간을 빈틈없이 덮으므로 원시 시간을 사용.
        clip_records.append({
            "chunks": [dict(c) for c in chunks],
            "asset_file_start": asset_file_start,
            "file_start": file_start,
            "file_end": file_end,
            "timeline_offset": timeline_offset,
            "clip_dur": clip_dur,
        })

        # 결과물 1 렌더링용 — 실제 발화 타이밍 유지, 짧은 끊김(미세 쉼)만 메움.
        # 긴 호흡/침묵은 공백으로 남겨 음성에 충실 (글자수 기반 재분배 안 함).
        if fill_gaps:
            _bridge_short_gaps(chunks, max_bridge=gap_bridge_sec)

        # 클립 경계 (파일 위치 기준)
        clip_src_start = _snap_to_frame(file_start, seq_fn, seq_fd)
        clip_src_end = _snap_to_frame(file_end, seq_fn, seq_fd)

        for chunk in chunks:
            ts_counter += 1

            chunk_start = _snap_to_frame(chunk["start"], seq_fn, seq_fd)
            chunk_end = _snap_to_frame(chunk["end"], seq_fn, seq_fd)

            # 클립 경계를 넘지 않도록 클램핑
            if chunk_start < clip_src_start:
                chunk_start = clip_src_start
            if chunk_end > clip_src_end:
                chunk_end = clip_src_end

            chunk_dur = chunk_end - chunk_start
            if chunk_dur <= 0:
                chunk_dur = Fraction(seq_fn, seq_fd)

            # 파일 위치 → FCPXML 타임코드 변환 (에셋 시작 TC 더하기)
            chunk_tc_start = chunk_start + asset_file_start
            _add_subtitle_elements(clip, chunk["text"], chunk_tc_start, chunk_dur,
                                   ts_counter, effect_id, caption_role, font_size,
                                   speaker_role=chunk.get("speaker_role"))

    # 7. 저장 헬퍼
    def _save_tree(tree_obj, out_path: Path) -> None:
        ET.indent(tree_obj, space="    ")

        def _write_xml(p: Path) -> None:
            with open(p, "wb") as f:
                f.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
                f.write(b'<!DOCTYPE fcpxml>\n')
                tree_obj.write(f, encoding="UTF-8", xml_declaration=False)

        # .fcpxmld는 번들(디렉토리); Import > XML용 평면 .fcpxml도 함께 출력
        if out_path.suffix == ".fcpxmld":
            out_path.mkdir(parents=True, exist_ok=True)
            _write_xml(out_path / "Info.fcpxml")
            flat_path = out_path.with_suffix(".fcpxml")
            _write_xml(flat_path)
            _log(f"[retranscribe] 평면 파일도 생성: {flat_path}")
        else:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            _write_xml(out_path)

    # 결과물 1: 롱폼자막_공백메움
    _save_tree(tree, output_path)
    _log(f"[retranscribe] 결과물 1 완료! → {output_path}")
    _verify_fcpxml(tree, "결과물1 공백메움", _log, expect_contiguous=False)

    # 클립 총 길이 계산 (결과 요약용)
    total_clip_sec = sum(r["clip_dur"] for r in clip_records) if clip_records else 0.0

    def _fmt(sec: float) -> str:
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = sec % 60
        if h:
            return f"{h}시간 {m}분 {s:.1f}초"
        return f"{m}분 {s:.1f}초"

    # 결과물 2: 롱폼자막_공백메움_무음제거
    kept_sec = None
    if remove_silence and tree2 is not None and clip_records:
        _log("[retranscribe] 무음제거 버전 생성 중...")
        tree2, kept_sec = _build_silence_removed(
            tree2, clip_records, audio_path,
            min_silence_sec=min_silence_sec, pad_ms=silence_pad_ms,
            seq_fn=seq_fn, seq_fd=seq_fd,
            effect_id=effect_id, caption_role=caption_role, font_size=font_size,
            log=_log,
        )
        # 출력 파일명: ..._무음제거.fcpxmld
        stem = output_path.stem  # 예: 김시은_롱폼자막_공백메움
        output_path2 = output_path.parent / (stem + "_무음제거.fcpxmld")
        _save_tree(tree2, output_path2)
        _log(f"[retranscribe] 결과물 2 완료! ({kept_sec:.1f}s 유지) → {output_path2}")
        _verify_fcpxml(tree2, "결과물2 무음제거", _log)

    # 최종 요약
    _log("")
    _log("=" * 52)
    _log("  작업 완료 요약")
    _log("=" * 52)
    _log(f"  원본 클립 길이  : {_fmt(total_clip_sec)}  ({total_clip_sec:.1f}s)")
    if kept_sec is not None:
        cut_sec = total_clip_sec - kept_sec
        ratio = cut_sec / total_clip_sec * 100 if total_clip_sec else 0
        _log(f"  잘라낸 분량     : {_fmt(cut_sec)}  ({cut_sec:.1f}s, {ratio:.1f}%)")
        _log(f"  최종 분량(무음제거): {_fmt(kept_sec)}  ({kept_sec:.1f}s)")
    else:
        _log("  무음제거        : 생략")
    _log("=" * 52)

    # iTT 생성
    if export_itt and all_transcribed_timeline:
        itt_path = output_path.with_suffix(".itt")
        _log("[retranscribe] iTT 자막 생성 중...")
        generate_itt(
            segments=all_transcribed_timeline,
            output_path=itt_path,
            language=language_code,
            max_subtitle_chars=max_subtitle_chars,
        )
        _log(f"[retranscribe] iTT → {itt_path}")

    # 임시 오디오 정리
    try:
        audio_path.unlink()
    except OSError:
        pass

    return output_path
