from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_VEHICLE_ID = "sls_block_1"


@dataclass(slots=True)
class BridgePaths:
    base_dir: Path

    @property
    def command_path(self) -> Path:
        return self.base_dir / "command.txt"

    @property
    def tower_status_path(self) -> Path:
        return self.base_dir / "tower_status.txt"

    @property
    def vehicle_status_path(self) -> Path:
        return self.base_dir / "vehicle_status.txt"

    @property
    def vehicle_flight_status_path(self) -> Path:
        return self.base_dir / "vehicle_flight.txt"

    @property
    def vehicle_flight_log_path(self) -> Path:
        return self.base_dir / "vehicle_flight_log.csv"

    @property
    def vehicle_launch_forecast_path(self) -> Path:
        return self.base_dir / "vehicle_launch_forecast.csv"


class MccBridgeClient:
    def __init__(self, base_dir: Path) -> None:
        self.paths = BridgePaths(base_dir=base_dir)
        self.paths.base_dir.mkdir(parents=True, exist_ok=True)
        self._ensure_defaults()

    def _ensure_defaults(self) -> None:
        defaults = {
            self.paths.command_path: {
                "command_revision": 0,
                "vehicle_id": DEFAULT_VEHICLE_ID,
                "command": "noop",
                "countdown_seconds": 0,
                "target_body": "",
                "launch_window_mode": "",
                "issued_at_utc": self._now_iso(),
            },
            self.paths.tower_status_path: {
                "source": "tower",
                "vehicle_id": DEFAULT_VEHICLE_ID,
                "status": "offline",
            },
            self.paths.vehicle_status_path: {
                "source": "vehicle",
                "vehicle_id": DEFAULT_VEHICLE_ID,
                "status": "offline",
            },
            self.paths.vehicle_flight_status_path: {
                "source": "vehicle_flight",
                "vehicle_id": DEFAULT_VEHICLE_ID,
                "status": "offline",
                "mode": "standby",
                "formatted_event_time": "T-00:00:00",
                "mission_elapsed_seconds": 0,
                "altitude": 0,
                "downrange_distance_m": 0,
                "surface_speed": 0,
                "vertical_speed": 0,
                "apoapsis": 0,
                "periapsis": 0,
                "updated_at": "",
            },
        }

        for path, payload in defaults.items():
            if not path.exists():
                self._atomic_write_record(path, payload)

        if not self.paths.vehicle_flight_log_path.exists():
            self._atomic_write_text(
                self.paths.vehicle_flight_log_path,
                "sample_index,mission_elapsed_seconds,altitude_m,downrange_m,vertical_speed_mps,surface_speed_mps,apoapsis_m,periapsis_m,latitude_deg,longitude_deg\n",
            )

        if not self.paths.vehicle_launch_forecast_path.exists():
            self._atomic_write_text(
                self.paths.vehicle_launch_forecast_path,
                "sample_index,checkpoint_seconds_to_launch,checkpoint_label,mission_elapsed_seconds,route_name,launch_heading_deg,pitchover_start_altitude_m,pitchover_end_altitude_m,gravity_turn_final_pitch_deg,gravity_turn_end_altitude_m,estimated_delta_v_mps,predicted_downrange_m,predicted_altitude_m,predicted_apoapsis_m,predicted_periapsis_m,route_points\n",
            )

    def read_bundle(self) -> dict[str, Any]:
        bundle: dict[str, Any] = {
            "tower": self._read_record(self.paths.tower_status_path, {"source": "tower", "status": "offline"}),
            "vehicle": self._read_record(self.paths.vehicle_status_path, {"source": "vehicle", "status": "offline"}),
            "command": self._read_record(self.paths.command_path, {}),
        }

        for path in sorted(self.paths.base_dir.iterdir()):
            if not path.is_file():
                continue

            if path.name.endswith(".tmp"):
                continue

            source_name = path.stem.lower()
            parsed = self._read_any(path)
            if parsed is None:
                continue

            bundle[source_name] = parsed

        return bundle

    def send_command(
        self,
        command_name: str,
        vehicle_id: str,
        countdown_seconds: int | None = None,
        target_body: str | None = None,
        launch_window_mode: str | None = None,
    ) -> dict[str, Any]:
        current = self._read_record(self.paths.command_path, {})
        next_revision = int(current.get("command_revision", 0)) + 1

        payload = {
            "command_revision": next_revision,
            "vehicle_id": vehicle_id,
            "command": command_name,
            "countdown_seconds": countdown_seconds if countdown_seconds is not None else -1,
            "target_body": target_body or "",
            "launch_window_mode": launch_window_mode or "",
            "issued_at_utc": self._now_iso(),
        }

        self._atomic_write_record(self.paths.command_path, payload)
        return payload

    def clear_command(self, vehicle_id: str) -> dict[str, Any]:
        current = self._read_record(self.paths.command_path, {})
        next_revision = int(current.get("command_revision", 0)) + 1

        payload = {
            "command_revision": next_revision,
            "vehicle_id": vehicle_id,
            "command": "noop",
            "countdown_seconds": -1,
            "target_body": "",
            "launch_window_mode": "",
            "issued_at_utc": self._now_iso(),
        }

        self._atomic_write_record(self.paths.command_path, payload)
        return payload

    def _read_record(self, path: Path, default: dict[str, Any]) -> dict[str, Any]:
        try:
            text = path.read_text(encoding="utf-8")
        except (FileNotFoundError, OSError):
            return default.copy()

        record: dict[str, Any] = {}
        for raw_line in text.splitlines():
            if "=" not in raw_line:
                continue
            key, value = raw_line.split("=", 1)
            record[key.strip()] = value.strip()

        if not record:
            return default.copy()
        return record

    def _read_any(self, path: Path) -> Any:
        if path.suffix.lower() == ".json":
            try:
                with path.open("r", encoding="utf-8") as handle:
                    return json.load(handle)
            except (OSError, json.JSONDecodeError):
                return None

        if path.suffix.lower() == ".txt":
            return self._read_record(path, {})

        return None

    def _atomic_write_record(self, path: Path, payload: dict[str, Any]) -> None:
        temp_path = path.with_suffix(path.suffix + ".tmp")
        lines = [f"{key}={value}" for key, value in payload.items()]
        with temp_path.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write("\n".join(lines))
            handle.write("\n")
        os.replace(temp_path, path)

    def _atomic_write_text(self, path: Path, contents: str) -> None:
        temp_path = path.with_suffix(path.suffix + ".tmp")
        with temp_path.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(contents)
        os.replace(temp_path, path)

    @staticmethod
    def _now_iso() -> str:
        return datetime.now(timezone.utc).isoformat(timespec="seconds")


def parse_countdown_to_seconds(value: str) -> int:
    parts = value.strip().split(":")
    if len(parts) != 3:
        raise ValueError("Countdown must be HH:MM:SS.")

    try:
        hours, minutes, seconds = (int(part) for part in parts)
    except ValueError as exc:
        raise ValueError("Countdown must contain only numbers.") from exc

    if minutes < 0 or minutes > 59 or seconds < 0 or seconds > 59 or hours < 0:
        raise ValueError("Countdown is out of range.")

    total_seconds = (hours * 3600) + (minutes * 60) + seconds
    if total_seconds < 0:
        raise ValueError("Countdown must be positive.")
    return total_seconds


def format_countdown(value: Any) -> str:
    try:
        total_seconds = max(0, int(float(value)))
    except (TypeError, ValueError):
        return "T-00:00:00"

    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60
    return f"T-{hours:02d}:{minutes:02d}:{seconds:02d}"
