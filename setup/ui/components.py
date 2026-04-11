from __future__ import annotations

import curses
import re
import textwrap
from typing import Iterable


BACK = "__back__"


def _safe_addstr(stdscr: curses.window, y: int, x: int, text: str, attr: int = 0) -> None:
    height, width = stdscr.getmaxyx()
    if y < 0 or y >= height or x >= width:
        return
    clipped = text[: max(0, width - x - 1)]
    stdscr.addstr(y, x, clipped, attr)


class WizardUI:
    def __init__(self, stdscr: curses.window) -> None:
        self.stdscr = stdscr
        curses.curs_set(0)
        stdscr.keypad(True)
        stdscr.nodelay(False)
        curses.start_color()
        curses.use_default_colors()
        curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
        curses.mouseinterval(0)
        self.step_index = 0
        self.step_total = 0
        self.cursor_memory: dict[tuple[str, str, tuple[str, ...]], int] = {}
        self.palette = self._init_palette()

    def _menu_memory_key(self, kind: str, title: str, option_values: Iterable[str]) -> tuple[str, str, tuple[str, ...]]:
        return (kind, title, tuple(option_values))

    def _remember_cursor(self, kind: str, title: str, option_values: Iterable[str], index: int) -> None:
        self.cursor_memory[self._menu_memory_key(kind, title, option_values)] = index

    def _restore_cursor(self, kind: str, title: str, option_values: Iterable[str], default: int = 0) -> int:
        key = self._menu_memory_key(kind, title, option_values)
        index = self.cursor_memory.get(key, default)
        max_index = max(0, len(tuple(option_values)) - 1)
        return max(0, min(index, max_index))

    def _init_palette(self) -> dict[str, int]:
        palette = {
            "title": curses.A_BOLD,
            "subtitle": curses.A_DIM,
            "footer": curses.A_DIM,
            "active": curses.A_BOLD,
            "label": curses.A_NORMAL,
            "status": curses.A_BOLD,
            "status_active": curses.A_BOLD,
            "preview": curses.A_DIM,
            "marker_on": curses.A_BOLD,
            "marker_off": curses.A_DIM,
            "cursor": curses.A_BOLD,
            "prompt": curses.A_BOLD,
            "input": curses.A_BOLD,
            "summary_key": curses.A_BOLD,
            "summary_value": curses.A_NORMAL,
            "choice_yes": curses.A_BOLD,
            "choice_no": curses.A_BOLD,
            "selected_badge": curses.A_BOLD,
            "footer_key": curses.A_BOLD,
            "warning": curses.A_BOLD,
            "recommendation": curses.A_BOLD,
            "success": curses.A_BOLD,
        }
        if not curses.has_colors():
            return palette

        curses.init_pair(1, curses.COLOR_CYAN, -1)
        curses.init_pair(2, curses.COLOR_WHITE, -1)
        curses.init_pair(3, curses.COLOR_YELLOW, -1)
        curses.init_pair(4, curses.COLOR_GREEN, -1)
        curses.init_pair(5, curses.COLOR_BLUE, -1)
        curses.init_pair(6, curses.COLOR_MAGENTA, -1)

        palette["title"] = curses.color_pair(1) | curses.A_BOLD
        palette["subtitle"] = curses.color_pair(2) | curses.A_DIM
        palette["footer"] = curses.color_pair(5) | curses.A_DIM
        palette["label"] = curses.color_pair(2)
        palette["status"] = curses.color_pair(6) | curses.A_BOLD
        palette["status_active"] = curses.color_pair(4) | curses.A_BOLD
        palette["preview"] = curses.color_pair(1)
        palette["marker_on"] = curses.color_pair(4) | curses.A_BOLD
        palette["marker_off"] = curses.color_pair(2) | curses.A_DIM
        palette["active"] = curses.color_pair(1) | curses.A_BOLD
        palette["cursor"] = curses.color_pair(2) | curses.A_BOLD
        palette["prompt"] = curses.color_pair(3) | curses.A_BOLD
        palette["input"] = curses.color_pair(4) | curses.A_BOLD
        palette["summary_key"] = curses.color_pair(3) | curses.A_BOLD
        palette["summary_value"] = curses.color_pair(2)
        palette["choice_yes"] = curses.color_pair(4) | curses.A_BOLD
        palette["choice_no"] = curses.color_pair(3) | curses.A_BOLD
        palette["selected_badge"] = curses.color_pair(6) | curses.A_BOLD
        palette["footer_key"] = curses.color_pair(1) | curses.A_BOLD
        palette["warning"] = curses.color_pair(3) | curses.A_BOLD
        palette["recommendation"] = curses.color_pair(1) | curses.A_BOLD
        palette["success"] = curses.color_pair(4) | curses.A_BOLD
        return palette

    def _draw_segments(self, y: int, x: int, segments: list[tuple[str, int]]) -> None:
        _height, width = self.stdscr.getmaxyx()
        cur_x = x
        for text, attr in segments:
            if cur_x >= width - 1:
                break
            clipped = text[: max(0, width - cur_x - 1)]
            if clipped:
                _safe_addstr(self.stdscr, y, cur_x, clipped, attr)
                cur_x += len(clipped)

    def _status_attr_for_text(self, text: str, active: bool = False) -> int:
        if active:
            return self.palette["active"]
        normalized = text.strip().lower()
        if not normalized:
            return self.palette["status"]
        if "driver" in normalized:
            return self.palette["status"]
        positive_tokens = ("yes", "enable", "enabled", "install", "installed", "on", "true")
        negative_tokens = ("no", "disable", "disabled", "skip", "off", "false")
        if any(token in normalized for token in positive_tokens):
            return self.palette["choice_yes"]
        if any(token in normalized for token in negative_tokens):
            return self.palette["choice_no"]
        return self.palette["status"]

    def _status_segments(self, text: str, active: bool = False) -> list[tuple[str, int]]:
        if not text:
            return []
        if active:
            return [(text, self.palette["active"])]
        default_attr = self.palette["status"]
        if "driver" in text.lower():
            return [(text, default_attr)]
        segments: list[tuple[str, int]] = []
        for token in re.split(r"(\s+|\||,)", text):
            if token == "":
                continue
            stripped = token.strip().lower()
            if stripped in {"yes", "enable", "enabled", "install", "installed", "on", "true"}:
                attr = self.palette["choice_yes"]
            elif stripped in {"no", "disable", "disabled", "skip", "off", "false"}:
                attr = self.palette["choice_no"]
            elif token in {"|", ","}:
                attr = self.palette["subtitle"]
            else:
                attr = default_attr
            segments.append((token, attr))
        return segments

    def _secondary_status_attr(self, text: str, active: bool = False) -> int:
        if active:
            return self.palette["active"]
        normalized = text.strip().lower()
        if normalized == "installed":
            return self.palette["choice_yes"]
        if normalized == "not installed":
            return self.palette["choice_no"]
        if normalized == "custom command":
            return self.palette["status"]
        return self.palette["status"]

    def draw_choice_rows(
        self,
        row: int,
        options: list[tuple[str, str, bool, str]],
        selected_index: int = 0,
        mode: str = "radio",
    ) -> int:
        base_x = 4
        _height, width = self.stdscr.getmaxyx()
        available = max(16, width - base_x - 1)
        max_label = max((len(label) for _value, label, _checked, _secondary in options), default=12)
        max_secondary = max((len(secondary) for _value, _label, _checked, secondary in options), default=0)
        gap = 3
        marker_prefix_width = 4
        label_width = min(max_label + 2, max(16, available - max_secondary - gap - marker_prefix_width))
        secondary_x = base_x + marker_prefix_width + label_width + gap
        if mode == "checkbox":
            badge_width = 10
            label_width = min(max_label + 2, max(16, available - badge_width - gap - max_secondary))
            badge_x = base_x + 2 + 4 + 1 + label_width + gap
            secondary_x = badge_x + badge_width + gap
        current_row = row
        for index, (value, label, checked, secondary) in enumerate(options):
            active = index == selected_index
            cursor = ">" if active else " "
            marker = "●" if mode == "radio" and checked else "○" if mode == "radio" else "[✓]" if checked else "[ ]"
            marker_attr = self.palette["marker_on"] if checked else self.palette["marker_off"]
            label_attr = self.palette["active"] if active else self.palette["label"]
            extra_attr = self.palette["active"] if active else self.palette["selected_badge"]
            extra = ""
            if value in {"yes", "y"}:
                label_attr = self.palette["active"] if active else self.palette["choice_yes"]
                extra_attr = self.palette["label"] if active else self.palette["choice_yes"]
            elif value in {"no", "n"}:
                label_attr = self.palette["active"] if active else self.palette["choice_no"]
                extra_attr = self.palette["label"] if active else self.palette["choice_no"]
            if mode == "checkbox" and checked:
                extra = " selected"
            _safe_addstr(self.stdscr, current_row, base_x, " " * max(0, width - base_x - 1), 0)
            if mode == "checkbox":
                self._draw_segments(
                    current_row,
                    base_x,
                    [
                        (cursor, self.palette["active"] if active else self.palette["cursor"]),
                        (" ", self.palette["label"]),
                        (marker, self.palette["active"] if active else marker_attr),
                        (" ", self.palette["label"]),
                        (self._truncate(label, label_width - 1).ljust(label_width), label_attr),
                    ],
                )
                if extra:
                    _safe_addstr(self.stdscr, current_row, badge_x, extra.strip(), extra_attr)
                if secondary:
                    _safe_addstr(
                        self.stdscr,
                        current_row,
                        secondary_x,
                        self._truncate(secondary, max(8, width - secondary_x - 1)),
                        self._secondary_status_attr(secondary, active),
                    )
            else:
                self._draw_segments(
                    current_row,
                    base_x,
                    [
                        (cursor, self.palette["active"] if active else self.palette["cursor"]),
                        (" ", self.palette["label"]),
                        (marker, self.palette["active"] if active else marker_attr),
                        (" ", self.palette["label"]),
                        (self._truncate(label, label_width - 1).ljust(label_width), label_attr),
                        (extra, extra_attr if extra else label_attr),
                    ],
                )
                if secondary:
                    _safe_addstr(
                        self.stdscr,
                        current_row,
                        secondary_x,
                        self._truncate(secondary, max(8, width - secondary_x - 1)),
                        self._secondary_status_attr(secondary, active),
                    )
            current_row += 1
        return current_row

    def draw_summary_lines(self, row: int, lines: list[str]) -> int:
        for line in lines:
            if ":" in line:
                key, value = line.split(":", 1)
                self._draw_segments(
                    row,
                    4,
                    [
                        (f"{key}:", self.palette["summary_key"]),
                        (" ", self.palette["label"]),
                        (value.strip(), self.palette["summary_value"]),
                    ],
                )
            else:
                _safe_addstr(self.stdscr, row, 4, line, self.palette["summary_value"])
            row += 1
        return row

    def set_step(self, index: int, total: int) -> None:
        self.step_index = index
        self.step_total = total

    def clear(self) -> None:
        self.stdscr.erase()

    def refresh(self) -> None:
        self.stdscr.refresh()

    def draw_header(self) -> int:
        _height, width = self.stdscr.getmaxyx()
        progress = f"Step {self.step_index}/{self.step_total}" if self.step_total else ""
        if progress:
            _safe_addstr(self.stdscr, 1, max(2, width - len(progress) - 3), progress, self.palette["subtitle"])
        return 3

    def draw_step_title(self, row: int, title: str, subtitle: str | None = None) -> int:
        _safe_addstr(self.stdscr, row, 2, title, self.palette["title"])
        row += 2
        if subtitle:
            _safe_addstr(self.stdscr, row, 2, subtitle, self.palette["subtitle"])
            row += 2
        return row

    def draw_footer(self, text: str) -> None:
        height, _width = self.stdscr.getmaxyx()
        segments: list[tuple[str, int]] = []
        parts = text.split(" • ")
        key_patterns = [
            "Y/N",
            "▲/▼",
            "◀",
            "▶",
            "↑/↓",
            "←",
            "→",
            "Arrows",
            "Enter",
            "Esc",
            "Ctrl+C",
            "Space/Enter",
            "Space",
            "D",
            "Backspace",
        ]
        for idx, part in enumerate(parts):
            matched = False
            for key_text in key_patterns:
                if part.startswith(key_text):
                    segments.append((key_text, self.palette["footer_key"]))
                    remainder = part[len(key_text):]
                    if remainder:
                        segments.append((remainder, self.palette["footer"]))
                    matched = True
                    break
            if not matched:
                segments.append((part, self.palette["footer"]))
            if idx < len(parts) - 1:
                segments.append((" • ", self.palette["subtitle"]))
        self._draw_segments(height - 2, 2, segments)

    def draw_detail_block(self, row: int, title: str, detail: str | None) -> None:
        if not detail:
            return
        _height, width = self.stdscr.getmaxyx()
        wrap_width = max(24, width - 8)
        _safe_addstr(self.stdscr, row, 2, title, self.palette["summary_key"])
        keyed_prefixes = {
            "Package",
            "Packages",
            "Core Packages",
            "Additional Packages",
            "Available Packages",
            "Primary Packages",
            "Package Scope",
            "Detected Hardware",
            "Selected Packages",
            "Detected Status",
            "Detected Current Session",
            "Desktop Sessions",
            "Custom Packages",
            "Driver Categories",
            "Replacement Bootloader",
            "Bootloader Action",
            "Plymouth Action",
            "Install Profile",
        }
        rendered_lines: list[tuple[str, str]] = []
        for paragraph in detail.splitlines():
            if not paragraph.strip():
                rendered_lines.append(("", "blank"))
                continue
            line_type = "body"
            prefix = paragraph.split(":", 1)[0].strip() if ":" in paragraph else ""
            if prefix in keyed_prefixes:
                line_type = "keyed"
            for wrapped in textwrap.wrap(paragraph, width=wrap_width) or [""]:
                rendered_lines.append((wrapped, line_type))
        for offset, (line, line_type) in enumerate(rendered_lines, start=1):
            if line_type == "blank":
                continue
            if line_type == "keyed" and ":" in line:
                key, value = line.split(":", 1)
                self._draw_segments(
                    row + offset,
                    4,
                    [
                        (f"{key}:", self.palette["summary_key"]),
                        (" ", self.palette["label"]),
                        (value.strip(), self.palette["preview"]),
                    ],
                )
            else:
                _safe_addstr(self.stdscr, row + offset, 4, line, self.palette["summary_value"])

    def _section_lines(self, heading: str, items: list[str], empty_text: str, attr: int) -> list[tuple[str, int]]:
        lines: list[tuple[str, int]] = [(heading, self.palette["summary_key"])]
        if not items:
            lines.append((f"  - {empty_text}", self.palette["subtitle"]))
            return lines
        for item in items:
            lines.append((f"  - {item}", attr))
        return lines

    def _fit_review_lines(self, sections: list[tuple[str, int]]) -> list[tuple[str, int]]:
        height, _width = self.stdscr.getmaxyx()
        max_lines = max(8, height - 12)
        if len(sections) <= max_lines:
            return sections
        trimmed = sections[: max_lines - 1]
        hidden = len(sections) - len(trimmed)
        trimmed.append((f"  ... {hidden} More Line(s)", self.palette["subtitle"]))
        return trimmed

    def _normalize_choice_option(self, option: tuple) -> tuple[str, str, str, str]:
        if len(option) >= 4:
            return option[0], option[1], option[2], option[3]
        if len(option) == 3:
            return option[0], option[1], option[2], ""
        return option[0], option[1], "", ""

    def _normalize_menu_option(self, option: tuple) -> tuple[str, str, str, str, str]:
        if len(option) >= 5:
            return option[0], option[1], option[2], option[3], option[4]
        if len(option) == 4:
            value, label, status, preview = option
            detail_parts = [part for part in [status, preview] if part]
            return value, label, status, preview, " | ".join(detail_parts)
        if len(option) == 3:
            value, label, status = option
            return value, label, status, "", status
        value, label = option[0], option[1]
        return value, label, "", "", ""

    def draw_welcome_logo(self, start_row: int = 2) -> int:
        logo = [
            "     █████╗ ██████╗  ██████╗████████╗██╗   ██╗██╗  ██╗",
            "    ██╔══██╗██╔══██╗██╔════╝╚══██╔══╝╚██╗ ██╔╝╚██╗██╔╝",
            "    ███████║██████╔╝██║        ██║    ╚████╔╝  ╚███╔╝ ",
            "    ██╔══██║██╔══██╗██║        ██║     ╚██╔╝   ██╔██╗ ",
            "    ██║  ██║██║  ██║╚██████╗   ██║      ██║   ██╔╝ ██╗",
            "    ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝",
        ]
        row = start_row
        for line in logo:
            _safe_addstr(self.stdscr, row, 2, line, self.palette["title"])
            row += 1
        row += 1
        _safe_addstr(self.stdscr, row, 3, "A modern, modular system setup tool", self.palette["subtitle"])
        row += 2
        _safe_addstr(self.stdscr, row, 3, "→ Clean setup", self.palette["preview"])
        row += 1
        _safe_addstr(self.stdscr, row, 3, "→ Full control", self.palette["preview"])
        return row + 2

    def _truncate(self, text: str, width: int) -> str:
        if width <= 0:
            return ""
        if len(text) <= width:
            return text
        if width <= 1:
            return text[:width]
        return text[: width - 1] + "…"

    def draw_menu_rows(
        self,
        row: int,
        options: list[tuple[str, str, str]],
        selected_index: int = 0,
    ) -> None:
        _height, width = self.stdscr.getmaxyx()
        available = max(24, width - 8)
        max_label = max((len(label) for label, _, _ in options), default=12)
        max_status = max((len(status) for _, status, _ in options), default=0)
        gap = 3
        marker_width = 2

        label_floor = 16
        label_cap = min(32, max(label_floor, (available - marker_width) // 3))
        label_width = min(max_label + 2, label_cap)
        status_width = max_status + 2
        status_width = min(status_width, max(0, available - marker_width - label_floor - gap))
        status_width = max(0, status_width)

        base_x = 4
        label_x = base_x + marker_width
        status_x = label_x + label_width + gap

        for index, (label, status, preview) in enumerate(options):
            active = index == selected_index
            cursor = ">" if active else " "
            label_attr = self.palette["active"] if active else self.palette["label"]
            status_attr = self._status_attr_for_text(status, active=active)
            cursor_attr = self.palette["active"] if active else self.palette["cursor"]

            _safe_addstr(self.stdscr, row + index, base_x, " " * max(0, width - base_x - 1), 0)
            _safe_addstr(self.stdscr, row + index, base_x, cursor, cursor_attr)
            _safe_addstr(self.stdscr, row + index, label_x, self._truncate(label, label_width - 1).ljust(label_width), label_attr)
            if status_width > 0:
                clipped_status = self._truncate(status, status_width - 1)
                self._draw_segments(row + index, status_x, self._status_segments(clipped_status, active=active))
                if len(clipped_status) < status_width:
                    _safe_addstr(self.stdscr, row + index, status_x + len(clipped_status), " " * (status_width - len(clipped_status)), status_attr)

    def draw_list(
        self,
        row: int,
        items: Iterable[str],
        selected_index: int | None = None,
        active: bool = True,
    ) -> None:
        for index, item in enumerate(items):
            attr = curses.A_DIM
            if active and selected_index == index:
                attr = curses.A_BOLD | curses.A_REVERSE
            _safe_addstr(self.stdscr, row + index, 4, item, attr)

    def read_key(self) -> str:
        key = self.stdscr.getch()
        if key == 3:
            return "force_quit"
        if key == curses.KEY_RESIZE:
            self.stdscr.clear()
            return "resize"
        if key == curses.KEY_MOUSE:
            try:
                curses.getmouse()
            except curses.error:
                pass
            return "mouse"
        if key in (curses.KEY_UP, ord("k")):
            return "up"
        if key in (curses.KEY_DOWN, ord("j")):
            return "down"
        if key in (curses.KEY_LEFT,):
            return "left"
        if key in (curses.KEY_RIGHT,):
            return "right"
        if key in (10, 13, curses.KEY_ENTER):
            return "enter"
        if key == ord(" "):
            return "space"
        if key in (ord("d"), ord("D")):
            return "done"
        if key in (ord("y"), ord("Y")):
            return "yes"
        if key in (ord("n"), ord("N")):
            return "no"
        if key == 27:
            return "back"
        if key in (curses.KEY_BACKSPACE, 127):
            return "back"
        if 32 <= key <= 126:
            return chr(key)
        return ""

    def read_input_key(self) -> str:
        key = self.stdscr.getch()
        if key == 3:
            return "force_quit"
        if key == curses.KEY_RESIZE:
            self.stdscr.clear()
            return "resize"
        if key == curses.KEY_MOUSE:
            try:
                curses.getmouse()
            except curses.error:
                pass
            return "mouse"
        if key in (10, 13, curses.KEY_ENTER):
            return "enter"
        if key in (curses.KEY_LEFT, 27):
            return "back"
        if key in (curses.KEY_BACKSPACE, 127):
            return "backspace"
        if 32 <= key <= 126:
            return chr(key)
        return ""

    def confirm_force_quit(self) -> bool:
        index = 1
        options = [("stay", "No, continue"), ("quit", "Yes, quit")]
        while True:
            self.clear()
            row = self.draw_header()
            row = self.draw_step_title(row, "Quit Arctyx", "A setup task is still in progress. Quit now?")
            rendered = [(value, label, i == index, "") for i, (value, label) in enumerate(options)]
            self.draw_choice_rows(row, rendered, selected_index=index, mode="radio")
            self.draw_footer("▲/▼ Move • ◀ Back • ▶ Confirm • Enter Confirm • Ctrl+C Quit")
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % len(options)
            elif key == "down":
                index = (index + 1) % len(options)
            elif key in {"mouse", "resize"}:
                continue
            elif key == "enter":
                return options[index][0] == "quit"
            elif key in {"back", "left"}:
                return False
            elif key == "right":
                return options[index][0] == "quit"
            elif key == "force_quit":
                index = 1

    def _maybe_force_quit(self) -> bool:
        return self.confirm_force_quit()

    def ask_yes_no(self, title: str, question: str, default: bool = True) -> bool:
        option_values = ["yes", "no"]
        index = self._restore_cursor("yesno", title, option_values, 0 if default else 1)
        choices = ["Yes", "No"]
        while True:
            self.clear()
            row = self.draw_header()
            row = self.draw_step_title(row, title, question)
            rendered = []
            for i, label in enumerate(choices):
                value = "yes" if i == 0 else "no"
                rendered.append((value, label, i == index, ""))
            options_end_row = self.draw_choice_rows(row, rendered, selected_index=index, mode="radio")
            detail = f"Yes: Apply this setting.\nNo: Leave this setting disabled or unchanged."
            self.draw_detail_block(options_end_row + 1, "Details", detail if index == 0 else detail)
            self.draw_footer("Y/N Choose Instantly • ▲/▼ Move • ◀ Back • ▶ Confirm • Enter Confirm • Ctrl+C Quit")
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % len(choices)
            elif key == "down":
                index = (index + 1) % len(choices)
            elif key in {"mouse", "resize"}:
                continue
            elif key in {"back", "left"}:
                self._remember_cursor("yesno", title, option_values, index)
                return BACK
            elif key == "yes":
                self._remember_cursor("yesno", title, option_values, 0)
                return True
            elif key == "no":
                self._remember_cursor("yesno", title, option_values, 1)
                return False
            elif key in {"enter", "right"}:
                self._remember_cursor("yesno", title, option_values, index)
                return index == 0
            elif key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt

    def ask_radio(
        self,
        title: str,
        options: list[tuple],
        selected_value: str,
        subtitle: str | None = None,
    ) -> str:
        normalized_options = [self._normalize_choice_option(option) for option in options]
        option_values = [value for value, _label, _detail, _secondary in normalized_options]
        default_index = next((i for i, (value, _label, _detail, _secondary) in enumerate(normalized_options) if value == selected_value), 0)
        index = self._restore_cursor("radio", title, option_values, default_index)
        while True:
            self.clear()
            row = self.draw_header()
            row = self.draw_step_title(row, title, subtitle)
            rendered = [(_value, label, i == index, secondary) for i, (_value, label, _detail, secondary) in enumerate(normalized_options)]
            options_end_row = self.draw_choice_rows(row, rendered, selected_index=index, mode="radio")
            self.draw_detail_block(options_end_row + 1, "Details", normalized_options[index][2])
            self.draw_footer("▲/▼ Move • ◀ Back • ▶ Confirm • Space/Enter Confirm • Ctrl+C Quit")
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % len(options)
            elif key == "down":
                index = (index + 1) % len(options)
            elif key in {"mouse", "resize"}:
                continue
            elif key in {"back", "left"}:
                self._remember_cursor("radio", title, option_values, index)
                return BACK
            elif key in {"enter", "right"}:
                self._remember_cursor("radio", title, option_values, index)
                return normalized_options[index][0]
            elif key == "space":
                self._remember_cursor("radio", title, option_values, index)
                return normalized_options[index][0]
            elif key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt

    def ask_menu(
        self,
        title: str,
        options: list[tuple],
        subtitle: str | None = None,
        footer: str = "▲/▼ Move • ◀ Back • ▶ Open • Enter Open • Ctrl+C Quit",
    ) -> str:
        option_values = [option[0] for option in options]
        index = self._restore_cursor("menu", title, option_values, 0)
        while True:
            self.clear()
            row = self.draw_header()
            row = self.draw_step_title(row, title, subtitle)
            rendered: list[tuple[str, str, str]] = []
            row_map: list[int] = []
            normalized_options = [self._normalize_menu_option(option) for option in options]
            for opt_index, option in enumerate(normalized_options):
                if opt_index == len(normalized_options) - 1 and option[0] == "done" and rendered:
                    rendered.append(("", "", ""))
                    row_map.append(-1)
                _value, label, status, preview, _detail = option
                rendered.append((label, status, preview))
                row_map.append(opt_index)

            selected_row = next((i for i, mapped in enumerate(row_map) if mapped == index), 0)
            self.draw_menu_rows(row, rendered, selected_index=selected_row)
            self.draw_detail_block(row + len(rendered) + 1, "Details", normalized_options[index][4])
            self.draw_footer(footer)
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % len(options)
            elif key == "down":
                index = (index + 1) % len(options)
            elif key in {"mouse", "resize"}:
                continue
            elif key in {"back", "left"}:
                self._remember_cursor("menu", title, option_values, index)
                return BACK
            elif key in {"enter", "space", "right"}:
                self._remember_cursor("menu", title, option_values, index)
                return normalized_options[index][0]
            elif key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt

    def ask_checkbox(
        self,
        title: str,
        options: list[tuple],
        selected_values: list[str],
        subtitle: str | None = None,
    ) -> list[str]:
        selected = set(selected_values)
        normalized_options = [self._normalize_choice_option(option) for option in options]
        option_values = [value for value, _label, _detail, _secondary in normalized_options]
        index = self._restore_cursor("checkbox", title, option_values, 0)
        while True:
            self.clear()
            row = self.draw_header()
            row = self.draw_step_title(row, title, subtitle)
            rendered = [(value, label, value in selected, secondary) for value, label, _detail, secondary in normalized_options]
            options_end_row = self.draw_choice_rows(row, rendered, selected_index=index, mode="checkbox")
            self.draw_detail_block(options_end_row + 1, "Details", normalized_options[index][2])
            self.draw_footer("▲/▼ Move • ◀ Back • Space Toggle • Enter/D Done • Ctrl+C Quit")
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % len(options)
            elif key == "down":
                index = (index + 1) % len(options)
            elif key in {"mouse", "resize"}:
                continue
            elif key in {"back", "left"}:
                self._remember_cursor("checkbox", title, option_values, index)
                return BACK
            elif key == "space":
                value = normalized_options[index][0]
                if value in selected:
                    selected.remove(value)
                else:
                    selected.add(value)
            elif key in {"done", "enter"}:
                self._remember_cursor("checkbox", title, option_values, index)
                return [value for value, _label, _detail, _secondary in normalized_options if value in selected]
            elif key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt

    def ask_input(
        self,
        title: str,
        prompt: str,
        default: str = "",
        detail_title: str | None = None,
        detail_resolver=None,
        footer: str | None = None,
    ) -> str:
        value = list(default)
        curses.curs_set(1)
        try:
            while True:
                self.clear()
                row = self.draw_header()
                row = self.draw_step_title(row, title)
                _safe_addstr(self.stdscr, row, 2, prompt, self.palette["prompt"])
                _safe_addstr(self.stdscr, row + 2, 4, "".join(value) or "", self.palette["input"])
                if detail_title and detail_resolver is not None:
                    detail_text = detail_resolver("".join(value))
                    self.draw_detail_block(row + 4, detail_title, detail_text)
                self.draw_footer(footer or "Type Value • ◀ Back • Enter Confirm • Backspace Delete • Ctrl+C Quit")
                self.stdscr.move(row + 2, 4 + len(value))
                self.refresh()

                key = self.read_input_key()
                if key == "enter":
                    return "".join(value).strip()
                if key == "backspace":
                    if value:
                        value.pop()
                elif key == "back":
                    return BACK
                elif key in {"mouse", "resize"}:
                    continue
                elif key == "force_quit":
                    if self._maybe_force_quit():
                        raise KeyboardInterrupt
                elif len(key) == 1:
                    value.append(key)
        finally:
            curses.curs_set(0)

    def show_summary(self, lines: list[str]) -> bool:
        index = 0
        while True:
            self.clear()
            row = self.draw_header()
            row = self.draw_step_title(row, "Summary")
            row = self.draw_summary_lines(row, lines)
            row += 1
            _safe_addstr(self.stdscr, row, 2, "Proceed?", self.palette["prompt"])
            row += 2
            self.draw_choice_rows(
                row,
                [("yes", "Yes", index == 0, ""), ("no", "No", index == 1, "")],
                selected_index=index,
                mode="radio",
            )
            self.draw_footer("Y/N Confirm • ▲/▼ Move • ◀ Back • ▶ Confirm • Ctrl+C Quit")
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % 2
                continue
            if key == "down":
                index = (index + 1) % 2
                continue
            if key == "yes":
                return True
            if key == "no":
                return False
            if key in {"mouse", "resize"}:
                continue
            if key in {"back", "left"}:
                return BACK
            if key in {"enter", "right"}:
                return index == 0
            if key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt

    def show_review(self, summary_lines: list[str], validations: list[str], warnings: list[str], recommendations: list[str], ready: bool) -> bool:
        index = 0
        while True:
            self.clear()
            row = self.draw_header()
            subtitle = "Review the plan, validation checks, and recommendations before applying."
            row = self.draw_step_title(row, "Summary", subtitle)

            review_lines: list[tuple[str, int]] = []
            status_text = "Ready To Apply" if ready else "Needs Attention"
            status_attr = self.palette["success"] if ready else self.palette["warning"]
            review_lines.append((f"Status: {status_text}", status_attr))
            review_lines.append(("", self.palette["label"]))

            for line in summary_lines:
                review_lines.append((line, self.palette["summary_value"]))
            review_lines.append(("", self.palette["label"]))
            review_lines.extend(self._section_lines("Validation", validations, "No Validation Signals", self.palette["summary_value"]))
            review_lines.append(("", self.palette["label"]))
            review_lines.extend(self._section_lines("Warnings", warnings, "No Blocking Warnings", self.palette["warning"]))
            review_lines.append(("", self.palette["label"]))
            review_lines.extend(self._section_lines("Recommendations", recommendations, "No Additional Recommendations", self.palette["recommendation"]))

            for text, attr in self._fit_review_lines(review_lines):
                if ":" in text and not text.startswith("  - "):
                    key, value = text.split(":", 1)
                    self._draw_segments(row, 4, [(f"{key}:", self.palette["summary_key"]), (" ", self.palette["label"]), (value.strip(), attr)])
                else:
                    _safe_addstr(self.stdscr, row, 4, text, attr)
                row += 1

            row += 1
            _safe_addstr(self.stdscr, row, 2, "Proceed?", self.palette["prompt"])
            row += 2
            self.draw_choice_rows(
                row,
                [("yes", "Apply Now", index == 0, ""), ("no", "Go Back", index == 1, "")],
                selected_index=index,
                mode="radio",
            )
            self.draw_footer("Y/N Confirm • ▲/▼ Move • ◀ Back • ▶ Confirm • Ctrl+C Quit")
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % 2
                continue
            if key == "down":
                index = (index + 1) % 2
                continue
            if key == "yes":
                return True
            if key == "no":
                return False
            if key in {"mouse", "resize"}:
                continue
            if key in {"back", "left"}:
                return BACK
            if key in {"enter", "right"}:
                return index == 0
            if key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt

    def show_message(self, title: str, message: str, footer: str = "Enter Continue • Ctrl+C Quit") -> None:
        while True:
            self.clear()
            row = self.draw_header()
            row = self.draw_step_title(row, title)
            for line in message.splitlines():
                _safe_addstr(self.stdscr, row, 4, line, self.palette["summary_value"])
                row += 1
            self.draw_footer(footer)
            self.refresh()

            key = self.read_key()
            if key in {"enter", "space", "right", "yes", "no"}:
                return
            if key in {"mouse", "resize"}:
                continue
            if key in {"back", "left"}:
                return
            if key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt

    def show_welcome_screen(self) -> str:
        options = [
            ("install", "Install", "Apply guided setup changes"),
            ("rollback", "Rollback", "Restore files from a backup snapshot"),
            ("uninstall", "Uninstall", "Remove managed autologin/autostart config"),
        ]
        option_values = [key for key, _label, _desc in options]
        index = self._restore_cursor("menu", "welcome", option_values, 0)
        while True:
            self.clear()
            row = self.draw_welcome_logo(2)
            self.draw_menu_rows(row, [(label, desc, "") for _key, label, desc in options], selected_index=index)
            self.draw_footer("▲/▼ Move • ▶ Select • Enter Select • Ctrl+C Quit")
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % len(options)
            elif key == "down":
                index = (index + 1) % len(options)
            elif key in {"mouse", "resize"}:
                continue
            elif key in {"enter", "space", "right"}:
                self._remember_cursor("menu", "welcome", option_values, index)
                return options[index][0]
            elif key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt

    def ask_resume_state(self) -> str:
        options = [
            ("continue", "Continue", "Resume from the last saved setup state"),
            ("fresh", "Fresh Start", "Reset saved selections and start clean"),
        ]
        option_values = [key for key, _label, _desc in options]
        index = self._restore_cursor("menu", "resume-state", option_values, 0)
        while True:
            self.clear()
            row = self.draw_welcome_logo(2)
            row = self.draw_step_title(row, "Saved State Found", "Choose how to continue this install session.")
            self.draw_menu_rows(row, [(label, desc, "") for _key, label, desc in options], selected_index=index)
            self.draw_footer("▲/▼ Move • ◀ Back • ▶ Select • Enter Select • Ctrl+C Quit")
            self.refresh()

            key = self.read_key()
            if key == "up":
                index = (index - 1) % len(options)
            elif key == "down":
                index = (index + 1) % len(options)
            elif key in {"mouse", "resize"}:
                continue
            elif key in {"back", "left"}:
                self._remember_cursor("menu", "resume-state", option_values, index)
                return BACK
            elif key in {"enter", "space", "right"}:
                self._remember_cursor("menu", "resume-state", option_values, index)
                return options[index][0]
            elif key == "force_quit":
                if self._maybe_force_quit():
                    raise KeyboardInterrupt
