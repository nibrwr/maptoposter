#!/usr/bin/env python3
"""
City Map Poster Generator

This module generates beautiful, minimalist map posters for any city in the world.
It fetches OpenStreetMap data using OSMnx, applies customizable themes, and creates
high-quality poster-ready images with roads, water features, and parks.
"""

import argparse
import asyncio
import hashlib
import hmac
import json
import math
import os
import pickle
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import cast

import matplotlib.colors as mcolors
import matplotlib.pyplot as plt
import numpy as np
import osmnx as ox
from geopandas import GeoDataFrame
from geopy.geocoders import Nominatim
from lat_lon_parser import parse
from matplotlib.font_manager import FontProperties
from networkx import MultiDiGraph
from shapely.geometry import Point
from tqdm import tqdm

from font_management import load_fonts


class CacheError(Exception):
    """Raised when a cache operation fails."""


CACHE_DIR_PATH = os.environ.get("CACHE_DIR", "cache")
CACHE_DIR = Path(CACHE_DIR_PATH)
CACHE_DIR.mkdir(exist_ok=True)
try:
    os.chmod(CACHE_DIR, 0o700)
except OSError:
    pass
CACHE_MAGIC = b"maptoposter-cache-v1\n"
CACHE_KEY_PATH = CACHE_DIR / ".cache_key"
CACHE_ONLY = False

THEMES_DIR = "themes"
FONTS_DIR = "fonts"
POSTERS_DIR = "posters"

FILE_ENCODING = "utf-8"

FONTS = load_fonts()


def _cache_path(key: str) -> str:
    """
    Generate a safe cache file path from a cache key.

    Args:
        key: Cache key identifier

    Returns:
        Path to cache file with .pkl extension
    """
    safe = hashlib.sha256(key.encode(FILE_ENCODING)).hexdigest()
    return os.path.join(CACHE_DIR, f"{safe}.pkl")


def _cache_signature(payload: bytes) -> bytes:
    return hmac.new(_cache_secret(), payload, hashlib.sha256).hexdigest().encode("ascii")


def _cache_secret() -> bytes:
    env_secret = os.environ.get("CACHE_SECRET")
    if env_secret:
        return env_secret.encode(FILE_ENCODING)

    if CACHE_KEY_PATH.exists():
        return CACHE_KEY_PATH.read_bytes()

    secret = os.urandom(32)
    CACHE_KEY_PATH.write_bytes(secret)
    try:
        os.chmod(CACHE_KEY_PATH, 0o600)
    except OSError:
        pass
    return secret


def cache_get(key: str):
    """
    Retrieve a cached object by key.

    Args:
        key: Cache key identifier

    Returns:
        Cached object if found, None otherwise

    Raises:
        CacheError: If cache read operation fails
    """
    try:
        path = _cache_path(key)
        if not os.path.exists(path):
            return None
        with open(path, "rb") as f:
            blob = f.read()
        if not blob.startswith(CACHE_MAGIC):
            return None
        signature, separator, payload = blob[len(CACHE_MAGIC):].partition(b"\n")
        if not separator or not hmac.compare_digest(signature, _cache_signature(payload)):
            return None
        return pickle.loads(payload)
    except Exception as e:
        raise CacheError(f"Cache read failed: {e}") from e


def cache_set(key: str, value):
    """
    Store an object in the cache.

    Args:
        key: Cache key identifier
        value: Object to cache (must be picklable)

    Raises:
        CacheError: If cache write operation fails
    """
    try:
        if not os.path.exists(CACHE_DIR):
            os.makedirs(CACHE_DIR)
        path = _cache_path(key)
        payload = pickle.dumps(value, protocol=pickle.HIGHEST_PROTOCOL)
        with open(path, "wb") as f:
            f.write(CACHE_MAGIC)
            f.write(_cache_signature(payload))
            f.write(b"\n")
            f.write(payload)
    except Exception as e:
        raise CacheError(f"Cache write failed: {e}") from e


# Font loading now handled by font_management.py module


def is_latin_script(text):
    """
    Check if text is primarily Latin script.
    Used to determine if letter-spacing should be applied to city names.

    :param text: Text to analyze
    :return: True if text is primarily Latin script, False otherwise
    """
    if not text:
        return True

    latin_count = 0
    total_alpha = 0

    for char in text:
        if char.isalpha():
            total_alpha += 1
            # Latin Unicode ranges:
            # - Basic Latin: U+0000 to U+007F
            # - Latin-1 Supplement: U+0080 to U+00FF
            # - Latin Extended-A: U+0100 to U+017F
            # - Latin Extended-B: U+0180 to U+024F
            if ord(char) < 0x250:
                latin_count += 1

    # If no alphabetic characters, default to Latin (numbers, symbols, etc.)
    if total_alpha == 0:
        return True

    # Consider it Latin if >80% of alphabetic characters are Latin
    return (latin_count / total_alpha) > 0.8


def generate_output_filename(city, theme_name, output_format):
    """
    Generate unique output filename with city, theme, and datetime.
    """
    if not os.path.exists(POSTERS_DIR):
        os.makedirs(POSTERS_DIR)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    city_slug = city.lower().replace(" ", "_")
    ext = output_format.lower()
    filename = f"{city_slug}_{theme_name}_{timestamp}.{ext}"
    return os.path.join(POSTERS_DIR, filename)


def emit_progress(progress, status):
    payload = json.dumps({"progress": progress, "status": status}, ensure_ascii=True)
    print(f"MAPTOPOSTER_EVENT {payload}", flush=True)


def get_available_themes():
    """
    Scans the themes directory and returns a list of available theme names.
    """
    if not os.path.exists(THEMES_DIR):
        os.makedirs(THEMES_DIR)
        return []

    themes = []
    for file in sorted(os.listdir(THEMES_DIR)):
        if file.endswith(".json"):
            theme_name = file[:-5]  # Remove .json extension
            themes.append(theme_name)
    return themes


def load_theme(theme_name="terracotta"):
    """
    Load theme from JSON file in themes directory.
    """
    theme_file = os.path.join(THEMES_DIR, f"{theme_name}.json")

    if not os.path.exists(theme_file):
        print(f"⚠ Theme file '{theme_file}' not found. Using default terracotta theme.")
        # Fallback to embedded terracotta theme
        return {
            "name": "Terracotta",
            "description": "Mediterranean warmth - burnt orange and clay tones on cream",
            "bg": "#F5EDE4",
            "text": "#8B4513",
            "gradient_color": "#F5EDE4",
            "water": "#A8C4C4",
            "parks": "#E8E0D0",
            "road_motorway": "#A0522D",
            "road_primary": "#B8653A",
            "road_secondary": "#C9846A",
            "road_tertiary": "#D9A08A",
            "road_residential": "#E5C4B0",
            "road_default": "#D9A08A",
        }

    with open(theme_file, "r", encoding=FILE_ENCODING) as f:
        theme = json.load(f)
        emit_progress(0.22, "Preparing theme")
        print(f"✓ Loaded theme: {theme.get('name', theme_name)}")
        if "description" in theme:
            print(f"  {theme['description']}")
        return theme


# Load theme (can be changed via command line or input)
THEME = dict[str, str]()  # Will be loaded later


@dataclass(frozen=True)
class MapDensityProfile:
    """Rendering hints derived from the visible street-network density."""

    name: str
    density: float
    road_scale: float
    feature_alpha: float
    texture_alpha: float
    contrast_target: float
    zoom_multiplier: float
    should_recenter: bool
    should_draw_inset: bool


def _theme_color(key, fallback):
    return THEME.get(key, fallback)


def _mix_colors(color, other, amount):
    rgb = np.array(mcolors.to_rgb(color))
    target = np.array(mcolors.to_rgb(other))
    return mcolors.to_hex(rgb * (1 - amount) + target * amount)


def _relative_luminance(color):
    def channel(value):
        return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4

    r, g, b = mcolors.to_rgb(color)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def _contrast_ratio(color, background):
    fg = _relative_luminance(color)
    bg = _relative_luminance(background)
    light, dark = max(fg, bg), min(fg, bg)
    return (light + 0.05) / (dark + 0.05)


def _ensure_contrast(color, background, target_ratio):
    adjusted = color
    background_luma = _relative_luminance(background)
    toward = "#000000" if background_luma > 0.5 else "#FFFFFF"

    for _ in range(8):
        if _contrast_ratio(adjusted, background) >= target_ratio:
            return adjusted
        adjusted = _mix_colors(adjusted, toward, 0.16)

    return adjusted


def _project_point(point, crs):
    lat, lon = point
    return ox.projection.project_geometry(
        Point(lon, lat),
        crs="EPSG:4326",
        to_crs=crs,
    )[0]


def create_gradient_fade(ax, color, location="bottom", zorder=10):
    """
    Creates a fade effect at the top or bottom of the map.
    """
    vals = np.linspace(0, 1, 256).reshape(-1, 1)
    gradient = np.hstack((vals, vals))

    rgb = mcolors.to_rgb(color)
    my_colors = np.zeros((256, 4))
    my_colors[:, 0] = rgb[0]
    my_colors[:, 1] = rgb[1]
    my_colors[:, 2] = rgb[2]

    if location == "bottom":
        my_colors[:, 3] = np.linspace(1, 0, 256)
        extent_y_start = 0
        extent_y_end = 0.25
    else:
        my_colors[:, 3] = np.linspace(0, 1, 256)
        extent_y_start = 0.75
        extent_y_end = 1.0

    custom_cmap = mcolors.ListedColormap(my_colors)

    xlim = ax.get_xlim()
    ylim = ax.get_ylim()
    y_range = ylim[1] - ylim[0]

    y_bottom = ylim[0] + y_range * extent_y_start
    y_top = ylim[0] + y_range * extent_y_end

    ax.imshow(
        gradient,
        extent=[xlim[0], xlim[1], y_bottom, y_top],
        aspect="auto",
        cmap=custom_cmap,
        zorder=zorder,
        origin="lower",
    )


def _normalized_highway(data):
    highway = data.get('highway', 'unclassified')
    if isinstance(highway, list):
        highway = highway[0] if highway else 'unclassified'
    return highway


def get_edge_colors_by_type(g, profile=None):
    """
    Assigns colors to edges based on road type hierarchy.
    Returns a list of colors corresponding to each edge in the graph.
    """
    edge_colors = []
    target_ratio = profile.contrast_target if profile else 1.65
    background = THEME["bg"]

    for _u, _v, data in g.edges(data=True):
        highway = _normalized_highway(data)

        # Assign color based on road type
        if highway in ["motorway", "motorway_link"]:
            color = THEME["road_motorway"]
        elif highway in ["trunk", "trunk_link", "primary", "primary_link"]:
            color = THEME["road_primary"]
        elif highway in ["secondary", "secondary_link"]:
            color = THEME["road_secondary"]
        elif highway in ["tertiary", "tertiary_link"]:
            color = THEME["road_tertiary"]
        elif highway in ["residential", "living_street", "unclassified"]:
            color = THEME["road_residential"]
        else:
            color = THEME['road_default']

        edge_colors.append(_ensure_contrast(color, background, target_ratio))

    return edge_colors


def get_edge_widths_by_type(g, profile=None, inset=False):
    """
    Assigns line widths to edges based on road type.
    Major roads get thicker lines.
    """
    edge_widths = []
    scale = profile.road_scale if profile else 1.0
    if inset:
        scale *= 1.25

    for _u, _v, data in g.edges(data=True):
        highway = _normalized_highway(data)

        # Assign width based on road importance
        if highway in ["motorway", "motorway_link"]:
            width = 1.2
        elif highway in ["trunk", "trunk_link", "primary", "primary_link"]:
            width = 1.0
        elif highway in ["secondary", "secondary_link"]:
            width = 0.8
        elif highway in ["tertiary", "tertiary_link"]:
            width = 0.6
        else:
            width = 0.4

        edge_widths.append(width * scale)

    return edge_widths


def analyze_map_density(g_proj, center_projected, fig, dist, detail_level="auto", enhance_sparse=True):
    crop_xlim, crop_ylim = get_crop_limits_projected(g_proj, center_projected, fig, dist)
    area_km2 = max(((crop_xlim[1] - crop_xlim[0]) * (crop_ylim[1] - crop_ylim[0])) / 1_000_000, 0.1)
    edge_length = 0.0
    visible_edges = 0

    for _u, _v, data in g_proj.edges(data=True):
        geometry = data.get("geometry")
        length = float(data.get("length", 0.0))
        if geometry is not None:
            bounds = geometry.bounds
            is_visible = not (
                bounds[2] < crop_xlim[0]
                or bounds[0] > crop_xlim[1]
                or bounds[3] < crop_ylim[0]
                or bounds[1] > crop_ylim[1]
            )
        else:
            is_visible = True

        if is_visible:
            edge_length += length
            visible_edges += 1

    density = (edge_length / 1000.0) / area_km2

    if detail_level == "clean":
        return MapDensityProfile("clean", density, 1.0, 0.78, 0.0, 1.7, 1.0, False, False)
    if detail_level == "rich":
        return MapDensityProfile("rich", density, 1.55, 0.95, 0.22, 2.05, 1.12, True, True)
    if not enhance_sparse:
        return MapDensityProfile("standard", density, 1.0, 0.78, 0.04, 1.7, 1.0, False, False)

    if density < 1.8 or visible_edges < 140:
        return MapDensityProfile("rural", density, 2.15, 0.98, 0.28, 2.18, 1.28, True, True)
    if density < 5.5 or visible_edges < 360:
        return MapDensityProfile("suburban", density, 1.70, 0.92, 0.20, 2.02, 1.16, True, True)
    if density < 11.0:
        return MapDensityProfile("open city", density, 1.32, 0.86, 0.12, 1.88, 1.06, False, False)

    return MapDensityProfile("urban", density, 1.0, 0.78, 0.05, 1.70, 1.0, False, False)


def find_density_center(g_proj, fallback_center, dist, profile):
    if not profile.should_recenter:
        return fallback_center

    try:
        nodes = ox.graph_to_gdfs(g_proj, edges=False)
    except Exception:
        return fallback_center

    if nodes.empty or "x" not in nodes or "y" not in nodes:
        return fallback_center

    x = nodes["x"].to_numpy()
    y = nodes["y"].to_numpy()
    if len(x) < 12:
        return fallback_center

    fx, fy = fallback_center.x, fallback_center.y
    max_shift = dist * (0.45 if profile.name == "rural" else 0.32)
    mask = ((x - fx) ** 2 + (y - fy) ** 2) <= max_shift ** 2
    if mask.sum() < 8:
        return fallback_center

    x_local = x[mask]
    y_local = y[mask]
    bins = 22 if profile.name == "rural" else 28
    counts, x_edges, y_edges = np.histogram2d(x_local, y_local, bins=bins)
    if counts.max() <= 0:
        return fallback_center

    ix, iy = np.unravel_index(np.argmax(counts), counts.shape)
    center_x = (x_edges[ix] + x_edges[ix + 1]) / 2
    center_y = (y_edges[iy] + y_edges[iy + 1]) / 2
    candidate = Point(center_x, center_y)
    shift = math.hypot(candidate.x - fx, candidate.y - fy)

    if shift > max_shift:
        ratio = max_shift / shift
        candidate = Point(fx + (candidate.x - fx) * ratio, fy + (candidate.y - fy) * ratio)

    print(f"✓ Recentered composition toward local street cluster ({int(shift)}m shift).")
    return candidate


def get_coordinates(city, country):
    """
    Fetches coordinates for a given city and country using geopy.
    Includes rate limiting to be respectful to the geocoding service.
    """
    coords = f"coords_{city.lower()}_{country.lower()}"
    cached = cache_get(coords)
    if cached:
        print(f"✓ Using cached coordinates for {city}, {country}")
        return cached
    if CACHE_ONLY:
        raise ValueError(f"Cache only is enabled and coordinates are not cached for {city}, {country}")

    emit_progress(0.15, "Locating")
    print("Looking up coordinates...")
    geolocator = Nominatim(user_agent="city_map_poster", timeout=10)

    # Add a small delay to respect Nominatim's usage policy
    time.sleep(1)

    try:
        location = geolocator.geocode(f"{city}, {country}")
    except Exception as e:
        raise ValueError(f"Geocoding failed for {city}, {country}: {e}") from e

    # If geocode returned a coroutine in some environments, run it to get the result.
    if asyncio.iscoroutine(location):
        try:
            location = asyncio.run(location)
        except RuntimeError as exc:
            # If an event loop is already running, try using it to complete the coroutine.
            loop = asyncio.get_event_loop()
            if loop.is_running():
                # Running event loop in the same thread; raise a clear error.
                raise RuntimeError(
                    "Geocoder returned a coroutine while an event loop is already running. "
                    "Run this script in a synchronous environment."
                ) from exc
            location = loop.run_until_complete(location)

    if location:
        # Use getattr to safely access address (helps static analyzers)
        addr = getattr(location, "address", None)
        if addr:
            print(f"✓ Found: {addr}")
        else:
            print("✓ Found location (address not available)")
        print(f"✓ Coordinates: {location.latitude}, {location.longitude}")
        try:
            cache_set(coords, (location.latitude, location.longitude))
        except CacheError as e:
            print(e)
        return (location.latitude, location.longitude)

    raise ValueError(f"Could not find coordinates for {city}, {country}")


def get_coordinates_for_location(location_query):
    """
    Fetch coordinates for a free-form place query such as a ZIP code,
    city/state, address, landmark, or city/country.
    """
    coords = f"coords_location_{location_query.lower()}"
    cached = cache_get(coords)
    if cached:
        print(f"✓ Using cached coordinates for {location_query}")
        return cached
    if CACHE_ONLY:
        raise ValueError(f"Cache only is enabled and coordinates are not cached for {location_query}")

    emit_progress(0.15, "Locating")
    print("Looking up location...")
    geolocator = Nominatim(user_agent="city_map_poster", timeout=10)

    # Add a small delay to respect Nominatim's usage policy
    time.sleep(1)

    try:
        location = geolocator.geocode(location_query)
    except Exception as e:
        raise ValueError(f"Geocoding failed for {location_query}: {e}") from e

    if asyncio.iscoroutine(location):
        try:
            location = asyncio.run(location)
        except RuntimeError as exc:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                raise RuntimeError(
                    "Geocoder returned a coroutine while an event loop is already running. "
                    "Run this script in a synchronous environment."
                ) from exc
            location = loop.run_until_complete(location)

    if location:
        addr = getattr(location, "address", None)
        if addr:
            print(f"✓ Found: {addr}")
        else:
            print("✓ Found location (address not available)")
        print(f"✓ Coordinates: {location.latitude}, {location.longitude}")
        try:
            cache_set(coords, (location.latitude, location.longitude))
        except CacheError as e:
            print(e)
        return (location.latitude, location.longitude)

    raise ValueError(f"Could not find coordinates for {location_query}")


def get_crop_limits(g_proj, center_lat_lon, fig, dist):
    """
    Crop inward to preserve aspect ratio while guaranteeing
    full coverage of the requested radius.
    """
    center = _project_point(center_lat_lon, g_proj.graph["crs"])
    return get_crop_limits_projected(g_proj, center, fig, dist)


def get_crop_limits_projected(g_proj, center, fig, dist):
    """
    Crop around a projected point while preserving the poster aspect ratio.
    """
    center_x, center_y = center.x, center.y

    fig_width, fig_height = fig.get_size_inches()
    aspect = fig_width / fig_height

    # Start from the *requested* radius
    half_x = dist
    half_y = dist

    # Cut inward to match aspect
    if aspect > 1:  # landscape → reduce height
        half_y = half_x / aspect
    else:  # portrait → reduce width
        half_x = half_y * aspect

    return (
        (center_x - half_x, center_x + half_x),
        (center_y - half_y, center_y + half_y),
    )


def fetch_graph(point, dist) -> MultiDiGraph | None:
    """
    Fetch street network graph from OpenStreetMap.

    Uses caching to avoid redundant downloads. Fetches all network types
    within the specified distance from the center point.

    Args:
        point: (latitude, longitude) tuple for center point
        dist: Distance in meters from center point

    Returns:
        MultiDiGraph of street network, or None if fetch fails
    """
    lat, lon = point
    candidate_distances = [dist, dist * 1.5, dist * 2.0]

    for candidate_dist in candidate_distances:
        graph = f"graph_{lat}_{lon}_{round(candidate_dist, 2)}"
        cached = cache_get(graph)
        if cached is not None:
            print(f"✓ Using cached street network ({int(candidate_dist)}m)")
            return cast(MultiDiGraph, cached)

    if CACHE_ONLY:
        print("Cache only is enabled and the street network is not cached.")
        return None

    for candidate_dist in candidate_distances:
        try:
            print(f"Fetching street network within {int(candidate_dist)}m...")
            g = ox.graph_from_point(
                point,
                dist=candidate_dist,
                dist_type='bbox',
                network_type='all',
                truncate_by_edge=True,
            )
            # Rate limit between requests
            time.sleep(0.5)
            try:
                cache_set(f"graph_{lat}_{lon}_{round(candidate_dist, 2)}", g)
            except CacheError as e:
                print(e)
            return g
        except Exception as e:
            print(f"OSMnx error while fetching graph at {int(candidate_dist)}m: {e}")

    return None


def fetch_features(point, dist, tags, name) -> GeoDataFrame | None:
    """
    Fetch geographic features (water, parks, etc.) from OpenStreetMap.

    Uses caching to avoid redundant downloads. Fetches features matching
    the specified OSM tags within distance from center point.

    Args:
        point: (latitude, longitude) tuple for center point
        dist: Distance in meters from center point
        tags: Dictionary of OSM tags to filter features
        name: Name for this feature type (for caching and logging)

    Returns:
        GeoDataFrame of features, or None if fetch fails
    """
    lat, lon = point
    tag_str = "_".join(tags.keys())
    features = f"{name}_{lat}_{lon}_{dist}_{tag_str}"
    cached = cache_get(features)
    if cached is not None:
        print(f"✓ Using cached {name}")
        return cast(GeoDataFrame, cached)
    if CACHE_ONLY:
        print(f"Cache only is enabled and {name} are not cached.")
        return None

    try:
        data = ox.features_from_point(point, tags=tags, dist=dist)
        # Rate limit between requests
        time.sleep(0.3)
        try:
            cache_set(features, data)
        except CacheError as e:
            print(e)
        return data
    except Exception as e:
        print(f"OSMnx error while fetching features: {e}")
        return None


def _project_feature_gdf(features, target_crs):
    if features is None or features.empty:
        return None

    try:
        if features.crs:
            return features.to_crs(target_crs)
        projected = ox.projection.project_gdf(features)
        return projected.to_crs(target_crs)
    except Exception:
        try:
            return ox.projection.project_gdf(features).to_crs(target_crs)
        except Exception as e:
            print(f"Feature projection skipped: {e}")
            return None


def _geometry_subset(features, geometry_types):
    if features is None or features.empty:
        return None
    subset = features[features.geometry.type.isin(geometry_types)]
    return subset if not subset.empty else None


def plot_polygon_layer(ax, features, facecolor, alpha, zorder, edgecolor="none", linewidth=0.0):
    polys = _geometry_subset(features, ["Polygon", "MultiPolygon"])
    if polys is None:
        return
    polys.plot(
        ax=ax,
        facecolor=facecolor,
        edgecolor=edgecolor,
        linewidth=linewidth,
        alpha=alpha,
        zorder=zorder,
    )


def plot_line_layer(ax, features, color, alpha, linewidth, zorder):
    lines = _geometry_subset(features, ["LineString", "MultiLineString"])
    if lines is None:
        return
    lines.plot(ax=ax, color=color, alpha=alpha, linewidth=linewidth, zorder=zorder)


def draw_rural_texture(ax, features, profile, crop_xlim, crop_ylim):
    if profile.texture_alpha <= 0:
        return

    boundary_color = _ensure_contrast(
        _mix_colors(THEME["text"], THEME["bg"], 0.62),
        THEME["bg"],
        1.28,
    )
    polys = _geometry_subset(features, ["Polygon", "MultiPolygon"])
    if polys is not None:
        polys.boundary.plot(
            ax=ax,
            color=boundary_color,
            linewidth=0.32 * profile.road_scale,
            alpha=profile.texture_alpha,
            zorder=1.3,
        )

    if profile.name not in {"rural", "suburban", "rich"}:
        return

    x0, x1 = crop_xlim
    y0, y1 = crop_ylim
    span = max(x1 - x0, y1 - y0)
    spacing = span / 10
    for offset in np.arange(-span, span * 1.5, spacing):
        ax.plot(
            [x0 + offset, x0 + offset + span],
            [y0, y1],
            color=boundary_color,
            alpha=profile.texture_alpha * 0.20,
            linewidth=0.35,
            zorder=0.3,
        )


def draw_coordinate_grid(ax, crop_xlim, crop_ylim, profile):
    if profile.name == "urban":
        alpha = 0.035
    else:
        alpha = 0.075

    grid_color = _ensure_contrast(_mix_colors(THEME["text"], THEME["bg"], 0.52), THEME["bg"], 1.22)
    x0, x1 = crop_xlim
    y0, y1 = crop_ylim
    for x in np.linspace(x0, x1, 7)[1:-1]:
        ax.plot([x, x], [y0, y1], color=grid_color, alpha=alpha, linewidth=0.45, zorder=0.2)
    for y in np.linspace(y0, y1, 9)[1:-1]:
        ax.plot([x0, x1], [y, y], color=grid_color, alpha=alpha, linewidth=0.45, zorder=0.2)


def draw_poster_frame(ax, scale_factor):
    frame_color = _ensure_contrast(_mix_colors(THEME["text"], THEME["bg"], 0.35), THEME["bg"], 1.35)
    for inset, alpha, width in [(0.018, 0.26, 0.9), (0.026, 0.14, 0.55)]:
        rect = plt.Rectangle(
            (inset, inset),
            1 - inset * 2,
            1 - inset * 2,
            transform=ax.transAxes,
            fill=False,
            edgecolor=frame_color,
            linewidth=width * scale_factor,
            alpha=alpha,
            zorder=12,
        )
        ax.add_patch(rect)


def _feature_label_candidates(features, crop_xlim, crop_ylim, max_labels):
    if features is None or features.empty or "name" not in features:
        return []

    candidates = []
    x0, x1 = crop_xlim
    y0, y1 = crop_ylim
    for _, row in features.dropna(subset=["name"]).head(80).iterrows():
        name = str(row.get("name", "")).strip()
        if len(name) < 3 or len(name) > 32:
            continue
        geometry = row.geometry
        if geometry is None or geometry.is_empty:
            continue
        point = geometry.representative_point()
        if not (x0 <= point.x <= x1 and y0 <= point.y <= y1):
            continue
        area = getattr(geometry, "area", 0.0)
        candidates.append((area, name, point.x, point.y))

    candidates.sort(reverse=True, key=lambda item: item[0])
    return candidates[:max_labels]


def draw_feature_labels(ax, feature_groups, crop_xlim, crop_ylim, profile, scale_factor):
    if profile.name == "urban":
        return

    label_color = _ensure_contrast(_mix_colors(THEME["text"], THEME["bg"], 0.12), THEME["bg"], 1.75)
    label_count = 0
    for features, limit in feature_groups:
        for _area, name, x, y in _feature_label_candidates(features, crop_xlim, crop_ylim, limit):
            if label_count >= 5:
                return
            ax.text(
                x,
                y,
                name.upper(),
                color=label_color,
                alpha=0.36,
                fontsize=max(4.5, 6.5 * scale_factor),
                ha="center",
                va="center",
                zorder=9,
            )
            label_count += 1


def draw_inset_map(ax, g_proj, center_projected, profile, width, height):
    if not profile.should_draw_inset:
        return

    inset_width = 0.24 if width <= height else 0.20
    inset_height = inset_width * (height / width) * 0.72
    inset_ax = ax.figure.add_axes([0.07, 0.72, inset_width, inset_height], facecolor=THEME["bg"])
    inset_ax.set_axis_off()

    inset_dist = 1400 if profile.name == "rural" else 1800
    bbox = inset_ax.get_position()
    aspect = (bbox.width * width) / max(bbox.height * height, 0.001)
    half_x = inset_dist
    half_y = inset_dist
    if aspect > 1:
        half_y = half_x / aspect
    else:
        half_x = half_y * aspect
    crop_xlim = (center_projected.x - half_x, center_projected.x + half_x)
    crop_ylim = (center_projected.y - half_y, center_projected.y + half_y)
    edge_colors = get_edge_colors_by_type(g_proj, profile)
    edge_widths = get_edge_widths_by_type(g_proj, profile, inset=True)

    ox.plot_graph(
        g_proj,
        ax=inset_ax,
        bgcolor=THEME["bg"],
        node_size=0,
        edge_color=edge_colors,
        edge_linewidth=edge_widths,
        show=False,
        close=False,
    )
    inset_ax.set_xlim(crop_xlim)
    inset_ax.set_ylim(crop_ylim)
    inset_ax.set_aspect("equal", adjustable="box")

    for spine in inset_ax.spines.values():
        spine.set_visible(True)
        spine.set_linewidth(0.8)
        spine.set_edgecolor(_mix_colors(THEME["text"], THEME["bg"], 0.35))
        spine.set_alpha(0.35)

    inset_ax.text(
        0.5,
        -0.12,
        "TOWN DETAIL",
        transform=inset_ax.transAxes,
        ha="center",
        va="top",
        color=THEME["text"],
        alpha=0.45,
        fontsize=7,
        zorder=13,
    )


def create_poster(
    city,
    country,
    point,
    dist,
    output_file,
    output_format,
    width=12,
    height=16,
    country_label=None,
    name_label=None,
    display_city=None,
    display_country=None,
    fonts=None,
    enhance_sparse=True,
    detail_level="auto",
    inset_mode="auto",
):
    """
    Generate a complete map poster with roads, water, parks, and typography.

    Creates a high-quality poster by fetching OSM data, rendering map layers,
    applying the current theme, and adding text labels with coordinates.

    Args:
        city: City name for display on poster
        country: Country name for display on poster
        point: (latitude, longitude) tuple for map center
        dist: Map radius in meters
        output_file: Path where poster will be saved
        output_format: File format ('png', 'svg', or 'pdf')
        width: Poster width in inches (default: 12)
        height: Poster height in inches (default: 16)
        country_label: Optional override for country text on poster
        _name_label: Optional override for city name (unused, reserved for future use)

    Raises:
        RuntimeError: If street network data cannot be retrieved
    """
    # Handle display names for i18n support
    # Priority: display_city/display_country > name_label/country_label > city/country
    display_city = display_city or name_label or city
    display_country = display_country or country_label or country

    emit_progress(0.32, "Preparing map")
    print(f"\nGenerating map for {city}, {country}...")

    # Progress bar for data fetching
    with tqdm(
        total=5,
        desc="Fetching map data",
        unit="step",
        bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt}",
        disable=not sys.stderr.isatty(),
    ) as pbar:
        # 1. Fetch Street Network
        emit_progress(0.42, "Downloading street network")
        pbar.set_description("Downloading street network")
        # Fetch at least the user-selected radius. Sparse or military-adjacent
        # places can have no routable nodes near the geocoded center, so fetching
        # too tightly makes otherwise valid locations fail before rendering.
        aspect_compensation = max(height, width) / min(height, width)
        sparse_buffer = 1.35 if enhance_sparse and detail_level != "clean" else 1.0
        compensated_dist = max(dist, dist * aspect_compensation * sparse_buffer)
        g = fetch_graph(point, compensated_dist)
        if g is None:
            raise RuntimeError("Failed to retrieve street network data.")
        pbar.update(1)

        # 2. Fetch Water Features
        emit_progress(0.56, "Downloading water features")
        pbar.set_description("Downloading water features")
        water = fetch_features(
            point,
            compensated_dist,
            tags={
                "natural": ["water", "bay", "strait"],
                "waterway": ["riverbank", "river", "stream", "canal"],
                "reservoir": True,
            },
            name="water",
        )
        pbar.update(1)

        # 3. Fetch Parks
        emit_progress(0.68, "Downloading parks")
        pbar.set_description("Downloading parks/green spaces")
        parks = fetch_features(
            point,
            compensated_dist,
            tags={
                "leisure": ["park", "garden", "golf_course", "nature_reserve"],
                "landuse": ["grass", "recreation_ground", "forest", "meadow", "village_green", "cemetery"],
                "natural": ["wood", "scrub", "heath", "grassland"],
            },
            name="parks",
        )
        pbar.update(1)

        emit_progress(0.72, "Downloading land features")
        pbar.set_description("Downloading land features")
        landuse = fetch_features(
            point,
            compensated_dist,
            tags={
                "landuse": [
                    "farmland",
                    "farmyard",
                    "orchard",
                    "vineyard",
                    "residential",
                    "commercial",
                    "industrial",
                    "military",
                    "railway",
                    "retail",
                ],
                "aeroway": ["aerodrome", "runway"],
                "amenity": ["school", "university", "college", "hospital"],
            },
            name="landuse",
        )
        pbar.update(1)

        emit_progress(0.74, "Downloading rail and paths")
        pbar.set_description("Downloading rail and path features")
        transport = fetch_features(
            point,
            compensated_dist,
            tags={
                "railway": ["rail", "light_rail", "subway", "tram"],
                "highway": ["cycleway", "footway", "path", "pedestrian"],
            },
            name="transport",
        )
        pbar.update(1)

    print("✓ All data retrieved successfully!")

    # 2. Setup Plot
    emit_progress(0.78, "Rendering")
    print("Rendering map...")
    fig, ax = plt.subplots(figsize=(width, height), facecolor=THEME["bg"])
    ax.set_facecolor(THEME["bg"])
    ax.set_position((0.0, 0.0, 1.0, 1.0))

    # Project graph to a metric CRS so distances and aspect are linear (meters)
    g_proj = ox.project_graph(g)
    center_projected = _project_point(point, g_proj.graph["crs"])
    profile = analyze_map_density(g_proj, center_projected, fig, dist, detail_level, enhance_sparse)
    render_dist = min(compensated_dist * 0.96, dist * profile.zoom_multiplier)
    center_projected = find_density_center(g_proj, center_projected, render_dist, profile)
    should_draw_inset = inset_mode == "on" or (inset_mode == "auto" and profile.should_draw_inset)
    profile = MapDensityProfile(
        profile.name,
        profile.density,
        profile.road_scale,
        profile.feature_alpha,
        profile.texture_alpha,
        profile.contrast_target,
        profile.zoom_multiplier,
        profile.should_recenter,
        should_draw_inset,
    )
    print(
        f"✓ Map profile: {profile.name} "
        f"({profile.density:.2f} km of roads/km², road scale {profile.road_scale:.2f}x)"
    )

    water_proj = _project_feature_gdf(water, g_proj.graph["crs"])
    parks_proj = _project_feature_gdf(parks, g_proj.graph["crs"])
    landuse_proj = _project_feature_gdf(landuse, g_proj.graph["crs"])
    transport_proj = _project_feature_gdf(transport, g_proj.graph["crs"])

    # Determine cropping limits early so texture, labels, and grid align to the visible composition.
    crop_xlim, crop_ylim = get_crop_limits_projected(g_proj, center_projected, fig, render_dist)

    # 3. Plot Layers
    # Layer 1: Polygons (filter to only plot polygon/multipolygon geometries, not points)
    water_color = _ensure_contrast(THEME['water'], THEME["bg"], 1.12)
    park_color = _theme_color("parks", _mix_colors(THEME["bg"], THEME["text"], 0.08))
    land_color = _theme_color("land", _mix_colors(THEME["bg"], THEME["text"], 0.045))
    rail_color = _ensure_contrast(_mix_colors(THEME["text"], THEME["bg"], 0.42), THEME["bg"], 1.45)

    draw_coordinate_grid(ax, crop_xlim, crop_ylim, profile)
    plot_polygon_layer(ax, water_proj, water_color, 0.82 * profile.feature_alpha, 0.5)
    plot_line_layer(ax, water_proj, water_color, 0.72 * profile.feature_alpha, 0.75 * profile.road_scale, 0.65)
    plot_polygon_layer(ax, parks_proj, park_color, 0.72 * profile.feature_alpha, 0.8)
    plot_polygon_layer(
        ax,
        landuse_proj,
        land_color,
        0.34 * profile.feature_alpha,
        0.9,
        edgecolor=_mix_colors(THEME["text"], THEME["bg"], 0.62),
        linewidth=0.12,
    )
    draw_rural_texture(ax, landuse_proj, profile, crop_xlim, crop_ylim)
    plot_line_layer(ax, transport_proj, rail_color, 0.46 * profile.feature_alpha, 0.45 * profile.road_scale, 1.2)

    # Layer 2: Roads with hierarchy coloring
    print("Applying road hierarchy colors...")
    edge_colors = get_edge_colors_by_type(g_proj, profile)
    edge_widths = get_edge_widths_by_type(g_proj, profile)

    # Plot the projected graph and then apply the cropped limits
    ox.plot_graph(
        g_proj, ax=ax, bgcolor=THEME['bg'],
        node_size=0,
        edge_color=edge_colors,
        edge_linewidth=edge_widths,
        show=False,
        close=False,
    )
    ax.set_aspect("equal", adjustable="box")
    ax.set_xlim(crop_xlim)
    ax.set_ylim(crop_ylim)

    draw_feature_labels(
        ax,
        [(water_proj, 2), (parks_proj, 2), (landuse_proj, 2)],
        crop_xlim,
        crop_ylim,
        profile,
        min(height, width) / 12.0,
    )
    draw_inset_map(ax, g_proj, center_projected, profile, width, height)

    # Layer 3: Gradients (Top and Bottom)
    create_gradient_fade(ax, THEME['gradient_color'], location='bottom', zorder=10)
    create_gradient_fade(ax, THEME['gradient_color'], location='top', zorder=10)

    # Calculate scale factor based on smaller dimension (reference 12 inches)
    # This ensures text scales properly for both portrait and landscape orientations
    scale_factor = min(height, width) / 12.0

    # Base font sizes (at 12 inches width)
    base_main = 60
    base_sub = 22
    base_coords = 14
    base_attr = 8

    # 4. Typography - use custom fonts if provided, otherwise use default FONTS
    active_fonts = fonts or FONTS
    if active_fonts:
        # font_main is calculated dynamically later based on length
        font_sub = FontProperties(
            fname=active_fonts["light"], size=base_sub * scale_factor
        )
        font_coords = FontProperties(
            fname=active_fonts["regular"], size=base_coords * scale_factor
        )
        font_attr = FontProperties(
            fname=active_fonts["light"], size=base_attr * scale_factor
        )
    else:
        # Fallback to system fonts
        font_sub = FontProperties(
            family="monospace", weight="normal", size=base_sub * scale_factor
        )
        font_coords = FontProperties(
            family="monospace", size=base_coords * scale_factor
        )
        font_attr = FontProperties(family="monospace", size=base_attr * scale_factor)

    # Format city name based on script type
    # Latin scripts: apply uppercase and letter spacing for aesthetic
    # Non-Latin scripts (CJK, Thai, Arabic, etc.): no spacing, preserve case structure
    if is_latin_script(display_city):
        # Latin script: uppercase with letter spacing (e.g., "P  A  R  I  S")
        spaced_city = "  ".join(list(display_city.upper()))
    else:
        # Non-Latin script: no spacing, no forced uppercase
        # For scripts like Arabic, Thai, Japanese, etc.
        spaced_city = display_city

    # Dynamically adjust font size based on city name length to prevent truncation
    # We use the already scaled "main" font size as the starting point.
    base_adjusted_main = base_main * scale_factor
    city_char_count = len(display_city)

    # Heuristic: If length is > 10, start reducing.
    if city_char_count > 10:
        length_factor = 10 / city_char_count
        adjusted_font_size = max(base_adjusted_main * length_factor, 10 * scale_factor)
    else:
        adjusted_font_size = base_adjusted_main

    if active_fonts:
        font_main_adjusted = FontProperties(
            fname=active_fonts["bold"], size=adjusted_font_size
        )
    else:
        font_main_adjusted = FontProperties(
            family="monospace", weight="bold", size=adjusted_font_size
        )

    # --- BOTTOM TEXT ---
    ax.text(
        0.5,
        0.14,
        spaced_city,
        transform=ax.transAxes,
        color=THEME["text"],
        ha="center",
        fontproperties=font_main_adjusted,
        zorder=11,
    )

    ax.text(
        0.5,
        0.10,
        display_country.upper(),
        transform=ax.transAxes,
        color=THEME["text"],
        ha="center",
        fontproperties=font_sub,
        zorder=11,
    )

    lat, lon = point
    coords = (
        f"{lat:.4f}° N / {lon:.4f}° E"
        if lat >= 0
        else f"{abs(lat):.4f}° S / {lon:.4f}° E"
    )
    if lon < 0:
        coords = coords.replace("E", "W")

    ax.text(
        0.5,
        0.07,
        coords,
        transform=ax.transAxes,
        color=THEME["text"],
        alpha=0.7,
        ha="center",
        fontproperties=font_coords,
        zorder=11,
    )

    ax.plot(
        [0.4, 0.6],
        [0.125, 0.125],
        transform=ax.transAxes,
        color=THEME["text"],
        linewidth=1 * scale_factor,
        zorder=11,
    )

    # --- ATTRIBUTION (bottom right) ---
    if FONTS:
        font_attr = FontProperties(fname=FONTS["light"], size=8)
    else:
        font_attr = FontProperties(family="monospace", size=8)

    ax.text(
        0.98,
        0.02,
        "© OpenStreetMap contributors",
        transform=ax.transAxes,
        color=THEME["text"],
        alpha=0.5,
        ha="right",
        va="bottom",
        fontproperties=font_attr,
        zorder=11,
    )

    draw_poster_frame(ax, scale_factor)

    # 5. Save
    emit_progress(0.92, "Saving")
    print(f"Saving to {output_file}...")

    fmt = output_format.lower()
    save_kwargs = dict(
        facecolor=THEME["bg"],
        bbox_inches="tight",
        pad_inches=0.05,
    )

    # DPI matters mainly for raster formats
    if fmt == "png":
        save_kwargs["dpi"] = 300

    plt.savefig(output_file, format=fmt, **save_kwargs)

    plt.close()
    print(f"✓ Done! Poster saved as {output_file}")
    emit_progress(0.98, "Finishing")


def print_examples():
    """Print usage examples."""
    print("""
City Map Poster Generator
=========================

Usage:
  python create_map_poster.py --city <city> --country <country> [options]

Examples:
  # Iconic grid patterns
  python create_map_poster.py -c "New York" -C "USA" -t noir -d 12000           # Manhattan grid
  python create_map_poster.py -c "Barcelona" -C "Spain" -t warm_beige -d 8000   # Eixample district grid

  # Waterfront & canals
  python create_map_poster.py -c "Venice" -C "Italy" -t blueprint -d 4000       # Canal network
  python create_map_poster.py -c "Amsterdam" -C "Netherlands" -t ocean -d 6000  # Concentric canals
  python create_map_poster.py -c "Dubai" -C "UAE" -t midnight_blue -d 15000     # Palm & coastline

  # Radial patterns
  python create_map_poster.py -c "Paris" -C "France" -t pastel_dream -d 10000   # Haussmann boulevards
  python create_map_poster.py -c "Moscow" -C "Russia" -t noir -d 12000          # Ring roads

  # Organic old cities
  python create_map_poster.py -c "Tokyo" -C "Japan" -t japanese_ink -d 15000    # Dense organic streets
  python create_map_poster.py -c "Marrakech" -C "Morocco" -t terracotta -d 5000 # Medina maze
  python create_map_poster.py -c "Rome" -C "Italy" -t warm_beige -d 8000        # Ancient street layout

  # Coastal cities
  python create_map_poster.py -c "San Francisco" -C "USA" -t sunset -d 10000    # Peninsula grid
  python create_map_poster.py -c "Sydney" -C "Australia" -t ocean -d 12000      # Harbor city
  python create_map_poster.py -c "Mumbai" -C "India" -t contrast_zones -d 18000 # Coastal peninsula

  # River cities
  python create_map_poster.py -c "London" -C "UK" -t noir -d 15000              # Thames curves
  python create_map_poster.py -c "Budapest" -C "Hungary" -t copper_patina -d 8000  # Danube split

  # List themes
  python create_map_poster.py --list-themes

Options:
  --city, -c        City name (required)
  --country, -C     Country name (required)
  --country-label   Override country text displayed on poster
  --theme, -t       Theme name (default: terracotta)
  --all-themes      Generate posters for all themes
  --distance, -d    Map radius in meters (default: 18000)
  --list-themes     List all available themes

Distance guide:
  4000-6000m   Small/dense cities (Venice, Amsterdam old center)
  8000-12000m  Medium cities, focused downtown (Paris, Barcelona)
  15000-20000m Large metros, full city view (Tokyo, Mumbai)

Available themes can be found in the 'themes/' directory.
Generated posters are saved to 'posters/' directory.
""")


def list_themes():
    """List all available themes with descriptions."""
    available_themes = get_available_themes()
    if not available_themes:
        print("No themes found in 'themes/' directory.")
        return

    print("\nAvailable Themes:")
    print("-" * 60)
    for theme_name in available_themes:
        theme_path = os.path.join(THEMES_DIR, f"{theme_name}.json")
        try:
            with open(theme_path, "r", encoding=FILE_ENCODING) as f:
                theme_data = json.load(f)
                display_name = theme_data.get('name', theme_name)
                description = theme_data.get('description', '')
        except (OSError, json.JSONDecodeError):
            display_name = theme_name
            description = ""
        print(f"  {theme_name}")
        print(f"    {display_name}")
        if description:
            print(f"    {description}")
        print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate beautiful map posters for any city",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python create_map_poster.py --city "New York" --country "USA"
  python create_map_poster.py --city "New York" --country "USA" -l 40.776676 -73.971321 --theme neon_cyberpunk
  python create_map_poster.py --city Tokyo --country Japan --theme midnight_blue
  python create_map_poster.py --city Paris --country France --theme noir --distance 15000
  python create_map_poster.py --list-themes
        """,
    )

    parser.add_argument("--city", "-c", type=str, help="City name")
    parser.add_argument("--country", "-C", type=str, help="Country name")
    parser.add_argument(
        "--location",
        "-q",
        type=str,
        help="Free-form location query, such as ZIP code, city/state, address, or landmark",
    )
    parser.add_argument(
        "--latitude",
        "-lat",
        dest="latitude",
        type=str,
        help="Override latitude center point",
    )
    parser.add_argument(
        "--longitude",
        "-long",
        dest="longitude",
        type=str,
        help="Override longitude center point",
    )
    parser.add_argument(
        "--country-label",
        dest="country_label",
        type=str,
        help="Override country text displayed on poster",
    )
    parser.add_argument(
        "--theme",
        "-t",
        type=str,
        default="terracotta",
        help="Theme name (default: terracotta)",
    )
    parser.add_argument(
        "--all-themes",
        "--All-themes",
        dest="all_themes",
        action="store_true",
        help="Generate posters for all themes",
    )
    parser.add_argument(
        "--distance",
        "-d",
        type=int,
        default=18000,
        help="Map radius in meters (default: 18000)",
    )
    parser.add_argument(
        "--width",
        "-W",
        type=float,
        default=12,
        help="Image width in inches (default: 12, max: 48)",
    )
    parser.add_argument(
        "--height",
        "-H",
        type=float,
        default=16,
        help="Image height in inches (default: 16, max: 48)",
    )
    parser.add_argument(
        "--list-themes", action="store_true", help="List all available themes"
    )
    parser.add_argument(
        "--display-city",
        "-dc",
        type=str,
        help="Custom display name for city (for i18n support)",
    )
    parser.add_argument(
        "--display-country",
        "-dC",
        type=str,
        help="Custom display name for country (for i18n support)",
    )
    parser.add_argument(
        "--font-family",
        type=str,
        help='Google Fonts family name (e.g., "Noto Sans JP", "Open Sans"). If not specified, uses local Roboto fonts.',
    )
    parser.add_argument(
        "--format",
        "-f",
        default="png",
        choices=["png", "svg", "pdf"],
        help="Output format for the poster (default: png)",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        help="Explicit output file path. Intended for single-theme generation.",
    )
    parser.add_argument(
        "--cache-only",
        action="store_true",
        help="Use only cached geocoding and map data. No new OpenStreetMap requests are made.",
    )
    parser.add_argument(
        "--detail-level",
        choices=["auto", "clean", "rich"],
        default="auto",
        help="Output detail recipe. Auto adapts to road density; clean is minimal; rich adds stronger sparse-map texture.",
    )
    parser.add_argument(
        "--inset",
        choices=["auto", "on", "off"],
        default="auto",
        help="Town detail inset behavior for sparse maps (default: auto).",
    )
    parser.add_argument(
        "--no-enhance-sparse",
        action="store_true",
        help="Disable automatic sparse-map enhancements such as stronger streets, recentering, regional context, and texture.",
    )

    args = parser.parse_args()
    CACHE_ONLY = args.cache_only

    # If no arguments provided, show examples
    if len(sys.argv) == 1:
        print_examples()
        sys.exit(0)

    # List themes if requested
    if args.list_themes:
        list_themes()
        sys.exit(0)

    # Validate required arguments
    if not args.location and (not args.city or not args.country):
        print("Error: provide --location, or provide both --city and --country.\n")
        print_examples()
        sys.exit(1)

    # Enforce maximum dimensions
    if args.width > 48:
        print(
            f"⚠ Width {args.width} exceeds the maximum allowed limit of 48. It's enforced as max limit 48."
        )
        args.width = 48.0
    if args.height > 48:
        print(
            f"⚠ Height {args.height} exceeds the maximum allowed limit of 48. It's enforced as max limit 48."
        )
        args.height = 48.0

    available_themes = get_available_themes()
    if not available_themes:
        print("No themes found in 'themes/' directory.")
        sys.exit(1)

    if args.all_themes:
        themes_to_generate = available_themes
    else:
        if args.theme not in available_themes:
            print(f"Error: Theme '{args.theme}' not found.")
            print(f"Available themes: {', '.join(available_themes)}")
            sys.exit(1)
        themes_to_generate = [args.theme]

    print("=" * 50)
    print("City Map Poster Generator")
    print("=" * 50)

    # Load custom fonts if specified
    custom_fonts = None
    if args.font_family:
        custom_fonts = load_fonts(args.font_family)
        if not custom_fonts:
            print(f"⚠ Failed to load '{args.font_family}', falling back to Roboto")

    # Get coordinates and generate poster
    try:
        if args.latitude and args.longitude:
            lat = parse(args.latitude)
            lon = parse(args.longitude)
            coords = [lat, lon]
            print(f"✓ Coordinates: {', '.join([str(i) for i in coords])}")
        elif args.location:
            coords = get_coordinates_for_location(args.location)
        else:
            coords = get_coordinates(args.city, args.country)

        for theme_name in themes_to_generate:
            THEME = load_theme(theme_name)
            city_name = args.city or args.location
            country_name = args.country or ""
            if args.output and len(themes_to_generate) == 1:
                output_file = args.output
                output_dir = os.path.dirname(output_file)
                if output_dir:
                    os.makedirs(output_dir, exist_ok=True)
            else:
                output_file = generate_output_filename(city_name, theme_name, args.format)
            create_poster(
                city_name,
                country_name,
                coords,
                args.distance,
                output_file,
                args.format,
                args.width,
                args.height,
                country_label=args.country_label,
                display_city=args.display_city,
                display_country=args.display_country,
                fonts=custom_fonts,
                enhance_sparse=not args.no_enhance_sparse,
                detail_level=args.detail_level,
                inset_mode=args.inset,
            )

        print("\n" + "=" * 50)
        print("✓ Poster generation complete!")
        print("=" * 50)
        emit_progress(1.0, "Complete")

    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)
