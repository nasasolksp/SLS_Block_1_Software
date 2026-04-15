from __future__ import annotations

import csv
import json
import tkinter as tk
from datetime import datetime, timezone
from pathlib import Path
from tkinter import messagebox, ttk
from typing import Any

from mcc_bridge import DEFAULT_VEHICLE_ID, MccBridgeClient, format_countdown, parse_countdown_to_seconds


VEHICLES = {
    "SLS Block 1": {
        "vehicle_id": DEFAULT_VEHICLE_ID,
        "description": "Space Launch System Block 1 with Orion pad countdown and tower handoff integration.",
    }
}
TARGET_BODY_OPTIONS = ("Earth", "Moon")

NASA_WORM_LOGO_PATH = Path(r"D:\NASAKSP\Logos\Worm.png")
ARTEMIS_LOGO_PATH = Path(r"D:\NASAKSP\Logos\Artemis_Logo_NASA.png")
LAYOUT_STATE_PATH = Path(__file__).resolve().parent / "layout.json"


class DataCard:
    DEFAULT_WIDTH = 392
    DEFAULT_HEIGHT = 282
    MIN_WIDTH = 320
    MIN_HEIGHT = 240

    def __init__(
        self,
        app: "NasaMccApp",
        parent: ttk.Frame,
        initial_field: str,
        card_id: str,
        position: tuple[int, int],
        size: tuple[int, int] | None = None,
    ) -> None:
        self.app = app
        self.parent = parent
        self.card_id = card_id
        self.field_var = tk.StringVar(value=initial_field)
        self.field_display_var = tk.StringVar(value="")
        self.source_var = tk.StringVar(value="")
        self.section_var = tk.StringVar(value="")
        self.metric_var = tk.StringVar(value="")
        self.source_display_var = tk.StringVar(value="")
        self.section_display_var = tk.StringVar(value="")
        self.metric_display_var = tk.StringVar(value="")
        self.value_var = tk.StringVar(value="Awaiting telemetry")
        self.meta_var = tk.StringVar(value="No source data")
        self.popout: tk.Toplevel | None = None
        self.popout_value_var = tk.StringVar(value="Awaiting telemetry")
        self.popout_meta_var = tk.StringVar(value="No source data")
        self.drag_start_x = 0
        self.drag_start_y = 0
        self.resize_start_x = 0
        self.resize_start_y = 0
        self.origin_x = position[0]
        self.origin_y = position[1]
        self.origin_width = size[0] if size and len(size) > 0 else self.DEFAULT_WIDTH
        self.origin_height = size[1] if size and len(size) > 1 else self.DEFAULT_HEIGHT
        self.is_dragging = False
        self.is_resizing = False
        self.picker_window: tk.Toplevel | None = None
        self.pos_x = position[0]
        self.pos_y = position[1]
        self.width = max(self.MIN_WIDTH, int(self.origin_width))
        self.height = max(self.MIN_HEIGHT, int(self.origin_height))
        self.selector_widths = {"source": 20, "section": 24, "metric": 24}

        self.frame = ttk.Frame(parent, style="TelemetryCard.TFrame", padding=0)
        self.frame.configure(width=self.width, height=self.height)
        self.frame.grid_propagate(False)
        self.frame.columnconfigure(0, weight=1)
        self.frame.rowconfigure(2, weight=1)

        header = ttk.Frame(self.frame, style="TelemetryCardChrome.TFrame", padding=(14, 12, 14, 10))
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(0, weight=0)
        header.columnconfigure(1, weight=1)
        header.columnconfigure(2, weight=0)

        self.drag_handle = ttk.Label(header, text="Drag", style="CardDrag.TLabel", cursor="fleur")
        self.drag_handle.grid(row=0, column=0, sticky="w", padx=(0, 10))
        self.drag_handle.bind("<ButtonPress-1>", self.on_drag_start)
        self.drag_handle.bind("<B1-Motion>", self.on_drag_motion)
        self.drag_handle.bind("<ButtonRelease-1>", self.on_drag_release)
        header.bind("<ButtonPress-1>", self.on_drag_start)
        header.bind("<B1-Motion>", self.on_drag_motion)
        header.bind("<ButtonRelease-1>", self.on_drag_release)

        title_block = ttk.Frame(header, style="TelemetryCardChrome.TFrame")
        title_block.grid(row=0, column=1, sticky="ew")
        title_block.columnconfigure(0, weight=1)
        ttk.Label(title_block, text="Telemetry Card", style="CardTitle.TLabel").grid(row=0, column=0, sticky="w")
        self.field_label = ttk.Label(
            title_block,
            textvariable=self.field_display_var,
            style="CardField.TLabel",
            justify="left",
            wraplength=max(220, self.width - 180),
        )
        self.field_label.grid(row=1, column=0, sticky="ew", pady=(4, 0))

        action_row = ttk.Frame(header, style="TelemetryCardChrome.TFrame")
        action_row.grid(row=0, column=2, sticky="e")
        action_row.columnconfigure(0, weight=1)
        ttk.Button(action_row, text="Pop Out", command=self.open_popout, style="Panel.TButton").grid(row=0, column=0, padx=(0, 6))
        ttk.Button(action_row, text="Remove", command=self.remove, style="Danger.TButton").grid(row=0, column=1)

        selector_panel = ttk.Frame(self.frame, style="TelemetryCard.TFrame", padding=(14, 2, 14, 10))
        selector_panel.grid(row=1, column=0, sticky="ew")
        selector_panel.columnconfigure(1, weight=1)

        self.source_label = ttk.Label(selector_panel, text="Source", style="CardMetaLabel.TLabel")
        self.source_label.grid(row=0, column=0, sticky="w", pady=(0, 6), padx=(0, 10))
        self.source_button = ttk.Button(
            selector_panel,
            textvariable=self.source_display_var,
            command=lambda: self.open_picker("source"),
            style="CardSelector.TButton",
            width=10,
        )
        self.source_button.grid(row=0, column=1, sticky="ew", pady=(0, 6))

        self.section_label = ttk.Label(selector_panel, text="Section", style="CardMetaLabel.TLabel")
        self.section_label.grid(row=1, column=0, sticky="w", pady=(0, 6), padx=(0, 10))
        self.section_button = ttk.Button(
            selector_panel,
            textvariable=self.section_display_var,
            command=lambda: self.open_picker("section"),
            style="CardSelector.TButton",
            width=14,
        )
        self.section_button.grid(row=1, column=1, sticky="ew", pady=(0, 6))

        self.metric_label = ttk.Label(selector_panel, text="Metric", style="CardMetaLabel.TLabel")
        self.metric_label.grid(row=2, column=0, sticky="w", padx=(0, 10))
        self.metric_button = ttk.Button(
            selector_panel,
            textvariable=self.metric_display_var,
            command=lambda: self.open_picker("metric"),
            style="CardSelector.TButton",
            width=16,
        )
        self.metric_button.grid(row=2, column=1, sticky="ew")

        self.value_panel = ttk.Frame(self.frame, style="TelemetryValue.TFrame", padding=(14, 12, 14, 10))
        self.value_panel.grid(row=2, column=0, sticky="nsew")
        self.value_panel.columnconfigure(0, weight=1)
        self.value_panel.rowconfigure(0, weight=1)

        self.value_label = ttk.Label(
            self.value_panel,
            textvariable=self.value_var,
            style="TelemetryValue.TLabel",
            anchor="w",
            justify="left",
            wraplength=max(260, self.width - 34),
        )
        self.value_label.grid(row=0, column=0, sticky="nsew")

        footer = ttk.Frame(self.frame, style="TelemetryCardChrome.TFrame", padding=(14, 0, 14, 10))
        footer.grid(row=3, column=0, sticky="ew")
        footer.columnconfigure(0, weight=1)
        footer.columnconfigure(1, weight=0)

        self.meta_label = ttk.Label(footer, textvariable=self.meta_var, style="CardMetaBody.TLabel", justify="left", wraplength=max(260, self.width - 90))
        self.meta_label.grid(row=0, column=0, sticky="w")
        self.resize_handle = ttk.Label(footer, text="↘", style="CardResize.TLabel", cursor="bottom_right_corner")
        self.resize_handle.grid(row=0, column=1, sticky="e")
        self.resize_handle.bind("<ButtonPress-1>", self.on_resize_start)
        self.resize_handle.bind("<B1-Motion>", self.on_resize_motion)
        self.resize_handle.bind("<ButtonRelease-1>", self.on_resize_release)
        self.frame.bind("<Configure>", self.on_card_configure)
        self._bind_drag_targets(self.frame, header, title_block, selector_panel, self.value_panel, footer)
        self._sync_layout_constraints()

    def update_hierarchy(self, field_catalog: dict[str, dict[str, list[str]]], preserve_field: str | None = None) -> None:
        target_field = preserve_field or self.field_var.get()
        self._assign_selection_from_field(target_field, field_catalog)

        sources = sorted(field_catalog.keys())
        if self.source_var.get() not in sources and sources:
            self.source_var.set(sources[0])

        self._refresh_section_options(field_catalog)
        self._refresh_metric_options(field_catalog)
        self.field_var.set(self._compose_field_key(self.source_var.get(), self.section_var.get(), self.metric_var.get()))
        self.field_display_var.set(self._abbreviate_field_key(self.field_var.get()))
        self._sync_layout_constraints(field_catalog)

    def update_value(self, flattened_data: dict[str, Any]) -> None:
        key = self.field_var.get()
        value = self.app.resolve_field_display_value(key, flattened_data)
        source = key.split(".", 1)[0] if "." in key else "bridge"
        display_value = self.app.stringify_value(value)
        self.value_var.set(display_value)
        self.meta_var.set(f"Src: {self._abbreviate_segment(source).upper()} | Field: {self._abbreviate_field_key(key)}")
        self.popout_value_var.set(display_value)
        self.popout_meta_var.set(f"Source: {source.upper()} | Field: {key}")

    def on_source_changed(self) -> None:
        self._refresh_section_options(self.app.field_catalog)
        self._refresh_metric_options(self.app.field_catalog)
        self.source_display_var.set(self._abbreviate_segment(self.source_var.get()))
        self._sync_layout_constraints(self.app.field_catalog)
        self.on_metric_changed()

    def on_section_changed(self) -> None:
        self._refresh_metric_options(self.app.field_catalog)
        self.section_display_var.set(self._abbreviate_segment(self.section_var.get()))
        self._sync_layout_constraints(self.app.field_catalog)
        self.on_metric_changed()

    def on_metric_changed(self) -> None:
        source_name = self.source_var.get()
        section_name = self.section_var.get()
        metric_name = self.metric_var.get()

        self.field_var.set(self._compose_field_key(source_name, section_name, metric_name))
        self.source_display_var.set(self._abbreviate_segment(source_name))
        self.section_display_var.set(self._abbreviate_segment(section_name))
        self.metric_display_var.set(self._abbreviate_segment(metric_name))
        self.field_display_var.set(self._abbreviate_field_key(self.field_var.get()))
        self._sync_layout_constraints(self.app.field_catalog)
        self.app.refresh_data_cards()
        self.app.save_layout_state()

    def _refresh_section_options(self, field_catalog: dict[str, dict[str, list[str]]]) -> None:
        sections = sorted(field_catalog.get(self.source_var.get(), {}).keys())
        if self.section_var.get() not in sections and sections:
            self.section_var.set(sections[0])

    def _refresh_metric_options(self, field_catalog: dict[str, dict[str, list[str]]]) -> None:
        metrics = field_catalog.get(self.source_var.get(), {}).get(self.section_var.get(), [])
        if self.metric_var.get() not in metrics and metrics:
            self.metric_var.set(metrics[0])

    def _assign_selection_from_field(self, field_key: str, field_catalog: dict[str, dict[str, list[str]]]) -> None:
        source_name, section_name, metric_name = self._split_field_key(field_key)

        if source_name not in field_catalog:
            if field_catalog:
                source_name = sorted(field_catalog.keys())[0]
            else:
                source_name = ""

        available_sections = field_catalog.get(source_name, {})
        if section_name not in available_sections:
            if available_sections:
                section_name = sorted(available_sections.keys())[0]
            else:
                section_name = ""

        available_metrics = available_sections.get(section_name, [])
        if metric_name not in available_metrics:
            if available_metrics:
                metric_name = available_metrics[0]
            else:
                metric_name = ""

        self.source_var.set(source_name)
        self.section_var.set(section_name)
        self.metric_var.set(metric_name)
        self.field_var.set(self._compose_field_key(source_name, section_name, metric_name))
        self.source_display_var.set(self._abbreviate_segment(source_name))
        self.section_display_var.set(self._abbreviate_segment(section_name))
        self.metric_display_var.set(self._abbreviate_segment(metric_name))
        self.field_display_var.set(self._abbreviate_field_key(self.field_var.get()))

    @staticmethod
    def _split_field_key(field_key: str) -> tuple[str, str, str]:
        if not field_key:
            return "", "", ""

        parts = field_key.split(".")
        if len(parts) == 1:
            return parts[0], "(root)", parts[0]
        if len(parts) == 2:
            return parts[0], "(root)", parts[1]
        return parts[0], ".".join(parts[1:-1]), parts[-1]

    @staticmethod
    def _compose_field_key(source_name: str, section_name: str, metric_name: str) -> str:
        if not source_name or not metric_name:
            return ""
        if not section_name or section_name == "(root)":
            return f"{source_name}.{metric_name}"
        return f"{source_name}.{section_name}.{metric_name}"

    @staticmethod
    def _abbreviate_segment(segment: str) -> str:
        normalized = str(segment or "").strip()
        if not normalized or normalized == "(root)":
            return "r"

        aliases = {
            "tower": "t",
            "vehicle": "v",
            "vehicle_status": "vs",
            "vehicle_flight": "vf",
            "bridge": "b",
            "launch_rule_check": "lrc",
            "readiness": "rd",
            "operator": "op",
        }
        if normalized in aliases:
            return aliases[normalized]

        parts = [part for part in normalized.split("_") if part]
        if len(parts) == 1:
            return normalized[:3]
        return "".join(part[0] for part in parts)[:4]

    @classmethod
    def _abbreviate_field_key(cls, field_key: str) -> str:
        parts = [part for part in str(field_key or "").split(".") if part]
        if not parts:
            return ""
        return ".".join(cls._abbreviate_segment(part) for part in parts)

    def remove(self) -> None:
        if self.popout is not None and self.popout.winfo_exists():
            self.popout.destroy()
        if self.picker_window is not None and self.picker_window.winfo_exists():
            self.picker_window.destroy()
        self.frame.destroy()
        self.app.remove_data_card(self)

    def on_drag_start(self, event: tk.Event) -> None:
        self.drag_start_x = event.x_root
        self.drag_start_y = event.y_root
        self.origin_x = self.pos_x
        self.origin_y = self.pos_y
        self.is_dragging = False

    def on_drag_motion(self, event: tk.Event) -> None:
        if abs(event.x_root - self.drag_start_x) < 8 and abs(event.y_root - self.drag_start_y) < 8:
            return

        self.is_dragging = True
        delta_x = event.x_root - self.drag_start_x
        delta_y = event.y_root - self.drag_start_y
        self.app.move_card(self, self.origin_x + delta_x, self.origin_y + delta_y)

    def on_drag_release(self, _event: tk.Event) -> None:
        if self.is_dragging:
            self.app.save_layout_state()
        self.is_dragging = False

    def on_resize_start(self, event: tk.Event) -> None:
        self.resize_start_x = event.x_root
        self.resize_start_y = event.y_root
        self.origin_width = self.width
        self.origin_height = self.height
        self.is_resizing = False

    def on_resize_motion(self, event: tk.Event) -> None:
        delta_x = event.x_root - self.resize_start_x
        delta_y = event.y_root - self.resize_start_y
        if abs(delta_x) < 4 and abs(delta_y) < 4:
            return

        self.is_resizing = True
        new_width = max(self.MIN_WIDTH, self.origin_width + delta_x)
        new_height = max(self.MIN_HEIGHT, self.origin_height + delta_y)
        self.app.resize_card(self, new_width, new_height)

    def on_resize_release(self, _event: tk.Event) -> None:
        if self.is_resizing:
            self.app.save_layout_state()
        self.is_resizing = False

    def on_card_configure(self, event: tk.Event) -> None:
        width = max(self.MIN_WIDTH, int(event.width))
        height = max(self.MIN_HEIGHT, int(event.height))
        if width == self.width and height == self.height:
            return

        self.width = width
        self.height = height
        self._sync_layout_constraints(self.app.field_catalog)

    def _bind_drag_targets(self, *widgets: ttk.Widget) -> None:
        for widget in widgets:
            widget.bind("<ButtonPress-1>", self.on_drag_start)
            widget.bind("<B1-Motion>", self.on_drag_motion)
            widget.bind("<ButtonRelease-1>", self.on_drag_release)

    def _set_selector_width(self, widget: ttk.Button, current_value: str, floor: int, ceiling: int) -> None:
        length = max(len(current_value or ""), floor)
        widget.configure(width=max(floor, min(ceiling, length + 2)))

    def _sync_layout_constraints(self, field_catalog: dict[str, dict[str, list[str]]] | None = None) -> None:
        catalog = field_catalog or self.app.field_catalog
        current_source = self.source_var.get()
        current_section = self.section_var.get()
        current_metric = self.metric_var.get()

        self.source_display_var.set(self._abbreviate_segment(current_source))
        self.section_display_var.set(self._abbreviate_segment(current_section))
        self.metric_display_var.set(self._abbreviate_segment(current_metric))

        self._set_selector_width(self.source_button, self.source_display_var.get(), 6, 10)
        self._set_selector_width(self.section_button, self.section_display_var.get(), 6, 12)
        self._set_selector_width(self.metric_button, self.metric_display_var.get(), 6, 14)

        self.field_label.configure(wraplength=max(180, self.width - 176))
        self.value_label.configure(wraplength=max(240, self.width - 34))
        self.meta_label.configure(wraplength=max(220, self.width - 90))
        self.frame.configure(width=self.width, height=self.height)
        self.frame.grid_propagate(False)

    def open_picker(self, level: str) -> None:
        options = self._get_picker_options(level)
        if not options:
            return

        if self.picker_window is not None and self.picker_window.winfo_exists():
            self.picker_window.destroy()

        self.picker_window = tk.Toplevel(self.app)
        self.picker_window.title(f"Select {level.title()}")
        self.picker_window.geometry("520x360")
        self.picker_window.minsize(420, 300)
        self.picker_window.configure(background=self.app.colors["bg"])
        self.picker_window.transient(self.app)

        shell = ttk.Frame(self.picker_window, style="Shell.TFrame", padding=16)
        shell.pack(fill="both", expand=True)
        shell.columnconfigure(0, weight=1)
        shell.rowconfigure(1, weight=1)

        ttk.Label(shell, text=f"Select {level.title()}", style="SectionTitle.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 10))

        listbox = tk.Listbox(
            shell,
            bg="#071929",
            fg=self.app.colors["text"],
            borderwidth=0,
            highlightthickness=0,
            selectbackground=self.app.colors["highlight"],
            font=("Consolas", 12),
        )
        listbox.grid(row=1, column=0, sticky="nsew")

        for option in options:
            listbox.insert(tk.END, option)

        current_value = {
            "source": self.source_var.get(),
            "section": self.section_var.get(),
            "metric": self.metric_var.get(),
        }[level]
        if current_value in options:
            current_index = options.index(current_value)
            listbox.selection_set(current_index)
            listbox.see(current_index)

        listbox.bind("<Double-Button-1>", lambda _event: self.apply_picker_selection(level, listbox))

        button_row = ttk.Frame(shell, style="Shell.TFrame")
        button_row.grid(row=2, column=0, sticky="e", pady=(12, 0))
        ttk.Button(button_row, text="Select", command=lambda: self.apply_picker_selection(level, listbox), style="Accent.TButton").grid(row=0, column=0, padx=(0, 8))
        ttk.Button(button_row, text="Cancel", command=self.picker_window.destroy, style="Panel.TButton").grid(row=0, column=1)

    def apply_picker_selection(self, level: str, listbox: tk.Listbox) -> None:
        selection = listbox.curselection()
        if not selection:
            return

        selected_value = listbox.get(selection[0])
        if level == "source":
            self.source_var.set(selected_value)
            self.on_source_changed()
        elif level == "section":
            self.section_var.set(selected_value)
            self.on_section_changed()
        else:
            self.metric_var.set(selected_value)
            self.on_metric_changed()

        if self.picker_window is not None and self.picker_window.winfo_exists():
            self.picker_window.destroy()

    def _get_picker_options(self, level: str) -> list[str]:
        if level == "source":
            return sorted(self.app.field_catalog.keys())
        if level == "section":
            return sorted(self.app.field_catalog.get(self.source_var.get(), {}).keys())
        return list(self.app.field_catalog.get(self.source_var.get(), {}).get(self.section_var.get(), []))

    def open_popout(self) -> None:
        if self.popout is not None and self.popout.winfo_exists():
            self.popout.focus_set()
            return

        self.popout = tk.Toplevel(self.app)
        self.popout.title(self.field_var.get() or "Telemetry")
        self.popout.geometry("420x220")
        self.popout.minsize(320, 180)
        self.popout.configure(background=self.app.colors["bg"])
        self.popout.protocol("WM_DELETE_WINDOW", self.popout.destroy)

        shell = ttk.Frame(self.popout, style="Shell.TFrame", padding=16)
        shell.pack(fill="both", expand=True)
        shell.columnconfigure(0, weight=1)

        ttk.Label(shell, textvariable=self.field_var, style="SectionTitle.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(shell, textvariable=self.popout_value_var, style="Value.TLabel", anchor="center").grid(
            row=1, column=0, sticky="nsew", pady=(18, 8)
        )
        ttk.Label(shell, textvariable=self.popout_meta_var, style="Meta.TLabel").grid(row=2, column=0, sticky="w")


class NasaMccApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("NASA MCC APP")
        self.geometry("1440x900")
        self.minsize(1080, 720)

        self.colors = {
            "bg": "#06111d",
            "panel": "#0c1f33",
            "panel_alt": "#102944",
            "text": "#f0f4f8",
            "muted": "#8ca3b8",
            "accent": "#d04436",
            "highlight": "#2f7ea1",
            "gold": "#c8aa6c",
        }

        self.configure(background=self.colors["bg"])
        self.style = ttk.Style(self)
        self._configure_theme()

        base_dir = Path(__file__).resolve().parent.parent / "MCC_Interface"
        self.bridge = MccBridgeClient(base_dir)
        self.flight_log_path = self.bridge.paths.vehicle_flight_log_path
        self.forecast_path = self.bridge.paths.vehicle_launch_forecast_path

        self.selected_vehicle_name = tk.StringVar(value="SLS Block 1")
        self.target_body_var = tk.StringVar(value="Earth")
        self.countdown_var = tk.StringVar(value="00:02:00")
        self.command_status_var = tk.StringVar(value="Bridge ready.")
        self.summary_vars = {
            "vehicle": tk.StringVar(value="SLS Block 1"),
            "tower_mode": tk.StringVar(value="Awaiting tower command"),
            "countdown": tk.StringVar(value="T-00:00:00"),
            "vehicle_mode": tk.StringVar(value="Awaiting tower handoff"),
            "operator": tk.StringVar(value="READY"),
            "readiness": tk.StringVar(value="Awaiting diagnostics"),
            "bridge": tk.StringVar(value=str(base_dir)),
        }
        self.tower_online = False
        self.vehicle_online = False
        self.flight_online = False
        self.vehicle_session_active = False

        self.current_bundle: dict[str, Any] = {}
        self.flattened_data: dict[str, Any] = {}
        self.last_known_values: dict[str, Any] = {}
        self.known_fields: set[str] = set()
        self.field_catalog: dict[str, dict[str, list[str]]] = {}
        self.data_cards: list[DataCard] = []
        self.card_counter = 0
        self.workspace_columns = 1
        self.log_items: list[str] = []
        self.log_var = tk.StringVar(value=[])
        self._image_refs: list[tk.PhotoImage] = []
        self.layout_state = self.load_layout_state()
        self.pending_command_clear: str | None = None
        self.last_tower_updated_at: str = ""
        self.last_tower_seen_at: float = 0.0
        self.last_vehicle_updated_at: str = ""
        self.last_vehicle_seen_at: float = 0.0
        self.last_flight_updated_at: str = ""
        self.last_flight_seen_at: float = 0.0
        self.flight_log_points: list[dict[str, float]] = []
        self.launch_forecast_rows: list[dict[str, Any]] = []
        self.launch_rule_check_rows: list[dict[str, Any]] = []
        self.visual_summary_vars = {
            "status": tk.StringVar(value="Awaiting flight data"),
            "route": tk.StringVar(value="No forecast loaded"),
            "altitude": tk.StringVar(value="0 m"),
            "downrange": tk.StringVar(value="0 m"),
            "speed": tk.StringVar(value="0 m/s"),
            "samples": tk.StringVar(value="0 samples"),
        }
        self.launch_rules_summary_vars = {
            "status": tk.StringVar(value="Awaiting launch rules"),
            "gate": tk.StringVar(value="T-60 gate inactive"),
            "readiness": tk.StringVar(value="Awaiting diagnostics"),
            "manifest": tk.StringVar(value="Unknown"),
            "margin": tk.StringVar(value="0 m/s"),
        }
        self.launch_rules_note_var = tk.StringVar(value="The T-60 launch rule check appears here when the countdown starts above 60 minutes.")
        self.protocol("WM_DELETE_WINDOW", self.on_close)

        self.show_start_screen()
        self.after(500, self.poll_bridge)

    def _configure_theme(self) -> None:
        self.style.theme_use("clam")
        self.style.configure(".", background=self.colors["bg"], foreground=self.colors["text"], fieldbackground=self.colors["panel"])
        self.style.configure("Shell.TFrame", background=self.colors["bg"])
        self.style.configure("Panel.TFrame", background=self.colors["panel"])
        self.style.configure("Card.TFrame", background=self.colors["panel_alt"], relief="flat")
        self.style.configure("TelemetryCard.TFrame", background="#081625", relief="flat", borderwidth=1)
        self.style.configure("TelemetryCardChrome.TFrame", background="#0b1b2d")
        self.style.configure("TelemetryValue.TFrame", background="#0d2034")
        self.style.configure("Header.TLabel", background=self.colors["bg"], foreground=self.colors["text"], font=("Bahnschrift", 22, "bold"))
        self.style.configure("SectionTitle.TLabel", background=self.colors["bg"], foreground=self.colors["gold"], font=("Bahnschrift", 14, "bold"))
        self.style.configure("Body.TLabel", background=self.colors["bg"], foreground=self.colors["muted"], font=("Segoe UI", 11))
        self.style.configure("PanelTitle.TLabel", background=self.colors["panel"], foreground=self.colors["gold"], font=("Bahnschrift", 14, "bold"))
        self.style.configure("PanelText.TLabel", background=self.colors["panel"], foreground=self.colors["text"], font=("Segoe UI", 11))
        self.style.configure("Meta.TLabel", background=self.colors["panel_alt"], foreground=self.colors["muted"], font=("Consolas", 10))
        self.style.configure("Value.TLabel", background=self.colors["panel_alt"], foreground=self.colors["text"], font=("Consolas", 22, "bold"))
        self.style.configure("HeroCountdown.TLabel", background=self.colors["panel"], foreground=self.colors["text"], font=("Consolas", 34, "bold"))
        self.style.configure("HeroMeta.TLabel", background=self.colors["panel"], foreground=self.colors["muted"], font=("Segoe UI", 11))
        self.style.configure("CardDrag.TLabel", background="#10263a", foreground=self.colors["gold"], font=("Bahnschrift", 10, "bold"), padding=(8, 4))
        self.style.configure("CardTitle.TLabel", background="#0b1b2d", foreground=self.colors["gold"], font=("Bahnschrift", 13, "bold"))
        self.style.configure("CardField.TLabel", background="#0b1b2d", foreground=self.colors["text"], font=("Consolas", 11, "bold"))
        self.style.configure("CardMetaLabel.TLabel", background="#081625", foreground=self.colors["muted"], font=("Segoe UI", 10, "bold"))
        self.style.configure("CardMetaBody.TLabel", background="#0b1b2d", foreground=self.colors["muted"], font=("Consolas", 9))
        self.style.configure("TelemetryValue.TLabel", background="#0d2034", foreground=self.colors["text"], font=("Consolas", 18, "bold"), padding=(0, 0, 0, 0))
        self.style.configure("CardResize.TLabel", background="#10263a", foreground=self.colors["gold"], font=("Segoe UI", 8, "bold"), padding=(6, 3))
        self.style.configure("Panel.TButton", background=self.colors["highlight"], foreground=self.colors["text"], borderwidth=0, padding=8)
        self.style.map("Panel.TButton", background=[("active", "#4597bb")])
        self.style.configure("Accent.TButton", background=self.colors["accent"], foreground=self.colors["text"], borderwidth=0, padding=10)
        self.style.map("Accent.TButton", background=[("active", "#f05a4b")])
        self.style.configure("Danger.TButton", background="#74292d", foreground=self.colors["text"], borderwidth=0, padding=8)
        self.style.map("Danger.TButton", background=[("active", "#93434c")])
        self.style.configure("Panel.TEntry", fieldbackground="#071929", foreground=self.colors["text"], insertcolor=self.colors["text"])
        self.style.configure("Panel.TCombobox", fieldbackground="#071929", foreground=self.colors["text"])
        self.style.configure("CardSelector.TButton", background="#071929", foreground=self.colors["text"], borderwidth=1, relief="solid", padding=(6, 3), anchor="center")
        self.style.map("CardSelector.TButton", background=[("active", "#0b243a")], foreground=[("active", self.colors["text"])])
        self.style.configure("TNotebook", background=self.colors["panel"], borderwidth=0)
        self.style.configure(
            "TNotebook.Tab",
            background=self.colors["panel_alt"],
            foreground=self.colors["text"],
            padding=(16, 10),
        )
        self.style.map("TNotebook.Tab", background=[("selected", self.colors["highlight"])], foreground=[("selected", self.colors["text"])])

    def clear_root(self) -> None:
        for child in self.winfo_children():
            child.destroy()

    def show_start_screen(self) -> None:
        self.clear_root()
        self._image_refs.clear()
        shell = ttk.Frame(self, style="Shell.TFrame", padding=32)
        shell.pack(fill="both", expand=True)
        shell.columnconfigure(0, weight=1)

        hero = ttk.Frame(shell, style="Shell.TFrame")
        hero.grid(row=0, column=0, sticky="nsew")
        hero.columnconfigure(0, weight=1)

        if not self.render_logo(hero, NASA_WORM_LOGO_PATH, max_width=720, max_height=240, row=0):
            canvas = tk.Canvas(hero, width=220, height=220, background=self.colors["bg"], highlightthickness=0)
            canvas.grid(row=0, column=0, pady=(30, 18))
            self.draw_nasa_mark(canvas)

        ttk.Label(hero, text="NASA MCC APP", style="Header.TLabel").grid(row=1, column=0, pady=(0, 10))
        ttk.Label(
            hero,
            text="Mission control hub for tower-command countdown operations, telemetry windows, and operator interventions.",
            style="Body.TLabel",
            wraplength=720,
            justify="center",
        ).grid(row=2, column=0, pady=(0, 30))

        selector = ttk.Frame(hero, style="Panel.TFrame", padding=24)
        selector.grid(row=3, column=0)
        selector.columnconfigure(0, weight=1)

        ttk.Label(selector, text="Vehicle Selection", style="PanelTitle.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 12))
        ttk.Combobox(
            selector,
            textvariable=self.selected_vehicle_name,
            values=list(VEHICLES.keys()),
            state="readonly",
            width=32,
            style="Panel.TCombobox",
        ).grid(row=1, column=0, sticky="ew")
        ttk.Label(
            selector,
            text=VEHICLES[self.selected_vehicle_name.get()]["description"],
            style="PanelText.TLabel",
            wraplength=520,
            justify="left",
        ).grid(row=2, column=0, sticky="w", pady=(12, 18))
        ttk.Button(selector, text="Select", command=self.show_vehicle_hub, style="Accent.TButton").grid(row=3, column=0, sticky="ew")

    def draw_nasa_mark(self, canvas: tk.Canvas) -> None:
        canvas.create_oval(18, 18, 202, 202, fill="#11315b", outline="#dfe8ef", width=4)
        canvas.create_arc(22, 35, 205, 188, start=220, extent=110, style="arc", outline="#d04436", width=8)
        canvas.create_text(110, 104, text="NASA", fill="#f5f7fa", font=("Bahnschrift", 28, "bold"))
        canvas.create_line(52, 150, 174, 60, fill="#f5f7fa", width=3, smooth=True)

    def render_logo(
        self,
        parent: ttk.Frame,
        path: Path,
        max_width: int,
        max_height: int,
        row: int,
        column: int = 0,
        padx: tuple[int, int] | int = 0,
        pady: tuple[int, int] = (20, 10),
    ) -> bool:
        image = self.load_logo(path, max_width=max_width, max_height=max_height)
        if image is None:
            return False

        ttk.Label(parent, image=image, style="Shell.TFrame").grid(row=row, column=column, padx=padx, pady=pady, sticky="w")
        self._image_refs.append(image)
        return True

    def load_logo(self, path: Path, max_width: int, max_height: int) -> tk.PhotoImage | None:
        if not path.exists():
            return None

        try:
            image = tk.PhotoImage(file=str(path))
        except tk.TclError:
            return None

        width = image.width()
        height = image.height()
        if width <= 0 or height <= 0:
            return None

        width_ratio = max(1, -(-width // max_width))
        height_ratio = max(1, -(-height // max_height))
        sample_ratio = max(width_ratio, height_ratio)

        if sample_ratio > 1:
            image = image.subsample(sample_ratio, sample_ratio)

        return image

    def show_vehicle_hub(self) -> None:
        self.clear_root()
        self._image_refs.clear()
        shell = ttk.Frame(self, style="Shell.TFrame", padding=18)
        shell.pack(fill="both", expand=True)
        shell.rowconfigure(2, weight=1)
        shell.columnconfigure(1, weight=1)

        header = ttk.Frame(shell, style="Shell.TFrame")
        header.grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 14))
        header.columnconfigure(0, weight=1)

        title_block = ttk.Frame(header, style="Shell.TFrame")
        title_block.grid(row=0, column=0, sticky="w")
        title_block.columnconfigure(1, weight=1)

        self.render_logo(title_block, ARTEMIS_LOGO_PATH, max_width=120, max_height=120, row=0, column=0, padx=(0, 16), pady=(0, 0))

        text_block = ttk.Frame(title_block, style="Shell.TFrame")
        text_block.grid(row=0, column=1, sticky="w")
        ttk.Label(text_block, text=f"{self.selected_vehicle_name.get()} Mission Control", style="Header.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(text_block, text="Tower command authority; the vehicle waits for handoff", style="Body.TLabel").grid(row=1, column=0, sticky="w")

        top_status = ttk.Frame(shell, style="Panel.TFrame", padding=18)
        top_status.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(0, 14))
        top_status.columnconfigure(1, weight=1)

        countdown_block = ttk.Frame(top_status, style="Panel.TFrame")
        countdown_block.grid(row=0, column=0, sticky="w", padx=(0, 32))
        ttk.Label(countdown_block, text="COUNTDOWN", style="PanelTitle.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(countdown_block, textvariable=self.summary_vars["countdown"], style="HeroCountdown.TLabel").grid(row=1, column=0, sticky="w", pady=(6, 0))
        ttk.Label(countdown_block, text="Primary mission clock", style="HeroMeta.TLabel").grid(row=2, column=0, sticky="w", pady=(4, 0))

        mission_strip = ttk.Frame(top_status, style="Panel.TFrame")
        mission_strip.grid(row=0, column=1, sticky="ew")
        for column in range(6):
            mission_strip.columnconfigure(column, weight=1, uniform="summary")

        self.build_top_summary_item(mission_strip, 0, "Vehicle", self.summary_vars["vehicle"])
        self.build_top_summary_item(mission_strip, 1, "Tower Mode", self.summary_vars["tower_mode"])
        self.build_top_summary_item(mission_strip, 2, "Vehicle Mode", self.summary_vars["vehicle_mode"])
        self.build_top_summary_item(mission_strip, 3, "Operator", self.summary_vars["operator"])
        self.build_top_summary_item(mission_strip, 4, "Readiness", self.summary_vars["readiness"])
        self.build_top_summary_item(mission_strip, 5, "Bridge Path", self.summary_vars["bridge"])

        left = ttk.Frame(shell, style="Panel.TFrame", padding=16)
        left.grid(row=2, column=0, sticky="nsw", padx=(0, 14))
        center = ttk.Frame(shell, style="Panel.TFrame", padding=12)
        center.grid(row=2, column=1, sticky="nsew")

        shell.columnconfigure(1, weight=1)
        shell.rowconfigure(2, weight=1)

        self.build_control_panel(left)
        center.rowconfigure(0, weight=1)
        center.columnconfigure(0, weight=1)

        self.page_notebook = ttk.Notebook(center)
        self.page_notebook.grid(row=0, column=0, sticky="nsew")

        telemetry_page = ttk.Frame(self.page_notebook, style="Panel.TFrame")
        rules_page = ttk.Frame(self.page_notebook, style="Panel.TFrame")
        visual_page = ttk.Frame(self.page_notebook, style="Panel.TFrame")
        self.page_notebook.add(telemetry_page, text="Telemetry Window")
        self.page_notebook.add(rules_page, text="Launch Rules")
        self.page_notebook.add(visual_page, text="Visual Data")

        self.build_workspace(telemetry_page)
        self.build_launch_rules_page(rules_page)
        self.build_visual_page(visual_page)

        if self.layout_state.get("cards"):
            for card_state in self.layout_state["cards"]:
                saved_x = card_state.get("x")
                saved_y = card_state.get("y")
                saved_width = card_state.get("width")
                saved_height = card_state.get("height")
                saved_position = None
                if isinstance(saved_x, (int, float)) and isinstance(saved_y, (int, float)):
                    saved_position = (int(saved_x), int(saved_y))
                saved_size = None
                if isinstance(saved_width, (int, float)) and isinstance(saved_height, (int, float)):
                    saved_size = (int(saved_width), int(saved_height))
                self.add_data_card(
                    card_state.get("field"),
                    card_id=card_state.get("card_id"),
                    position=saved_position,
                    size=saved_size,
                )
        else:
            for field in (
                "tower.formatted_countdown",
                "tower.operator_status_text",
                "vehicle.mode",
                "vehicle.altitude",
            ):
                self.add_data_card(field)

        self.refresh_data_cards()
        self.refresh_launch_rules_page()
        self.refresh_visual_page()

    def build_control_panel(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        ttk.Label(parent, text="Countdown Control", style="PanelTitle.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(parent, text="Vehicle", style="PanelText.TLabel").grid(row=1, column=0, sticky="w", pady=(16, 4))
        ttk.Label(parent, text=self.selected_vehicle_name.get(), style="PanelText.TLabel").grid(row=2, column=0, sticky="w")

        ttk.Label(parent, text="Target Body", style="PanelText.TLabel").grid(row=3, column=0, sticky="w", pady=(18, 6))
        ttk.Combobox(
            parent,
            textvariable=self.target_body_var,
            values=TARGET_BODY_OPTIONS,
            state="readonly",
            style="Panel.TCombobox",
        ).grid(row=4, column=0, sticky="ew")

        ttk.Label(parent, text="Set Count (HH:MM:SS)", style="PanelText.TLabel").grid(row=5, column=0, sticky="w", pady=(18, 6))
        ttk.Entry(parent, textvariable=self.countdown_var, style="Panel.TEntry").grid(row=6, column=0, sticky="ew")

        buttons = ttk.Frame(parent, style="Panel.TFrame")
        buttons.grid(row=7, column=0, sticky="ew", pady=(16, 0))
        buttons.columnconfigure(0, weight=1)
        buttons.columnconfigure(1, weight=1)
        ttk.Button(buttons, text="Apply Tower Count", command=self.send_set_countdown, style="Accent.TButton").grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(buttons, text="Add Data Window", command=lambda: self.add_data_card(None), style="Panel.TButton").grid(row=0, column=1, sticky="ew")

        action_row = ttk.Frame(parent, style="Panel.TFrame")
        action_row.grid(row=8, column=0, sticky="ew", pady=(12, 0))
        action_row.columnconfigure(0, weight=1)
        action_row.columnconfigure(1, weight=1)
        ttk.Button(action_row, text="Arm Tower", command=self.send_start_countdown, style="Accent.TButton").grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(action_row, text="Abort", command=self.send_abort, style="Danger.TButton").grid(row=0, column=1, sticky="ew")

        hold_row = ttk.Frame(parent, style="Panel.TFrame")
        hold_row.grid(row=9, column=0, sticky="ew", pady=(12, 0))
        hold_row.columnconfigure(0, weight=1)
        hold_row.columnconfigure(1, weight=1)
        ttk.Button(hold_row, text="Hold", command=self.send_hold, style="Danger.TButton").grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(hold_row, text="Resume", command=self.send_resume, style="Panel.TButton").grid(row=0, column=1, sticky="ew")

        ttk.Label(parent, text="Operator Link", style="PanelTitle.TLabel").grid(row=10, column=0, sticky="w", pady=(24, 8))
        ttk.Label(parent, textvariable=self.command_status_var, style="PanelText.TLabel", wraplength=260, justify="left").grid(row=11, column=0, sticky="w")

        ttk.Label(parent, text="Command Log", style="PanelTitle.TLabel").grid(row=12, column=0, sticky="w", pady=(22, 8))
        self.log_list = tk.Listbox(
            parent,
            listvariable=self.log_var,
            bg="#071929",
            fg=self.colors["text"],
            borderwidth=0,
            highlightthickness=0,
            selectbackground=self.colors["highlight"],
            font=("Consolas", 10),
            height=10,
        )
        self.log_list.grid(row=13, column=0, sticky="nsew")
        parent.rowconfigure(13, weight=1)

    def build_workspace(self, parent: ttk.Frame) -> None:
        parent.rowconfigure(1, weight=1)
        parent.columnconfigure(0, weight=1)

        top = ttk.Frame(parent, style="Panel.TFrame")
        top.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        top.columnconfigure(0, weight=1)
        ttk.Label(top, text="Telemetry Windows", style="PanelTitle.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(top, text="Cards can be dragged anywhere in the workspace and their positions are saved locally.", style="PanelText.TLabel").grid(row=1, column=0, sticky="w")

        self.workspace_container = ttk.Frame(parent, style="Panel.TFrame")
        self.workspace_container.grid(row=1, column=0, sticky="nsew")
        self.workspace_container.columnconfigure(0, weight=1)
        self.workspace_container.rowconfigure(0, weight=1)

        self.workspace_canvas = tk.Canvas(
            self.workspace_container,
            background=self.colors["panel"],
            highlightthickness=0,
            borderwidth=0,
        )
        scrollbar = ttk.Scrollbar(self.workspace_container, orient="vertical", command=self.workspace_canvas.yview)
        self.workspace_canvas.configure(yscrollcommand=scrollbar.set)

        self.workspace_canvas.grid(row=0, column=0, sticky="nsew")
        scrollbar.grid(row=0, column=1, sticky="ns")

        self.workspace_frame = ttk.Frame(self.workspace_canvas, style="Panel.TFrame", width=1200, height=900)
        self.workspace_window = self.workspace_canvas.create_window((0, 0), window=self.workspace_frame, anchor="nw")

        self.workspace_frame.bind("<Configure>", self.on_workspace_configure)
        self.workspace_canvas.bind("<Configure>", self.on_workspace_canvas_configure)

    def build_visual_page(self, parent: ttk.Frame) -> None:
        parent.rowconfigure(1, weight=1)
        parent.columnconfigure(0, weight=1)

        summary_shell = ttk.Frame(parent, style="Panel.TFrame", padding=12)
        summary_shell.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        for column in range(6):
            summary_shell.columnconfigure(column, weight=1, uniform="visual")

        self.build_top_summary_item(summary_shell, 0, "Status", self.visual_summary_vars["status"])
        self.build_top_summary_item(summary_shell, 1, "Route", self.visual_summary_vars["route"])
        self.build_top_summary_item(summary_shell, 2, "Altitude", self.visual_summary_vars["altitude"])
        self.build_top_summary_item(summary_shell, 3, "Downrange", self.visual_summary_vars["downrange"])
        self.build_top_summary_item(summary_shell, 4, "Delta-v / Speed", self.visual_summary_vars["speed"])
        self.build_top_summary_item(summary_shell, 5, "Samples", self.visual_summary_vars["samples"])

        graph_shell = ttk.Frame(parent, style="Panel.TFrame", padding=12)
        graph_shell.grid(row=1, column=0, sticky="nsew")
        graph_shell.rowconfigure(0, weight=1)
        graph_shell.columnconfigure(0, weight=1)

        self.flight_graph_canvas = tk.Canvas(
            graph_shell,
            background="#06111d",
            highlightthickness=0,
            borderwidth=0,
        )
        self.flight_graph_canvas.grid(row=0, column=0, sticky="nsew")
        self.flight_graph_canvas.bind("<Configure>", self.on_flight_graph_configure)

    def build_launch_rules_page(self, parent: ttk.Frame) -> None:
        parent.rowconfigure(2, weight=1)
        parent.columnconfigure(0, weight=1)

        summary_shell = ttk.Frame(parent, style="Panel.TFrame", padding=12)
        summary_shell.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        for column in range(5):
            summary_shell.columnconfigure(column, weight=1, uniform="rules")

        self.build_top_summary_item(summary_shell, 0, "Status", self.launch_rules_summary_vars["status"])
        self.build_top_summary_item(summary_shell, 1, "Gate", self.launch_rules_summary_vars["gate"])
        self.build_top_summary_item(summary_shell, 2, "Readiness", self.launch_rules_summary_vars["readiness"])
        self.build_top_summary_item(summary_shell, 3, "Manifest", self.launch_rules_summary_vars["manifest"])
        self.build_top_summary_item(summary_shell, 4, "Margin", self.launch_rules_summary_vars["margin"])

        notes_shell = ttk.Frame(parent, style="Panel.TFrame", padding=12)
        notes_shell.grid(row=1, column=0, sticky="ew", pady=(0, 10))
        notes_shell.columnconfigure(0, weight=1)
        ttk.Label(notes_shell, text="T-60 Launch Rule Check", style="PanelTitle.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(
            notes_shell,
            textvariable=self.launch_rules_note_var,
            style="PanelText.TLabel",
            wraplength=1000,
            justify="left",
        ).grid(row=1, column=0, sticky="w", pady=(6, 0))

        table_shell = ttk.Frame(parent, style="Panel.TFrame", padding=12)
        table_shell.grid(row=2, column=0, sticky="nsew")
        table_shell.rowconfigure(0, weight=1)
        table_shell.columnconfigure(0, weight=1)

        columns = ("criterion", "status", "details")
        self.launch_rules_tree = ttk.Treeview(table_shell, columns=columns, show="headings", height=14)
        self.launch_rules_tree.heading("criterion", text="Criterion")
        self.launch_rules_tree.heading("status", text="Status")
        self.launch_rules_tree.heading("details", text="Details")
        self.launch_rules_tree.column("criterion", width=280, anchor="w", stretch=False)
        self.launch_rules_tree.column("status", width=120, anchor="center", stretch=False)
        self.launch_rules_tree.column("details", width=900, anchor="w", stretch=True)

        rules_scrollbar = ttk.Scrollbar(table_shell, orient="vertical", command=self.launch_rules_tree.yview)
        self.launch_rules_tree.configure(yscrollcommand=rules_scrollbar.set)
        self.launch_rules_tree.grid(row=0, column=0, sticky="nsew")
        rules_scrollbar.grid(row=0, column=1, sticky="ns")

    def on_flight_graph_configure(self, _event: tk.Event) -> None:
        self.draw_flight_graph()

    def build_top_summary_item(self, parent: ttk.Frame, column: int, label_text: str, variable: tk.StringVar) -> None:
        block = ttk.Frame(parent, style="Panel.TFrame", padding=8)
        block.grid(row=0, column=column, sticky="nsew")
        ttk.Label(block, text=label_text, style="HeroMeta.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(block, textvariable=variable, style="PanelText.TLabel", wraplength=220, justify="left").grid(row=1, column=0, sticky="w", pady=(6, 0))

    def refresh_visual_page(self) -> None:
        flight_data = self.current_bundle.get("vehicle_flight", {})
        flight_points = self.load_flight_log_points()
        forecast_rows = self.load_launch_forecast_rows()

        if self.flight_online and flight_points:
            latest_point = flight_points[-1]
            status_text = str(flight_data.get("status", "Logging")).replace("_", " ").upper()
            self.visual_summary_vars["status"].set(status_text)
            self.visual_summary_vars["route"].set("Live flight log")
            self.visual_summary_vars["altitude"].set(self.format_distance_label(latest_point.get("altitude_m", 0.0)))
            self.visual_summary_vars["downrange"].set(self.format_distance_label(latest_point.get("downrange_m", 0.0)))
            self.visual_summary_vars["speed"].set(self.format_speed_label(latest_point.get("surface_speed_mps", 0.0)))
            self.visual_summary_vars["samples"].set(f"{len(flight_points)} samples")
            self.flight_log_points = flight_points
            if hasattr(self, "flight_graph_canvas"):
                self.draw_flight_graph(flight_points)
            return

        self.launch_forecast_rows = forecast_rows
        points: list[dict[str, float]] = []

        if forecast_rows:
            latest_row = forecast_rows[-1]
            points = self.parse_launch_forecast_points(str(latest_row.get("route_points", "")))
            status_text = str(latest_row.get("route_status", "FORECAST")).replace("_", " ").upper()
            self.visual_summary_vars["status"].set(status_text)
            self.visual_summary_vars["route"].set(str(latest_row.get("route_name", "No forecast route")))
            self.visual_summary_vars["altitude"].set(self.format_distance_label(latest_row.get("predicted_altitude_m", 0.0)))
            self.visual_summary_vars["downrange"].set(self.format_distance_label(latest_row.get("predicted_downrange_m", 0.0)))
            self.visual_summary_vars["speed"].set(self.format_speed_label(latest_row.get("estimated_delta_v_mps", 0.0)))
            self.visual_summary_vars["samples"].set(f"{len(points)} route points")
        else:
            if flight_points:
                latest_point = flight_points[-1]
                self.visual_summary_vars["status"].set("LAST FLIGHT")
                self.visual_summary_vars["route"].set("Archived flight log")
                self.visual_summary_vars["altitude"].set(self.format_distance_label(latest_point.get("altitude_m", 0.0)))
                self.visual_summary_vars["downrange"].set(self.format_distance_label(latest_point.get("downrange_m", 0.0)))
                self.visual_summary_vars["speed"].set(self.format_speed_label(latest_point.get("surface_speed_mps", 0.0)))
                self.visual_summary_vars["samples"].set(f"{len(flight_points)} samples")
                points = flight_points
            else:
                status_text = str(flight_data.get("status", "Awaiting flight data")).replace("_", " ").strip()
                self.visual_summary_vars["status"].set(status_text.title())
                self.visual_summary_vars["route"].set("Awaiting launch forecast")
                self.visual_summary_vars["altitude"].set(self.format_distance_label(flight_data.get("altitude", 0.0)))
                self.visual_summary_vars["downrange"].set(self.format_distance_label(flight_data.get("downrange_distance_m", 0.0)))
                self.visual_summary_vars["speed"].set(self.format_speed_label(flight_data.get("surface_speed", 0.0)))
                self.visual_summary_vars["samples"].set("0 route points")
        self.flight_log_points = points

        if hasattr(self, "flight_graph_canvas"):
            self.draw_flight_graph(points)

    def refresh_launch_rules_page(self) -> None:
        if not hasattr(self, "launch_rules_tree"):
            return

        tower = self.current_bundle.get("tower", {})
        vehicle = self.current_bundle.get("vehicle", {})
        gate_record = self.current_bundle.get("launch_rule_check", {})

        countdown_armed = self.is_truthy(tower.get("countdown_armed"))
        tower_seconds = self.safe_float(tower.get("seconds_to_window"))
        gate_armed = countdown_armed and tower_seconds is not None and tower_seconds > 3600
        gate_triggered = self.is_truthy(gate_record.get("gate_triggered"))
        manifest_valid = self.is_truthy(gate_record.get("manifest_valid"))
        all_rules_met = self.is_truthy(gate_record.get("all_rules_met"))
        pending_gate = gate_armed and not gate_triggered

        readiness_state = str(
            gate_record.get(
                "readiness_status_text",
                vehicle.get("readiness_status_text", vehicle.get("readiness_summary_text", "Awaiting diagnostics")),
            )
        ).strip().upper()
        readiness_summary = str(gate_record.get("readiness_summary_text", vehicle.get("readiness_summary_text", "Awaiting diagnostics")))
        gate_status = str(gate_record.get("status", "INACTIVE")).strip().upper()
        gate_result_text = str(gate_record.get("gate_result_text", "Awaiting T-60 launch rule snapshot."))
        delta_v_margin = gate_record.get("readiness_delta_v_margin_mps", vehicle.get("readiness_delta_v_margin_mps", 0))
        liftoff_twr = gate_record.get("readiness_liftoff_twr", vehicle.get("readiness_liftoff_twr", 0))
        operator_text = str(vehicle.get("operator_status_text", tower.get("operator_status_text", "READY")))

        if gate_triggered:
            gate_summary = "T-60 gate snapshot captured"
        elif gate_armed:
            gate_summary = "Countdown started above T-60; awaiting the gate snapshot"
            gate_status = "PENDING"
        elif countdown_armed:
            gate_summary = "Countdown started at or below T-60; gate check not required"
            gate_status = "NOT REQUIRED"
        else:
            gate_summary = "Awaiting tower countdown"
            gate_status = "INACTIVE"

        self.launch_rules_summary_vars["status"].set(gate_status.replace("_", " "))
        self.launch_rules_summary_vars["gate"].set(gate_summary)
        self.launch_rules_summary_vars["readiness"].set(readiness_state if readiness_state else "AWAITING DIAGNOSTICS")
        if gate_triggered:
            self.launch_rules_summary_vars["manifest"].set("PASS" if manifest_valid else "FAIL")
        elif pending_gate:
            self.launch_rules_summary_vars["manifest"].set("PENDING")
        elif countdown_armed:
            self.launch_rules_summary_vars["manifest"].set("N/A")
        else:
            self.launch_rules_summary_vars["manifest"].set("INACTIVE")
        self.launch_rules_summary_vars["margin"].set(self.format_speed_label(delta_v_margin))
        self.launch_rules_note_var.set(
            gate_result_text if gate_triggered else (
                "The T-60 launch rule snapshot is written only when the countdown starts above 60 minutes."
                if gate_armed
                else gate_summary + "."
            )
        )

        rows: list[tuple[str, str, str]] = []

        def add_rule(label: str, passed: bool | None, detail: str) -> None:
            if passed is None:
                status_text = "PENDING" if pending_gate else "N/A"
            else:
                status_text = "PASS" if passed else "FAIL"
            rows.append((label, status_text, detail))

        add_rule("Tower countdown armed", countdown_armed if (countdown_armed or pending_gate or gate_triggered) else None, f"{tower.get('formatted_countdown', 'T-00:00:00')} | {operator_text}")
        add_rule("T-60 gate required", (gate_armed or gate_triggered) if (countdown_armed or pending_gate or gate_triggered) else None, gate_summary)
        add_rule("Manifest valid", manifest_valid if gate_triggered else None, "Pending gate snapshot" if pending_gate else str(manifest_valid))
        add_rule("Readiness state GO", readiness_state == "GO" if gate_triggered else None, readiness_state)
        add_rule("Launch TWR meets minimum", (self.is_truthy(gate_record.get("liftoff_twr_ok")) or float(liftoff_twr or 0) >= 1.15) if gate_triggered else None, f"{float(liftoff_twr or 0):.2f}")
        add_rule("Delta-v margin non-negative", (self.is_truthy(gate_record.get("delta_v_margin_ok")) or float(delta_v_margin or 0) >= 0) if gate_triggered else None, self.format_speed_label(delta_v_margin))
        add_rule("Countdown hold clear", (not self.is_truthy(gate_record.get("countdown_hold_active", tower.get("countdown_hold_active")))) if gate_triggered else None, f"Hold active: {self.is_truthy(gate_record.get('countdown_hold_active', tower.get('countdown_hold_active')))}")
        add_rule("Abort clear", (not self.is_truthy(gate_record.get("abort_active", tower.get("abort_active")))) if gate_triggered else None, f"Abort active: {self.is_truthy(gate_record.get('abort_active', tower.get('abort_active')))}")
        add_rule("All required rules met", all_rules_met if gate_triggered else None, gate_result_text)

        for row_id in self.launch_rules_tree.get_children():
            self.launch_rules_tree.delete(row_id)

        for criterion, status_text, detail in rows:
            self.launch_rules_tree.insert("", "end", values=(criterion, status_text, detail))

        if gate_triggered and all_rules_met:
            current_status = "PASS"
        elif gate_triggered:
            current_status = "FAIL"
        elif gate_armed:
            current_status = "PENDING"
        elif countdown_armed:
            current_status = "NOT REQUIRED"
        else:
            current_status = "INACTIVE"
        self.launch_rules_summary_vars["status"].set(current_status)

    def load_flight_log_points(self) -> list[dict[str, float]]:
        if not self.flight_log_path.exists():
            return []

        try:
            with self.flight_log_path.open("r", encoding="utf-8", newline="") as handle:
                reader = csv.DictReader(handle)
                points: list[dict[str, float]] = []
                for row in reader:
                    altitude_m = self.safe_float(row.get("altitude_m"))
                    downrange_m = self.safe_float(row.get("downrange_m"))
                    if altitude_m is None or downrange_m is None:
                        continue

                    points.append(
                        {
                            "sample_index": float(self.safe_float(row.get("sample_index")) or len(points)),
                            "mission_elapsed_seconds": float(self.safe_float(row.get("mission_elapsed_seconds")) or 0.0),
                            "altitude_m": altitude_m,
                            "downrange_m": downrange_m,
                            "vertical_speed_mps": float(self.safe_float(row.get("vertical_speed_mps")) or 0.0),
                            "surface_speed_mps": float(self.safe_float(row.get("surface_speed_mps")) or 0.0),
                            "apoapsis_m": float(self.safe_float(row.get("apoapsis_m")) or 0.0),
                            "periapsis_m": float(self.safe_float(row.get("periapsis_m")) or 0.0),
                            "latitude_deg": float(self.safe_float(row.get("latitude_deg")) or 0.0),
                            "longitude_deg": float(self.safe_float(row.get("longitude_deg")) or 0.0),
                        }
                    )
        except OSError:
            return []

        return points

    def load_launch_forecast_rows(self) -> list[dict[str, Any]]:
        if not self.forecast_path.exists():
            return []

        try:
            with self.forecast_path.open("r", encoding="utf-8", newline="") as handle:
                reader = csv.DictReader(handle)
                rows: list[dict[str, Any]] = []
                for row in reader:
                    if not row:
                        continue
                    rows.append(row)
        except OSError:
            return []

        return rows

    def parse_launch_forecast_points(self, route_points_text: str) -> list[dict[str, float]]:
        points: list[dict[str, float]] = []
        if not route_points_text.strip():
            return points

        for raw_pair in route_points_text.split(";"):
            if "|" not in raw_pair:
                continue
            downrange_text, altitude_text = raw_pair.split("|", 1)
            downrange_m = self.safe_float(downrange_text)
            altitude_m = self.safe_float(altitude_text)
            if downrange_m is None or altitude_m is None:
                continue
            points.append(
                {
                    "sample_index": float(len(points)),
                    "mission_elapsed_seconds": 0.0,
                    "altitude_m": altitude_m,
                    "downrange_m": downrange_m,
                    "vertical_speed_mps": 0.0,
                    "surface_speed_mps": 0.0,
                    "apoapsis_m": 0.0,
                    "periapsis_m": 0.0,
                    "latitude_deg": 0.0,
                    "longitude_deg": 0.0,
                }
            )

        return points

    def draw_flight_graph(self, points: list[dict[str, float]] | None = None) -> None:
        if not hasattr(self, "flight_graph_canvas"):
            return

        canvas = self.flight_graph_canvas
        canvas.delete("all")

        width = max(canvas.winfo_width(), 800)
        height = max(canvas.winfo_height(), 480)
        canvas.configure(width=width, height=height)

        plot_left = 76
        plot_top = 24
        plot_right = 28
        plot_bottom = 54
        plot_width = max(10, width - plot_left - plot_right)
        plot_height = max(10, height - plot_top - plot_bottom)

        if points is None:
            points = self.flight_log_points

        if not points:
            canvas.create_text(
                width / 2,
                height / 2 - 12,
                text="Awaiting flight log",
                fill=self.colors["muted"],
                font=("Segoe UI", 16, "bold"),
            )
            canvas.create_text(
                width / 2,
                height / 2 + 18,
                text="The data CPU will populate vehicle_flight_log.csv during ascent.",
                fill=self.colors["muted"],
                font=("Segoe UI", 11),
            )
            return

        x_values = [point["downrange_m"] / 1000.0 for point in points]
        y_values = [point["altitude_m"] / 1000.0 for point in points]
        max_x = max(max(x_values), 1.0)
        max_y = max(max(y_values), 1.0)
        x_scale = plot_width / max_x
        y_scale = plot_height / max_y

        def project(point: dict[str, float]) -> tuple[float, float]:
            x_value = point["downrange_m"] / 1000.0
            y_value = point["altitude_m"] / 1000.0
            x_pos = plot_left + (x_value * x_scale)
            y_pos = plot_top + plot_height - (y_value * y_scale)
            return x_pos, y_pos

        for tick in range(6):
            x = plot_left + (plot_width * tick / 5)
            y = plot_top + (plot_height * tick / 5)
            canvas.create_line(x, plot_top, x, plot_top + plot_height, fill="#10273d", width=1)
            canvas.create_line(plot_left, y, plot_left + plot_width, y, fill="#10273d", width=1)

        canvas.create_line(plot_left, plot_top, plot_left, plot_top + plot_height, fill="#3d5f7b", width=2)
        canvas.create_line(plot_left, plot_top + plot_height, plot_left + plot_width, plot_top + plot_height, fill="#3d5f7b", width=2)

        path_points: list[float] = []
        for point in points:
            x_pos, y_pos = project(point)
            path_points.extend((x_pos, y_pos))

        if len(path_points) >= 4:
            canvas.create_line(*path_points, fill=self.colors["accent"], width=2, smooth=True)

        for index, point in enumerate(points[-30:]):
            x_pos, y_pos = project(point)
            radius = 3 if index < len(points[-30:]) - 1 else 5
            fill_color = self.colors["gold"] if index < len(points[-30:]) - 1 else self.colors["highlight"]
            canvas.create_oval(x_pos - radius, y_pos - radius, x_pos + radius, y_pos + radius, fill=fill_color, outline="")

        latest_point = points[-1]
        latest_x, latest_y = project(latest_point)
        canvas.create_text(
            latest_x + 8,
            latest_y - 18,
            text=f"{latest_point['altitude_m'] / 1000.0:.1f} km",
            fill=self.colors["text"],
            anchor="w",
            font=("Consolas", 10, "bold"),
        )

        canvas.create_text(plot_left, height - 20, text="Downrange (km)", fill=self.colors["muted"], anchor="w", font=("Segoe UI", 11))
        canvas.create_text(20, plot_top + (plot_height / 2), text="Altitude (km)", fill=self.colors["muted"], anchor="w", angle=90, font=("Segoe UI", 11))
        canvas.create_text(
            plot_left,
            plot_top - 6,
            text=f"Max altitude: {max_y:.1f} km",
            fill=self.colors["muted"],
            anchor="w",
            font=("Segoe UI", 10),
        )
        canvas.create_text(
            width - plot_right,
            height - 20,
            text=f"Latest: {latest_point['downrange_m'] / 1000.0:.1f} km downrange",
            fill=self.colors["muted"],
            anchor="e",
            font=("Segoe UI", 10),
        )

    @staticmethod
    def safe_float(value: Any) -> float | None:
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def format_distance_label(value_m: Any) -> str:
        try:
            meters = float(value_m)
        except (TypeError, ValueError):
            return "0 m"

        if abs(meters) >= 1000:
            return f"{meters / 1000:.1f} km"
        return f"{meters:.0f} m"

    @staticmethod
    def format_speed_label(value_mps: Any) -> str:
        try:
            meters_per_second = float(value_mps)
        except (TypeError, ValueError):
            return "0 m/s"

        return f"{meters_per_second:.1f} m/s"

    def on_workspace_configure(self, _event: tk.Event) -> None:
        self.workspace_canvas.configure(scrollregion=self.workspace_canvas.bbox("all"))

    def on_workspace_canvas_configure(self, event: tk.Event) -> None:
        self.workspace_canvas.itemconfigure(self.workspace_window, width=max(event.width, self.workspace_frame.winfo_reqwidth()))
        self.refresh_workspace_bounds()

    def add_data_card(
        self,
        preferred_field: str | None,
        card_id: str | None = None,
        position: tuple[int, int] | None = None,
        size: tuple[int, int] | None = None,
    ) -> None:
        field_options = self.available_fields()
        initial_field = preferred_field or (field_options[0] if field_options else "tower.formatted_countdown")
        initial_position = position if self.is_valid_saved_position(position) else self.next_card_position()
        card = DataCard(self, self.workspace_frame, initial_field, card_id or self.next_card_id(), initial_position, size=size)
        card.update_hierarchy(self.field_catalog, preserve_field=initial_field)
        self.data_cards.append(card)
        self.place_card(card)
        self.refresh_data_cards()
        self.save_layout_state()

    def remove_data_card(self, card: DataCard) -> None:
        self.data_cards = [existing for existing in self.data_cards if existing is not card]
        self.refresh_workspace_bounds()
        self.save_layout_state()

    def refresh_data_cards(self) -> None:
        for card in self.data_cards:
            card.update_hierarchy(self.field_catalog)
            card.update_value(self.flattened_data)

    def move_card(self, card: DataCard, x_pos: int, y_pos: int) -> None:
        card.pos_x = max(12, x_pos)
        card.pos_y = max(12, y_pos)
        self.place_card(card)
        self.refresh_workspace_bounds()

    def resize_card(self, card: DataCard, width: int, height: int) -> None:
        card.width = max(DataCard.MIN_WIDTH, int(width))
        card.height = max(DataCard.MIN_HEIGHT, int(height))
        self.place_card(card)
        self.refresh_workspace_bounds()

    def place_card(self, card: DataCard) -> None:
        card.frame.place(x=card.pos_x, y=card.pos_y, width=card.width, height=card.height)
        self.refresh_workspace_bounds()

    def refresh_workspace_bounds(self) -> None:
        if not hasattr(self, "workspace_frame"):
            return

        required_width = max(self.workspace_canvas.winfo_width(), 1200)
        required_height = max(self.workspace_canvas.winfo_height(), 900)

        for card in self.data_cards:
            card_width = max(card.width, card.frame.winfo_reqwidth(), DataCard.MIN_WIDTH)
            card_height = max(card.height, card.frame.winfo_reqheight(), DataCard.MIN_HEIGHT)
            required_width = max(required_width, card.pos_x + card_width + 24)
            required_height = max(required_height, card.pos_y + card_height + 24)

        self.workspace_frame.configure(width=required_width, height=required_height)
        self.workspace_canvas.itemconfigure(self.workspace_window, width=required_width, height=required_height)
        self.workspace_canvas.configure(scrollregion=(0, 0, required_width, required_height))

    def available_fields(self) -> list[str]:
        keys = sorted(key for key in self.known_fields if key)
        if not keys:
            return [
                "tower.formatted_countdown",
                "tower.operator_status_text",
                "vehicle.mode",
                "vehicle.altitude",
                "vehicle_flight.altitude",
                "vehicle_flight.downrange_distance_m",
            ]
        return keys

    def stringify_value(self, value: Any) -> str:
        if isinstance(value, bool):
            return "TRUE" if value else "FALSE"
        if isinstance(value, float):
            return f"{value:.2f}"
        return str(value)

    @staticmethod
    def is_missing_value(value: Any) -> bool:
        if value is None:
            return True
        if isinstance(value, str):
            normalized = value.strip().upper()
            return normalized in {"", "N/A", "NA", "NONE", "NULL"}
        return False

    def send_hold(self) -> None:
        if not self.ensure_tower_online("Hold"):
            return
        self.dispatch_command("hold")

    def send_resume(self) -> None:
        if not self.ensure_tower_online("Resume"):
            return
        self.dispatch_command("resume")

    def send_start_countdown(self) -> None:
        if not self.ensure_tower_online("Arm Tower"):
            return
        target_body = self.target_body_var.get()
        launch_window_mode = self.resolve_launch_window_mode(target_body)

        countdown_seconds: int | None = None
        command_name = "start_countdown"
        if launch_window_mode == "MANUAL_COUNTDOWN":
            try:
                countdown_seconds = parse_countdown_to_seconds(self.countdown_var.get())
            except ValueError as exc:
                messagebox.showerror("Invalid Countdown", str(exc))
                return
            command_name = "set_countdown"

        self.dispatch_command(command_name, countdown_seconds, target_body, launch_window_mode)

    def send_abort(self) -> None:
        if not self.ensure_tower_online("Abort"):
            return
        self.dispatch_command("abort")

    def send_set_countdown(self) -> None:
        if not self.ensure_tower_online("Apply Tower Count"):
            return
        try:
            countdown_seconds = parse_countdown_to_seconds(self.countdown_var.get())
        except ValueError as exc:
            messagebox.showerror("Invalid Countdown", str(exc))
            return

        self.dispatch_command("set_countdown", countdown_seconds, self.target_body_var.get(), "MANUAL_COUNTDOWN")

    def dispatch_command(
        self,
        command_name: str,
        countdown_seconds: int | None = None,
        target_body: str | None = None,
        launch_window_mode: str | None = None,
    ) -> None:
        vehicle_id = VEHICLES[self.selected_vehicle_name.get()]["vehicle_id"]
        payload = self.bridge.send_command(command_name, vehicle_id, countdown_seconds, target_body, launch_window_mode)
        command_text = {
            "start_countdown": "ARM TOWER",
            "set_countdown": "ARM TOWER COUNT",
            "hold": "HOLD TOWER",
            "resume": "RESUME TOWER",
            "abort": "ABORT",
        }.get(command_name, command_name.replace("_", " ").upper())
        if countdown_seconds is not None:
            command_text = f"{command_text} {format_countdown(countdown_seconds)}"
        if target_body:
            command_text = f"{command_text} | TARGET {target_body.upper()}"
        if launch_window_mode == "RELATIVE_INCLINATION":
            command_text = f"{command_text} | WINDOWED"
        self.command_status_var.set(f"Command queued: {command_text} | Revision {payload['command_revision']}")
        self.push_log(self.command_status_var.get())

        if command_name in {"start_countdown", "set_countdown", "abort", "hold", "resume"}:
            if self.pending_command_clear is not None:
                self.after_cancel(self.pending_command_clear)
            self.pending_command_clear = self.after(1500, self.clear_active_command)

    def clear_active_command(self) -> None:
        vehicle_id = VEHICLES[self.selected_vehicle_name.get()]["vehicle_id"]
        payload = self.bridge.clear_command(vehicle_id)
        self.pending_command_clear = None
        self.push_log(f"Command auto-cleared | Revision {payload['command_revision']}")

    def push_log(self, entry: str) -> None:
        self.log_items.insert(0, entry)
        self.log_items = self.log_items[:12]
        self.log_var.set(self.log_items)

    def poll_bridge(self) -> None:
        self.current_bundle = self.bridge.read_bundle()
        self.flattened_data = self.flatten_bundle(self.current_bundle)
        self.known_fields.update(key for key in self.flattened_data.keys() if key)
        self.field_catalog = self.build_field_catalog(self.known_fields)
        tower_data = self.current_bundle.get("tower", {})
        vehicle_data = self.current_bundle.get("vehicle", {})
        flight_data = self.current_bundle.get("vehicle_flight", {})
        self.tower_online = self.is_tower_online(tower_data)
        self.vehicle_online = self.is_vehicle_online(vehicle_data)
        self.flight_online = self.is_flight_online(flight_data)
        self.vehicle_session_active = self.is_vehicle_session_active(tower_data, vehicle_data, flight_data)
        if not self.vehicle_session_active:
            self.clear_vehicle_cache()
        self.update_summary()
        self.refresh_data_cards()
        self.refresh_launch_rules_page()
        self.refresh_visual_page()
        self.after(500, self.poll_bridge)

    def update_summary(self) -> None:
        tower = self.current_bundle.get("tower", {})
        vehicle = self.current_bundle.get("vehicle", {})
        flight = self.current_bundle.get("vehicle_flight", {})
        target_body = tower.get("target_body")
        if isinstance(target_body, str) and target_body in TARGET_BODY_OPTIONS:
            self.target_body_var.set(target_body)
        self.summary_vars["vehicle"].set(self.selected_vehicle_name.get())
        tower_mode_text = str(tower.get("mode_status_text", tower.get("status", "offline")))
        if not self.tower_online:
            tower_mode_text = "Tower CPU not running"
        self.summary_vars["tower_mode"].set(tower_mode_text)
        self.summary_vars["countdown"].set(self.resolve_primary_clock_display())
        if self.vehicle_online:
            vehicle_mode_text = str(vehicle.get("mode", vehicle.get("status", "online")))
        elif self.flight_online:
            vehicle_mode_text = str(flight.get("mode", flight.get("status", "logging")))
        elif not self.vehicle_session_active:
            vehicle_mode_text = "Awaiting tower handoff"
        else:
            vehicle_mode_text = "Vehicle telemetry stale"
        self.summary_vars["vehicle_mode"].set(vehicle_mode_text)

        if self.vehicle_session_active:
            operator_text = str(vehicle.get("operator_status_text", tower.get("operator_status_text", "READY")))
            wet_dress_text = str(vehicle.get("wet_dress_status_text", "")).strip()
            if wet_dress_text and wet_dress_text.upper() != "DISABLED":
                operator_text = f"{operator_text} | {wet_dress_text}"
        else:
            operator_text = str(tower.get("operator_status_text", "READY"))
        self.summary_vars["operator"].set(operator_text)
        if not self.vehicle_session_active:
            readiness_text = "Awaiting tower handoff"
        else:
            readiness_text = str(vehicle.get("readiness_summary_text", vehicle.get("readiness_status_text", "Awaiting diagnostics")))
            vehicle_mode_value = str(vehicle.get("mode", vehicle.get("status", "online")))
            if not vehicle_mode_value.startswith("TERMINAL_COUNTDOWN"):
                readiness_text = f"Snapshot: {readiness_text}"
        self.summary_vars["readiness"].set(readiness_text)
        if not self.tower_online:
            self.command_status_var.set("Tower script is offline. Start tower_main.ks via AG6/boot before using app tower control.")

    @staticmethod
    def resolve_launch_window_mode(target_body: str) -> str:
        if target_body == "Earth":
            return "MANUAL_COUNTDOWN"
        return "RELATIVE_INCLINATION"

    def flatten_bundle(self, value: dict[str, Any]) -> dict[str, Any]:
        flattened: dict[str, Any] = {}

        def walk(prefix: str, current: Any) -> None:
            if isinstance(current, dict):
                for key, child in current.items():
                    child_prefix = f"{prefix}.{key}" if prefix else key
                    walk(child_prefix, child)
                return
            if isinstance(current, list):
                for index, child in enumerate(current):
                    child_prefix = f"{prefix}[{index}]"
                    walk(child_prefix, child)
                return
            flattened[prefix] = current

        walk("", value)
        return flattened

    def build_field_catalog(self, fields: set[str]) -> dict[str, dict[str, list[str]]]:
        catalog: dict[str, dict[str, list[str]]] = {}

        for field in sorted(field for field in fields if field):
            source_name, section_name, metric_name = DataCard._split_field_key(field)
            if not source_name or not metric_name:
                continue

            if source_name not in catalog:
                catalog[source_name] = {}
            if section_name not in catalog[source_name]:
                catalog[source_name][section_name] = []
            if metric_name not in catalog[source_name][section_name]:
                catalog[source_name][section_name].append(metric_name)

        for source_name in catalog:
            for section_name in catalog[source_name]:
                catalog[source_name][section_name].sort()

        return catalog


    def resolve_primary_clock_display(self) -> str:
        tower = self.current_bundle.get("tower", {})
        vehicle = self.current_bundle.get("vehicle", {})
        flight = self.current_bundle.get("vehicle_flight", {})
        cache_key = "_summary.primary_clock"

        if self.should_force_tower_countdown(tower):
            tower_countdown = tower.get("formatted_countdown")
            if isinstance(tower_countdown, str) and tower_countdown.strip().startswith(("T-", "T+")):
                self.last_known_values[cache_key] = tower_countdown.strip()
                return tower_countdown.strip()

            tower_seconds = tower.get("seconds_to_window")
            if not self.is_missing_value(tower_seconds):
                fallback_clock = self.format_signed_clock_from_seconds(tower_seconds)
                self.last_known_values[cache_key] = fallback_clock
                return fallback_clock

            return "T-00:00:00"

        flight_event_time = flight.get("formatted_event_time")
        if self.flight_online and isinstance(flight_event_time, str) and flight_event_time.startswith("T"):
            self.last_known_values[cache_key] = flight_event_time
            return flight_event_time

        vehicle_event_time = vehicle.get("formatted_event_time")
        if self.vehicle_online and isinstance(vehicle_event_time, str) and vehicle_event_time.startswith("T"):
            self.last_known_values[cache_key] = vehicle_event_time
            return vehicle_event_time

        return self.last_known_values.get(cache_key, "T-00:00:00")

    def should_force_tower_countdown(self, tower_data: dict[str, Any]) -> bool:
        if not self.tower_online:
            return False

        countdown_mode = str(tower_data.get("countdown_mode", "")).strip().upper()
        mode_status = str(tower_data.get("mode_status_text", tower_data.get("status", ""))).strip().upper()
        countdown_armed = self.is_truthy(tower_data.get("countdown_armed"))
        countdown_hold = self.is_truthy(tower_data.get("countdown_hold_active"))
        abort_active = self.is_truthy(tower_data.get("abort_active"))
        formatted_countdown = str(tower_data.get("formatted_countdown", "")).strip()
        seconds_to_window = tower_data.get("seconds_to_window")

        if abort_active:
            return True

        if countdown_mode == "MANUAL_COUNTDOWN":
            if formatted_countdown.startswith(("T-", "T+")):
                return True
            if not self.is_missing_value(seconds_to_window):
                return True
            if countdown_armed or countdown_hold:
                return True

        if "COUNTDOWN" in mode_status or "HOLD" in mode_status:
            if formatted_countdown.startswith(("T-", "T+")):
                return True
            if not self.is_missing_value(seconds_to_window):
                return True
            if countdown_armed or countdown_hold:
                return True

        return False

    @staticmethod
    def format_signed_clock_from_seconds(value: Any) -> str:
        try:
            total_seconds = float(value)
        except (TypeError, ValueError):
            return "T-00:00:00"

        sign = "T-" if total_seconds >= 0 else "T+"
        total_seconds = abs(total_seconds)

        whole_seconds = int(total_seconds)
        hours = whole_seconds // 3600
        minutes = (whole_seconds % 3600) // 60
        seconds = whole_seconds % 60
        return f"{sign}{hours:02d}:{minutes:02d}:{seconds:02d}"


    def resolve_field_display_value(self, key: str, flattened_data: dict[str, Any]) -> Any:
        if not key:
            return "N/A"

        source_name = key.split(".", 1)[0] if "." in key else ""

        if key.endswith("formatted_countdown"):
            if source_name == "tower" and self.should_force_tower_countdown(self.current_bundle.get("tower", {})):
                tower = self.current_bundle.get("tower", {})
                tower_value = tower.get("formatted_countdown")
                if isinstance(tower_value, str) and tower_value.strip().startswith(("T-", "T+")):
                    self.last_known_values[key] = tower_value.strip()
                    return tower_value.strip()

                tower_seconds = tower.get("seconds_to_window")
                if not self.is_missing_value(tower_seconds):
                    display_value = self.format_signed_clock_from_seconds(tower_seconds)
                    self.last_known_values[key] = display_value
                    return display_value

            primary_clock = self.resolve_primary_clock_display()
            if primary_clock:
                self.last_known_values[key] = primary_clock
                return primary_clock

        if self.is_vehicle_field(key) and not self.vehicle_session_active:
            return "Awaiting tower handoff"

        if key.endswith("formatted_event_time"):
            if source_name == "vehicle_flight":
                if not self.flight_online and not self.vehicle_session_active:
                    return "Awaiting flight data"
                flight_event_time = self.current_bundle.get("vehicle_flight", {}).get("formatted_event_time", flattened_data.get(key, "N/A"))
                if not self.is_missing_value(flight_event_time):
                    self.last_known_values[key] = flight_event_time
                    return flight_event_time
                return self.last_known_values.get(key, "N/A")

            if not self.vehicle_session_active:
                return "Awaiting tower handoff"
            vehicle_event_time = self.current_bundle.get("vehicle", {}).get("formatted_event_time", flattened_data.get(key, "N/A"))
            if not self.is_missing_value(vehicle_event_time):
                self.last_known_values[key] = vehicle_event_time
                return vehicle_event_time
            return self.last_known_values.get(key, "N/A")

        current_value = flattened_data.get(key, "N/A")
        if self.is_missing_value(current_value):
            if self.is_vehicle_field(key) and not self.vehicle_session_active:
                return "Awaiting tower handoff"
            return self.last_known_values.get(key, "N/A")

        self.last_known_values[key] = current_value
        return current_value
    def next_card_position(self) -> tuple[int, int]:
        index = len(self.data_cards)
        columns = 3
        card_width = DataCard.DEFAULT_WIDTH
        card_height = DataCard.DEFAULT_HEIGHT
        gutter = 20
        row = index // columns
        column = index % columns
        return (12 + (column * (card_width + gutter)), 12 + (row * (card_height + gutter)))

    def is_valid_saved_position(self, position: tuple[int, int] | None) -> bool:
        if position is None:
            return False

        x_pos, y_pos = position
        if x_pos < 0 or y_pos < 0:
            return False

        for existing_card in self.data_cards:
            if abs(existing_card.pos_x - x_pos) < 24 and abs(existing_card.pos_y - y_pos) < 24:
                return False

        return True

    def ensure_tower_online(self, action_name: str) -> bool:
        if self.tower_online:
            return True

        messagebox.showwarning(
            "Tower Offline",
            f"{action_name} requires the tower script to be running.\n\nStart the tower via AG6 or its boot script first. The vehicle waits for tower handoff.",
        )
        return False

    def is_tower_online(self, tower_data: dict[str, Any]) -> bool:
        if tower_data.get("source") != "tower":
            return False

        updated_at = str(tower_data.get("updated_at", "")).strip()
        now_seconds = datetime.now(timezone.utc).timestamp()

        if updated_at:
            if updated_at != self.last_tower_updated_at:
                self.last_tower_updated_at = updated_at
                self.last_tower_seen_at = now_seconds
        elif self.last_tower_seen_at <= 0:
            return False

        return (now_seconds - self.last_tower_seen_at) <= 10

    def is_vehicle_online(self, vehicle_data: dict[str, Any]) -> bool:
        if vehicle_data.get("source") != "vehicle":
            return False

        selected_vehicle_id = VEHICLES[self.selected_vehicle_name.get()]["vehicle_id"]
        vehicle_id = str(vehicle_data.get("vehicle_id", "")).strip()
        if vehicle_id and vehicle_id != selected_vehicle_id:
            return False

        updated_at = str(vehicle_data.get("updated_at", "")).strip()
        now_seconds = datetime.now(timezone.utc).timestamp()

        if updated_at:
            if updated_at != self.last_vehicle_updated_at:
                self.last_vehicle_updated_at = updated_at
                self.last_vehicle_seen_at = now_seconds
        elif self.last_vehicle_seen_at <= 0:
            return False

        return (now_seconds - self.last_vehicle_seen_at) <= 10

    def is_vehicle_session_active(self, tower_data: dict[str, Any], vehicle_data: dict[str, Any], flight_data: dict[str, Any]) -> bool:
        if self.vehicle_online:
            return True

        if self.flight_online:
            return True

        if not self.tower_online:
            return False

        if self.is_truthy(tower_data.get("countdown_armed")) or self.is_truthy(tower_data.get("countdown_hold_active")):
            return True

        if self.is_truthy(vehicle_data.get("engine_started")) or self.is_truthy(vehicle_data.get("pad_released")):
            return True

        if self.is_truthy(flight_data.get("logging_active")) or str(flight_data.get("status", "")).strip().lower() in {"logging", "active"}:
            return True

        vehicle_event_time = str(vehicle_data.get("formatted_event_time", "")).strip()
        return vehicle_event_time.startswith("T")

    def clear_vehicle_cache(self) -> None:
        self.last_known_values = {
            key: value
            for key, value in self.last_known_values.items()
            if not self.is_vehicle_field(key)
        }

    @staticmethod
    def is_vehicle_field(key: str) -> bool:
        return key.startswith("vehicle.") or key.startswith("vehicle_status.") or key.startswith("vehicle_flight.")

    def is_flight_online(self, flight_data: dict[str, Any]) -> bool:
        if flight_data.get("source") != "vehicle_flight":
            return False

        selected_vehicle_id = VEHICLES[self.selected_vehicle_name.get()]["vehicle_id"]
        vehicle_id = str(flight_data.get("vehicle_id", "")).strip()
        if vehicle_id and vehicle_id != selected_vehicle_id:
            return False

        updated_at = str(flight_data.get("updated_at", "")).strip()
        now_seconds = datetime.now(timezone.utc).timestamp()

        if updated_at:
            if updated_at != self.last_flight_updated_at:
                self.last_flight_updated_at = updated_at
                self.last_flight_seen_at = now_seconds
        elif self.last_flight_seen_at <= 0:
            return False

        return (now_seconds - self.last_flight_seen_at) <= 10

    @staticmethod
    def is_truthy(value: Any) -> bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return value != 0
        if isinstance(value, str):
            return value.strip().upper() in {"TRUE", "1", "YES", "ON"}
        return False

    def next_card_id(self) -> str:
        card_id = f"card_{self.card_counter}"
        self.card_counter += 1
        return card_id

    def load_layout_state(self) -> dict[str, Any]:
        try:
            with LAYOUT_STATE_PATH.open("r", encoding="utf-8") as handle:
                state = json.load(handle)
        except (FileNotFoundError, OSError, json.JSONDecodeError):
            return {"cards": []}

        cards = state.get("cards")
        if not isinstance(cards, list):
            return {"cards": []}

        normalized_cards: list[dict[str, Any]] = []
        for card_state in cards:
            if not isinstance(card_state, dict):
                continue

            field = str(card_state.get("field", "")).strip()
            if not field:
                continue

            width = card_state.get("width")
            height = card_state.get("height")
            if isinstance(width, (int, float)) and isinstance(height, (int, float)):
                normalized_width = max(DataCard.MIN_WIDTH, int(width))
                normalized_height = max(DataCard.MIN_HEIGHT, int(height))
            else:
                normalized_width = DataCard.DEFAULT_WIDTH
                normalized_height = DataCard.DEFAULT_HEIGHT

            normalized_cards.append(
                {
                    "card_id": str(card_state.get("card_id", "")).strip(),
                    "field": field,
                    "x": int(card_state.get("x", 12)) if isinstance(card_state.get("x"), (int, float)) else 12,
                    "y": int(card_state.get("y", 12)) if isinstance(card_state.get("y"), (int, float)) else 12,
                    "width": normalized_width,
                    "height": normalized_height,
                }
            )

        return {"cards": normalized_cards}

    def save_layout_state(self) -> None:
        if not hasattr(self, "workspace_frame"):
            return

        state = {
            "cards": [
                {
                    "card_id": card.card_id,
                    "field": card.field_var.get(),
                    "x": card.pos_x,
                    "y": card.pos_y,
                    "width": card.width,
                    "height": card.height,
                }
                for card in self.data_cards
            ]
        }

        with LAYOUT_STATE_PATH.open("w", encoding="utf-8") as handle:
            json.dump(state, handle, indent=2)

    def on_close(self) -> None:
        if self.pending_command_clear is not None:
            self.after_cancel(self.pending_command_clear)
        self.save_layout_state()
        self.destroy()


def main() -> None:
    app = NasaMccApp()
    app.mainloop()


if __name__ == "__main__":
    main()
