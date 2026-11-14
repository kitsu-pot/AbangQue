import { memo, useEffect, useMemo, useRef, useState } from "react";
import { MapContainer, Marker, Popup, TileLayer, useMap } from "react-leaflet";
import { divIcon } from "leaflet";
import type { TileLayer as LeafletTileLayer } from "leaflet";
import type { MonitoringRow } from "./monitoring";
import { manilaTime, reportState } from "./monitoring";
import "leaflet/dist/leaflet.css";

export type MapFocus = {
  latitude: number;
  longitude: number;
  revision: number;
} | null;
function Viewport({ focus }: { focus: MapFocus }) {
  const map = useMap();
  useEffect(() => {
    if (focus)
      map.setView(
        [focus.latitude, focus.longitude],
        Math.max(map.getZoom(), 14),
        { animate: false },
      );
  }, [focus, map]);
  useEffect(() => {
    const observer = new ResizeObserver(() =>
      map.invalidateSize({ pan: false }),
    );
    observer.observe(map.getContainer());
    return () => observer.disconnect();
  }, [map]);
  return null;
}
const icons = new Map<string, ReturnType<typeof divIcon>>();
function markerIcon(tone: string, selected: boolean) {
  const key = tone + selected;
  if (!icons.has(key))
    icons.set(
      key,
      divIcon({
        className: "monitor-pin " + tone + (selected ? " chosen" : ""),
        html: `<span>${tone === "fresh" ? "●" : tone === "stale" ? "S" : tone === "restricted" ? "H" : "?"}</span>`,
        iconSize: [32, 32],
        iconAnchor: [16, 16],
      }),
    );
  return icons.get(key)!;
}
const ReportMarker = memo(function ReportMarker({
  row,
  label,
  tone,
  status,
  historical,
  selected,
  onSelect,
}: {
  row: MonitoringRow;
  label: string;
  tone: string;
  status: string;
  historical: boolean;
  selected: boolean;
  onSelect: (row: MonitoringRow) => void;
}) {
  const latitude = row.position!.latitude,
    longitude = row.position!.longitude;
  const position = useMemo<[number, number]>(
    () => [latitude, longitude],
    [latitude, longitude],
  );
  const handlers = useMemo(
    () => ({ click: () => onSelect(row) }),
    [row, onSelect],
  );
  return (
    <Marker
      position={position}
      icon={markerIcon(tone, selected)}
      title={`${row.id} · ${label}${historical ? " · Historical location" : ""}`}
      alt={`Select jeepney ${row.id}`}
      eventHandlers={handlers}
    >
      <Popup autoPan={false}>
        <strong>{row.id}</strong>
        <p>
          {label} ·{" "}
          {historical ? "Last known location" : "Latest reported location"}
        </p>
        <p>Driver status: {status}</p>
        <small>Measured {manilaTime(row.timestamp)}</small>
      </Popup>
    </Marker>
  );
});
export function MonitoringMap({
  rows,
  selectedId,
  focus,
  onSelect,
  now,
  stale,
  verified,
}: {
  rows: MonitoringRow[];
  selectedId: string;
  focus: MapFocus;
  onSelect: (row: MonitoringRow) => void;
  now: number;
  stale: number;
  verified: boolean;
}) {
  const tiles = useRef<LeafletTileLayer>(null),
    [tileError, setTileError] = useState(false);
  const events = useMemo(() => ({ tileerror: () => setTileError(true) }), []);
  return (
    <div className="monitor-map-wrap">
      <MapContainer
        center={[13.4, 121.95]}
        zoom={10}
        className="monitor-map"
        scrollWheelZoom={false}
        aria-label="Last reported jeepney locations"
      >
        <TileLayer
          ref={tiles}
          url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
          maxZoom={19}
          eventHandlers={events}
          attribution={
            '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          }
        />
        <Viewport focus={focus} />
        {rows
          .filter((r) => r.position)
          .map((row) => {
            const state = reportState(row, now, stale, verified);
            return (
              <ReportMarker
                key={row.id}
                row={row}
                {...state}
                selected={row.id === selectedId}
                onSelect={onSelect}
              />
            );
          })}
      </MapContainer>
      <div className="map-caption">
        LAST REPORTED LOCATIONS · NOT CONTINUOUS TRACKING
      </div>
      {tileError && (
        <div className="map-warning" role="status">
          Map tiles unavailable. Report details remain usable.{" "}
          <button
            onClick={() => {
              setTileError(false);
              tiles.current?.redraw();
            }}
          >
            Retry tiles
          </button>
        </div>
      )}
      {!rows.some((r) => r.position) && (
        <div className="map-empty">
          No valid reported positions in this view.
          <br />
          <small>Records without coordinates appear in the list.</small>
        </div>
      )}
    </div>
  );
}
