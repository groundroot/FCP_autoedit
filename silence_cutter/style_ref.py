"""스타일 참조 폴더 — 기존 자막 파일에서 어휘·문체 학습.

특정 폴더의 FCPXML / SRT / TXT 자막 파일들을 스캔해
도메인 특화 어휘 세트를 추출한다.
이 어휘 세트를 retranscribe 파이프라인의 script_terms에 주입하면
인명·지명·전문어 등 반복 등장 고유명사의 인식 정확도가 높아진다.

지원 입력:
  .fcpxml / .fcpxmld 번들 내 Info.fcpxml — caption/title 텍스트
  .srt                                   — 자막 텍스트
  .txt / .md                             — 일반 텍스트
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Callable, Optional


def _tokens(text: str) -> set:
    """2자 이상 한국어/영문/숫자 토큰 집합."""
    return {t for t in re.findall(r'[가-힣A-Za-z0-9]+', text) if len(t) >= 2}


def _from_fcpxml(path: Path) -> set:
    """FCPXML에서 caption/title 텍스트 어휘 추출."""
    try:
        root = ET.parse(str(path)).getroot()
        vocab: set = set()
        for ts in root.iter("text-style"):
            if ts.text:
                vocab |= _tokens(ts.text)
        return vocab
    except Exception:
        return set()


def _from_srt(path: Path) -> set:
    """SRT 자막 파일에서 어휘 추출."""
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
        # 줄번호·타임코드 제거
        text = re.sub(r'^\d+\s*$', '', text, flags=re.MULTILINE)
        text = re.sub(
            r'\d{2}:\d{2}:\d{2}[,\.]\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}[,\.]\d{3}',
            '', text,
        )
        return _tokens(text)
    except Exception:
        return set()


def _from_text(path: Path) -> set:
    """일반 텍스트/마크다운 파일에서 어휘 추출."""
    try:
        return _tokens(path.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return set()


def load_style_ref_dir(
    folder: str | Path,
    *,
    log: Optional[Callable[[str], None]] = None,
) -> set:
    """폴더 내 자막/텍스트 파일에서 어휘 세트 추출.

    반환값은 retranscribe() 의 script_terms 에 그대로 병합 가능.
    재귀 탐색하므로 하위 폴더 구조 무관.
    """
    folder = Path(folder)
    if not folder.is_dir():
        if log:
            log(f"[style_ref] 폴더 없음: {folder}")
        return set()

    vocab: set = set()
    file_count = 0

    for f in folder.rglob("*"):
        if f.name == "Info.fcpxml" or f.suffix == ".fcpxml":
            vocab |= _from_fcpxml(f)
            file_count += 1
        elif f.suffix == ".srt":
            vocab |= _from_srt(f)
            file_count += 1
        elif f.suffix in (".txt", ".md"):
            vocab |= _from_text(f)
            file_count += 1

    if log:
        log(
            f"[style_ref] 참조 파일 {file_count}개 → 어휘 {len(vocab)}개 추출: {folder}"
        )
    return vocab
