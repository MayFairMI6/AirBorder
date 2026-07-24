#!/usr/bin/env python3
"""Deterministic Markdown-to-PDF exporter for Airport XR Companion reports.

The exporter deliberately uses ReportLab's standard fonts and invariant mode so
that identical Markdown and exporter versions produce byte-identical PDFs.  It
also keeps the source Markdown, PDF, and provenance manifest together under a
stable report ID.
"""

from __future__ import annotations

import argparse
import datetime as _datetime
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import textwrap
import unicodedata
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


NOTICE = "Research prototype - simulated or research data."
BRAND = "AIRPORT XR COMPANION"
EXPORTER_VERSION = "1.0"

_REPORT_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_HEADING_RE = re.compile(r"^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$")
_FENCE_RE = re.compile(r"^[ \t]*```([^`]*)$")
_LIST_RE = re.compile(r"^(\s*)([-+*]|\d+[.)])\s+(.+?)\s*$")
_HORIZONTAL_RULE_RE = re.compile(r"^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$")
_TABLE_SEPARATOR_RE = re.compile(r"^:?-{3,}:?$")
_INLINE_RE = re.compile(
    r"\[([^\]\n]+)\]\(([^)\n]+)\)"
    r"|`([^`\n]+)`"
    r"|\*\*([^*\n]+)\*\*"
    r"|__([^_\n]+)__"
    r"|(?<!\*)\*([^*\n]+)\*(?!\*)"
    r"|(?<!_)_([^_\n]+)_(?!_)"
)


class ExportError(RuntimeError):
    """Expected user-facing export failure."""


@dataclass(frozen=True)
class Block:
    kind: str
    text: str = ""
    level: int = 0
    language: str = ""
    items: Tuple[Tuple[int, str, str], ...] = field(default_factory=tuple)
    rows: Tuple[Tuple[str, ...], ...] = field(default_factory=tuple)
    alignments: Tuple[str, ...] = field(default_factory=tuple)


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name("." + path.name + ".tmp")
    try:
        with temporary.open("wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary), str(path))
    finally:
        if temporary.exists():
            temporary.unlink()


def _slugify(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii").lower()
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_value).strip("-")
    return slug or "report"


def _validate_report_id(value: str) -> str:
    if not _REPORT_ID_RE.fullmatch(value):
        raise ExportError(
            "report ID must contain only lowercase letters, digits, and single "
            "hyphens (for example, 2026-07-14-transfer-design)"
        )
    return value


def _canonical_generated_at(value: Optional[str]) -> Optional[str]:
    source = value
    if source is None:
        source = os.environ.get("SOURCE_DATE_EPOCH")
    if source is None or source == "":
        return None

    try:
        if re.fullmatch(r"\d+", source):
            moment = _datetime.datetime.fromtimestamp(
                int(source), tz=_datetime.timezone.utc
            )
        else:
            parsed = source[:-1] + "+00:00" if source.endswith("Z") else source
            moment = _datetime.datetime.fromisoformat(parsed)
            if moment.tzinfo is None:
                raise ValueError("timestamp has no UTC offset")
            moment = moment.astimezone(_datetime.timezone.utc)
    except (OverflowError, OSError, ValueError) as exc:
        raise ExportError(
            "--generated-at (or SOURCE_DATE_EPOCH) must be an epoch integer or "
            "an ISO-8601 timestamp with a UTC offset"
        ) from exc

    return moment.isoformat(timespec="seconds").replace("+00:00", "Z")


def _display_text(value: str) -> str:
    """Keep standard-font text legible and avoid unsupported PDF glyph boxes."""

    replacements = {
        "\u00a0": " ",
        "\u2010": "-",
        "\u2011": "-",
        "\u2012": "-",
        "\u2013": "-",
        "\u2014": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2022": "-",
        "\u2026": "...",
        "\u2192": "->",
        "\u2713": "yes",
        "\u2717": "no",
    }
    for old, new in replacements.items():
        value = value.replace(old, new)
    value = "".join(
        character
        for character in value
        if character in "\t\n" or ord(character) >= 32
    )
    return value.encode("cp1252", "replace").decode("cp1252")


def _plain_inline(value: str) -> str:
    value = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", value)
    value = re.sub(r"[`*_]", "", value)
    return _display_text(value).strip()


def _inline_markup(value: str) -> str:
    value = _display_text(value)
    pieces: List[str] = []
    cursor = 0
    for match in _INLINE_RE.finditer(value):
        pieces.append(html.escape(value[cursor : match.start()], quote=False))
        label, destination, code, bold_star, bold_under, italic_star, italic_under = (
            match.groups()
        )
        if label is not None and destination is not None:
            destination = destination.strip()
            if destination.startswith("<") and destination.endswith(">"):
                destination = destination[1:-1]
            # Ignore an optional Markdown link title while preserving the URL.
            destination = re.split(r"\s+[\"']", destination, maxsplit=1)[0]
            safe_label = html.escape(_display_text(label), quote=False)
            if re.match(r"^(?:https?://|mailto:)", destination, re.IGNORECASE):
                safe_destination = html.escape(destination, quote=True)
                pieces.append(
                    '<link href="{}"><u><font color="#087EA4">{}</font></u></link>'.format(
                        safe_destination, safe_label
                    )
                )
            else:
                pieces.append(safe_label)
        elif code is not None:
            pieces.append(
                '<font name="Courier" color="#19324D">{}</font>'.format(
                    html.escape(code, quote=False)
                )
            )
        elif bold_star is not None or bold_under is not None:
            pieces.append(
                "<b>{}</b>".format(
                    html.escape(bold_star or bold_under or "", quote=False)
                )
            )
        else:
            pieces.append(
                "<i>{}</i>".format(
                    html.escape(italic_star or italic_under or "", quote=False)
                )
            )
        cursor = match.end()
    pieces.append(html.escape(value[cursor:], quote=False))
    return "".join(pieces)


def _split_table_row(line: str) -> Tuple[str, ...]:
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|") and not line.endswith(r"\|"):
        line = line[:-1]

    cells: List[str] = []
    current: List[str] = []
    escaped = False
    for character in line:
        if escaped:
            current.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == "|":
            cells.append("".join(current).strip())
            current = []
        else:
            current.append(character)
    if escaped:
        current.append("\\")
    cells.append("".join(current).strip())
    return tuple(cells)


def _table_alignments(separator: Sequence[str]) -> Optional[Tuple[str, ...]]:
    result: List[str] = []
    for cell in separator:
        compact = re.sub(r"\s+", "", cell)
        if not _TABLE_SEPARATOR_RE.fullmatch(compact):
            return None
        if compact.startswith(":") and compact.endswith(":"):
            result.append("CENTER")
        elif compact.endswith(":"):
            result.append("RIGHT")
        else:
            result.append("LEFT")
    return tuple(result)


def _looks_like_table(lines: Sequence[str], index: int) -> bool:
    if index + 1 >= len(lines) or "|" not in lines[index]:
        return False
    header = _split_table_row(lines[index])
    separator = _split_table_row(lines[index + 1])
    return len(header) > 0 and len(header) == len(separator) and bool(
        _table_alignments(separator)
    )


def _starts_block(lines: Sequence[str], index: int) -> bool:
    line = lines[index]
    return bool(
        not line.strip()
        or _HEADING_RE.match(line)
        or _FENCE_RE.match(line)
        or _LIST_RE.match(line)
        or _HORIZONTAL_RULE_RE.match(line)
        or line.lstrip().startswith(">")
        or _looks_like_table(lines, index)
    )


def _parse_markdown(markdown: str) -> List[Block]:
    markdown = markdown.lstrip("\ufeff")
    lines = markdown.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    blocks: List[Block] = []
    index = 0

    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue

        fence = _FENCE_RE.match(line)
        if fence:
            language = fence.group(1).strip()
            index += 1
            code_lines: List[str] = []
            while index < len(lines) and not re.match(r"^[ \t]*```[ \t]*$", lines[index]):
                code_lines.append(lines[index])
                index += 1
            if index < len(lines):
                index += 1
            blocks.append(Block("code", text="\n".join(code_lines), language=language))
            continue

        heading = _HEADING_RE.match(line)
        if heading:
            blocks.append(
                Block("heading", text=heading.group(2).strip(), level=len(heading.group(1)))
            )
            index += 1
            continue

        if _HORIZONTAL_RULE_RE.match(line):
            blocks.append(Block("rule"))
            index += 1
            continue

        if _looks_like_table(lines, index):
            rows: List[Tuple[str, ...]] = [_split_table_row(lines[index])]
            alignments = _table_alignments(_split_table_row(lines[index + 1])) or ()
            column_count = len(rows[0])
            index += 2
            while index < len(lines) and lines[index].strip() and "|" in lines[index]:
                row = list(_split_table_row(lines[index]))
                row = (row + [""] * column_count)[:column_count]
                rows.append(tuple(row))
                index += 1
            blocks.append(Block("table", rows=tuple(rows), alignments=alignments))
            continue

        list_match = _LIST_RE.match(line)
        if list_match:
            items: List[Tuple[int, str, str]] = []
            while index < len(lines):
                item = _LIST_RE.match(lines[index])
                if not item:
                    break
                spaces, marker, item_text = item.groups()
                level = max(0, len(spaces.expandtabs(4)) // 2)
                rendered_marker = marker[:-1] + "." if marker[0].isdigit() else "-"
                items.append((level, rendered_marker, item_text))
                index += 1
            blocks.append(Block("list", items=tuple(items)))
            continue

        if line.lstrip().startswith(">"):
            quote_lines: List[str] = []
            while index < len(lines) and lines[index].lstrip().startswith(">"):
                quote_lines.append(re.sub(r"^\s*>\s?", "", lines[index]).strip())
                index += 1
            blocks.append(Block("quote", text=" ".join(quote_lines)))
            continue

        paragraph_lines = [line.strip()]
        index += 1
        while index < len(lines) and not _starts_block(lines, index):
            paragraph_lines.append(lines[index].strip())
            index += 1
        blocks.append(Block("paragraph", text=" ".join(paragraph_lines)))

    return blocks


def _document_title(blocks: Iterable[Block], fallback: str) -> str:
    for block in blocks:
        if block.kind == "heading" and block.level == 1:
            return _plain_inline(block.text) or fallback
    return fallback.replace("-", " ").title()


def _column_widths(rows: Sequence[Sequence[str]], available: float) -> List[float]:
    column_count = len(rows[0])
    weights: List[float] = []
    for column in range(column_count):
        longest = max(len(_plain_inline(row[column])) for row in rows)
        weights.append(float(max(6, min(longest + 2, 34))))
    minimum = min(44.0, available / column_count)
    base = minimum * column_count
    if base >= available:
        return [available / column_count] * column_count
    remaining = available - base
    total_weight = sum(weights) or 1.0
    return [minimum + remaining * weight / total_weight for weight in weights]


def _build_pdf(markdown: str, target: Path, report_id: str, title: str) -> None:
    try:
        from reportlab import rl_config
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import letter
        from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
        from reportlab.lib.units import inch
        from reportlab.pdfgen import canvas as reportlab_canvas
        from reportlab.platypus import (
            HRFlowable,
            Paragraph,
            SimpleDocTemplate,
            Spacer,
            Table,
            TableStyle,
        )
    except ImportError as exc:
        raise ExportError(
            "ReportLab is required for PDF export. Install it with "
            "'python3 -m pip install reportlab'."
        ) from exc

    # Invariant mode fixes CreationDate/ModDate and the trailer ID.  Standard
    # fonts avoid platform-dependent font subsetting and embedding order.
    rl_config.invariant = 1

    navy = colors.HexColor("#102A43")
    blue = colors.HexColor("#087EA4")
    cyan = colors.HexColor("#14B8A6")
    ink = colors.HexColor("#243B53")
    muted = colors.HexColor("#627D98")
    pale = colors.HexColor("#EAF6FA")
    pale_gray = colors.HexColor("#F4F7F9")
    border = colors.HexColor("#CBD5E1")
    white = colors.white

    page_width, page_height = letter
    left_margin = 0.72 * inch
    right_margin = 0.72 * inch
    top_margin = 0.78 * inch
    bottom_margin = 0.66 * inch

    class DeterministicCanvas(reportlab_canvas.Canvas):
        def __init__(self, *args: Any, **kwargs: Any) -> None:
            kwargs["invariant"] = 1
            kwargs["pageCompression"] = 1
            super().__init__(*args, **kwargs)
            self.setTitle(_display_text(title))
            self.setAuthor(BRAND.title())
            self.setSubject("Research report")
            self.setCreator("Airport XR Companion deterministic report exporter")
            self.setProducer("Airport XR Companion / ReportLab")
            self.setKeywords("airport, XR, research prototype, decision support")

    def decorate_page(canvas: Any, document: Any) -> None:
        canvas.saveState()
        canvas.setFillColor(navy)
        canvas.roundRect(left_margin, page_height - 33, 12, 12, 2, fill=1, stroke=0)
        canvas.setFillColor(cyan)
        canvas.rect(left_margin + 3, page_height - 30, 6, 6, fill=1, stroke=0)
        canvas.setFont("Helvetica-Bold", 8.5)
        canvas.setFillColor(navy)
        canvas.drawString(left_margin + 18, page_height - 29, BRAND)
        canvas.setFont("Helvetica", 7.5)
        canvas.setFillColor(muted)
        canvas.drawRightString(page_width - right_margin, page_height - 29, "RESEARCH REPORT")
        canvas.setStrokeColor(blue)
        canvas.setLineWidth(0.75)
        canvas.line(left_margin, page_height - 39, page_width - right_margin, page_height - 39)

        canvas.setStrokeColor(border)
        canvas.setLineWidth(0.5)
        canvas.line(left_margin, 34, page_width - right_margin, 34)
        canvas.setFont("Helvetica", 7.25)
        canvas.setFillColor(muted)
        canvas.drawString(left_margin, 22, "Research prototype")
        canvas.drawCentredString(page_width / 2, 22, report_id)
        canvas.drawRightString(
            page_width - right_margin, 22, "Page {}".format(canvas.getPageNumber())
        )
        canvas.restoreState()

    styles = getSampleStyleSheet()
    body = ParagraphStyle(
        "AXR Body",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=9.4,
        leading=13.2,
        textColor=ink,
        spaceAfter=7,
        allowWidows=0,
        allowOrphans=0,
    )
    heading_styles = {
        1: ParagraphStyle(
            "AXR H1",
            parent=body,
            fontName="Helvetica-Bold",
            fontSize=22,
            leading=25,
            textColor=navy,
            spaceBefore=4,
            spaceAfter=12,
            keepWithNext=1,
        ),
        2: ParagraphStyle(
            "AXR H2",
            parent=body,
            fontName="Helvetica-Bold",
            fontSize=14.2,
            leading=17,
            textColor=navy,
            spaceBefore=12,
            spaceAfter=6,
            keepWithNext=1,
        ),
        3: ParagraphStyle(
            "AXR H3",
            parent=body,
            fontName="Helvetica-Bold",
            fontSize=11.3,
            leading=14,
            textColor=blue,
            spaceBefore=9,
            spaceAfter=4,
            keepWithNext=1,
        ),
    }
    for level in range(4, 7):
        heading_styles[level] = ParagraphStyle(
            "AXR H{}".format(level),
            parent=body,
            fontName="Helvetica-Bold",
            fontSize=9.6,
            leading=12.5,
            textColor=navy,
            spaceBefore=7,
            spaceAfter=3,
            keepWithNext=1,
        )
    notice_style = ParagraphStyle(
        "AXR Notice",
        parent=body,
        fontName="Helvetica-Bold",
        fontSize=8.5,
        leading=11.5,
        textColor=navy,
        spaceAfter=0,
    )
    quote_style = ParagraphStyle(
        "AXR Quote",
        parent=body,
        leftIndent=12,
        rightIndent=8,
        textColor=muted,
        fontName="Helvetica-Oblique",
        backColor=pale_gray,
        borderPadding=(7, 8, 7, 10),
        borderColor=blue,
        borderWidth=0.6,
        spaceBefore=2,
        spaceAfter=9,
    )
    table_header = ParagraphStyle(
        "AXR Table Header",
        parent=body,
        fontName="Helvetica-Bold",
        fontSize=7.8,
        leading=10,
        textColor=white,
        spaceAfter=0,
        wordWrap="CJK",
    )
    table_cell = ParagraphStyle(
        "AXR Table Cell",
        parent=body,
        fontSize=7.7,
        leading=10.2,
        spaceAfter=0,
        wordWrap="CJK",
    )
    code_caption = ParagraphStyle(
        "AXR Code Caption",
        parent=body,
        fontName="Helvetica-Bold",
        fontSize=7.3,
        leading=9,
        textColor=blue,
        spaceBefore=3,
        spaceAfter=3,
        keepWithNext=1,
    )
    code_line = ParagraphStyle(
        "AXR Code Line",
        parent=body,
        fontName="Courier",
        fontSize=7.1,
        leading=9.1,
        textColor=navy,
        spaceAfter=0,
        wordWrap="CJK",
    )

    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name("." + target.name + ".tmp")
    if temporary.exists():
        temporary.unlink()

    document = SimpleDocTemplate(
        str(temporary),
        pagesize=letter,
        leftMargin=left_margin,
        rightMargin=right_margin,
        topMargin=top_margin,
        bottomMargin=bottom_margin,
        title=_display_text(title),
        author=BRAND.title(),
        subject="Research report",
        creator="Airport XR Companion deterministic report exporter",
        producer="Airport XR Companion / ReportLab",
        invariant=1,
        pageCompression=1,
        allowSplitting=1,
    )

    story: List[Any] = []
    notice = Table(
        [[Paragraph(html.escape(NOTICE), notice_style)]],
        colWidths=[document.width],
        hAlign="LEFT",
    )
    notice.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), pale),
                ("BOX", (0, 0), (-1, -1), 0.8, blue),
                ("LINEBEFORE", (0, 0), (0, -1), 4, cyan),
                ("LEFTPADDING", (0, 0), (-1, -1), 11),
                ("RIGHTPADDING", (0, 0), (-1, -1), 9),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ]
        )
    )
    story.extend([notice, Spacer(1, 11)])

    for block in _parse_markdown(markdown):
        if block.kind == "heading":
            story.append(Paragraph(_inline_markup(block.text), heading_styles[block.level]))
        elif block.kind == "paragraph":
            story.append(Paragraph(_inline_markup(block.text), body))
        elif block.kind == "quote":
            story.append(Paragraph(_inline_markup(block.text), quote_style))
        elif block.kind == "rule":
            story.append(
                HRFlowable(
                    width="100%",
                    thickness=0.7,
                    color=border,
                    spaceBefore=4,
                    spaceAfter=8,
                )
            )
        elif block.kind == "list":
            for level, marker, item_text in block.items:
                list_style = ParagraphStyle(
                    "AXR List {}".format(level),
                    parent=body,
                    leftIndent=14 + level * 14,
                    bulletIndent=level * 14,
                    firstLineIndent=0,
                    spaceAfter=3,
                )
                story.append(
                    Paragraph(
                        _inline_markup(item_text),
                        list_style,
                        bulletText=html.escape(marker),
                    )
                )
            story.append(Spacer(1, 3))
        elif block.kind == "table":
            table_rows: List[List[Any]] = []
            for row_index, row in enumerate(block.rows):
                style = table_header if row_index == 0 else table_cell
                table_rows.append([Paragraph(_inline_markup(cell), style) for cell in row])
            table = Table(
                table_rows,
                colWidths=_column_widths(block.rows, document.width),
                repeatRows=1,
                splitByRow=1,
                hAlign="LEFT",
            )
            commands: List[Tuple[Any, ...]] = [
                ("BACKGROUND", (0, 0), (-1, 0), navy),
                ("TEXTCOLOR", (0, 0), (-1, 0), white),
                ("GRID", (0, 0), (-1, -1), 0.45, border),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
            for row_index in range(1, len(table_rows)):
                if row_index % 2 == 0:
                    commands.append(("BACKGROUND", (0, row_index), (-1, row_index), pale_gray))
            for column, alignment in enumerate(block.alignments):
                commands.append(("ALIGN", (column, 1), (column, -1), alignment))
            table.setStyle(TableStyle(commands))
            story.extend([table, Spacer(1, 9)])
        elif block.kind == "code":
            if block.language:
                story.append(
                    Paragraph(
                        "CODE - {}".format(html.escape(_display_text(block.language).upper())),
                        code_caption,
                    )
                )
            wrapped_lines: List[str] = []
            wrapper = textwrap.TextWrapper(
                width=92,
                expand_tabs=True,
                tabsize=4,
                replace_whitespace=False,
                drop_whitespace=False,
                break_long_words=True,
                break_on_hyphens=False,
            )
            for original_line in block.text.split("\n"):
                wrapped_lines.extend(wrapper.wrap(original_line) or [""])
            code_rows = []
            for line in wrapped_lines or [""]:
                safe_line = html.escape(_display_text(line), quote=False)
                safe_line = safe_line.replace(" ", "&#160;") or "&#160;"
                code_rows.append([Paragraph(safe_line, code_line)])
            code_table = Table(code_rows, colWidths=[document.width], splitByRow=1, hAlign="LEFT")
            code_commands: List[Tuple[Any, ...]] = [
                ("BACKGROUND", (0, 0), (-1, -1), pale_gray),
                ("BOX", (0, 0), (-1, -1), 0.6, border),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 1),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 1),
            ]
            code_commands.extend(
                [
                    ("TOPPADDING", (0, 0), (-1, 0), 7),
                    ("BOTTOMPADDING", (0, -1), (-1, -1), 7),
                ]
            )
            code_table.setStyle(TableStyle(code_commands))
            story.extend([code_table, Spacer(1, 9)])

    if not story:
        story.append(Paragraph("No report content was provided.", body))

    try:
        document.build(
            story,
            onFirstPage=decorate_page,
            onLaterPages=decorate_page,
            canvasmaker=DeterministicCanvas,
        )
        pdf_bytes = temporary.read_bytes()
        if not pdf_bytes.startswith(b"%PDF-") or b"%%EOF" not in pdf_bytes[-1024:]:
            raise ExportError("ReportLab produced an invalid PDF container")
        os.replace(str(temporary), str(target))
    finally:
        if temporary.exists():
            temporary.unlink()


def _clear_rendered_pages(rendered_dir: Path) -> None:
    if not rendered_dir.exists():
        return
    for path in rendered_dir.glob("page-*.png"):
        if path.is_file():
            path.unlink()
    try:
        rendered_dir.rmdir()
    except OSError:
        pass


def _png_dimensions(path: Path) -> Tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if (
        len(header) != 24
        or header[:8] != b"\x89PNG\r\n\x1a\n"
        or header[12:16] != b"IHDR"
    ):
        raise ExportError("render verification produced an invalid PNG: {}".format(path.name))
    width, height = struct.unpack(">II", header[16:24])
    if width <= 0 or height <= 0:
        raise ExportError("render verification produced an empty PNG: {}".format(path.name))
    return width, height


def _page_number(path: Path) -> int:
    match = re.search(r"-(\d+)\.png$", path.name)
    return int(match.group(1)) if match else sys.maxsize


def _render_check(pdf_path: Path, mode: str, dpi: int) -> Dict[str, Any]:
    rendered_dir = pdf_path.parent / "rendered"
    _clear_rendered_pages(rendered_dir)

    if mode == "off":
        return {"status": "not_requested", "renderer": "pdftoppm"}

    executable = shutil.which("pdftoppm")
    if executable is None:
        if mode == "require":
            raise ExportError(
                "pdftoppm is required by --render-check require but was not found"
            )
        return {
            "status": "unavailable",
            "renderer": "pdftoppm",
            "message": "pdftoppm was not found; visual verification was not performed",
        }

    rendered_dir.mkdir(parents=True, exist_ok=True)
    prefix = rendered_dir / "page"
    completed = subprocess.run(
        [executable, "-png", "-r", str(dpi), str(pdf_path), str(prefix)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().splitlines()
        message = detail[-1] if detail else "unknown pdftoppm error"
        raise ExportError("pdftoppm render verification failed: {}".format(message))

    pages = sorted(rendered_dir.glob("page-*.png"), key=_page_number)
    if not pages:
        raise ExportError("pdftoppm completed without producing any PNG pages")

    page_records = []
    for page in pages:
        width, height = _png_dimensions(page)
        page_records.append(
            {
                "file": "rendered/{}".format(page.name),
                "height_px": height,
                "width_px": width,
            }
        )
    return {
        "status": "passed",
        "renderer": "pdftoppm",
        "dpi": dpi,
        "page_count": len(page_records),
        "pages": page_records,
    }


def _relative_input_label(source: Path, canonical: Path) -> str:
    try:
        return source.resolve().relative_to(canonical.parent.resolve()).as_posix()
    except ValueError:
        # Avoid machine-specific absolute paths in the deterministic manifest.
        return source.name


def export_report(args: argparse.Namespace) -> Tuple[Path, Path, Path, Dict[str, Any]]:
    source = Path(args.input_markdown).expanduser()
    if not source.is_file():
        raise ExportError("input Markdown does not exist or is not a file: {}".format(source))
    try:
        source_bytes = source.read_bytes()
        markdown = source_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ExportError("input Markdown must be UTF-8 encoded") from exc

    requested_id = args.report_id or _slugify(source.stem)
    report_id = _validate_report_id(requested_id)
    generated_at = _canonical_generated_at(args.generated_at)
    output_root = Path(args.output_root).expanduser()
    report_dir = output_root / report_id
    canonical_path = report_dir / (report_id + ".md")
    pdf_path = report_dir / (report_id + ".pdf")
    provenance_path = report_dir / (report_id + ".provenance.json")

    _atomic_write(canonical_path, source_bytes)
    blocks = _parse_markdown(markdown)
    title = _document_title(blocks, report_id)
    _build_pdf(markdown, pdf_path, report_id, title)
    render_record = _render_check(pdf_path, args.render_check, args.render_dpi)

    source_hash = _sha256_bytes(source_bytes)
    canonical_hash = _sha256_file(canonical_path)
    pdf_hash = _sha256_file(pdf_path)
    exporter_path = Path(__file__).resolve()
    exporter_hash = _sha256_file(exporter_path)
    if canonical_hash != source_hash:
        raise ExportError("canonical Markdown copy does not match the original source")

    provenance: Dict[str, Any] = {
        "schema": "airport-xr-companion-report-provenance/v1",
        "exporter_version": EXPORTER_VERSION,
        "report_id": report_id,
        "generated_at": generated_at,
        "notice": NOTICE,
        "artifacts": {
            "original_source": {
                "path": _relative_input_label(source, canonical_path),
                "sha256": source_hash,
            },
            "canonical_source": {
                "path": canonical_path.name,
                "sha256": canonical_hash,
            },
            "pdf": {"path": pdf_path.name, "sha256": pdf_hash},
            "exporter": {"path": exporter_path.name, "sha256": exporter_hash},
        },
        "hashes": {
            "original_source_sha256": source_hash,
            "canonical_source_sha256": canonical_hash,
            "pdf_sha256": pdf_hash,
            "exporter_sha256": exporter_hash,
        },
        "pdf_determinism": {
            "invariant_mode": True,
            "metadata_timestamps": "fixed by ReportLab invariant mode",
            "standard_fonts_only": True,
        },
        "render_verification": render_record,
    }
    manifest_bytes = (
        json.dumps(provenance, indent=2, sort_keys=True, ensure_ascii=True) + "\n"
    ).encode("utf-8")
    _atomic_write(provenance_path, manifest_bytes)
    return canonical_path, pdf_path, provenance_path, provenance


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Export an Airport XR Companion Markdown research report as a "
            "deterministic PDF with a canonical source copy and SHA-256 provenance."
        ),
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("input_markdown", help="UTF-8 Markdown source file")
    parser.add_argument(
        "--output-root",
        default="research_exports/reports",
        help="directory that will contain the stable report-ID folder",
    )
    parser.add_argument(
        "--report-id",
        help="lowercase, hyphenated stable ID; defaults to the source filename slug",
    )
    parser.add_argument(
        "--render-check",
        choices=("off", "auto", "require"),
        default="auto",
        help="render PDF pages with pdftoppm and validate their PNG containers",
    )
    parser.add_argument(
        "--render-dpi",
        type=int,
        default=144,
        help="DPI used for optional pdftoppm render verification",
    )
    parser.add_argument(
        "--generated-at",
        help=(
            "optional ISO-8601 timestamp or Unix epoch recorded in provenance; "
            "SOURCE_DATE_EPOCH is used when this option is omitted"
        ),
    )
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    if args.render_dpi < 36 or args.render_dpi > 600:
        parser.error("--render-dpi must be between 36 and 600")
    try:
        canonical, pdf, provenance, manifest = export_report(args)
    except ExportError as exc:
        print("error: {}".format(exc), file=sys.stderr)
        return 2

    print("Canonical Markdown: {}".format(canonical))
    print("PDF: {}".format(pdf))
    print("Provenance: {}".format(provenance))
    print("Render verification: {}".format(manifest["render_verification"]["status"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
