"""단어 교정 사전 — 사용자 정의 ASR 오인식 교정.

사용자가 반복적으로 틀리는 단어를 {오인식어: 정답어} JSON으로 저장하고
ASR 결과에 정확 치환(exact match)을 적용한다.

- 기본 경로: ~/.config/silenci/corrections.json
- --corrections 옵션으로 다른 경로 지정 가능
- CLI: silence-cutter corrections add|list|remove|clear
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Optional

DEFAULT_PATH = Path.home() / ".config" / "silenci" / "corrections.json"


def load(path: Optional[str | Path] = None) -> dict:
    """{오인식어: 정답어} 사전 로드."""
    p = Path(path) if path else DEFAULT_PATH
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def save(corrections: dict, path: Optional[str | Path] = None) -> None:
    """사전 저장."""
    p = Path(path) if path else DEFAULT_PATH
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        json.dumps(corrections, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def apply(text: str, corrections: dict) -> str:
    """교정 사전을 텍스트에 적용.

    공백 경계 기반 어절 단위 매칭 — 부분 문자열 오치환 방지.
    예) "서과" → "사과" 적용 시 "배서과다" 는 건드리지 않음.
    """
    if not corrections:
        return text
    for wrong, correct in corrections.items():
        text = re.sub(
            r'(?<!\S)' + re.escape(wrong) + r'(?!\S)',
            correct,
            text,
        )
    return text
