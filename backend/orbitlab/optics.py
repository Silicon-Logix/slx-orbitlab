# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Deterministic Earth-surface camera and geographic preview of a recorded observation."""
import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from Basilisk.utilities import RigidBodyKinematics as rbk
from .physics import EARTH_RADIUS, EARTH_RATE


class EarthCamera:
    def __init__(self):
        texture = Path(__file__).resolve().parents[2] / "SLX_OrbitLab_3D/assets/earth/earth_surface_2048.png"
        self.texture = np.asarray(Image.open(texture).convert("RGB"), dtype=np.float64)
        self.height, self.width = self.texture.shape[:2]

    def sample(self, latitude, longitude):
        x = (longitude + math.pi) / (2 * math.pi) * self.width
        y = np.clip((math.pi / 2 - latitude) / math.pi * (self.height - 1), 0, self.height - 1)
        ix, iy = np.floor(x).astype(int) % self.width, np.floor(y).astype(int)
        fx, fy = (x - np.floor(x))[..., None], (y - iy)[..., None]
        lower = np.minimum(iy + 1, self.height - 1)
        return ((1-fy) * ((1-fx)*self.texture[iy, ix] + fx*self.texture[iy, (ix+1) % self.width]) +
                fy * ((1-fx)*self.texture[lower, ix] + fx*self.texture[lower, (ix+1) % self.width]))

    def acquire(self, sample):
        grid = np.linspace(-math.tan(math.radians(35)/2), math.tan(math.radians(35)/2), 256)
        x, y = np.meshgrid(grid, grid)
        rays = np.stack((x, -np.ones_like(x), -y), axis=-1)
        rays /= np.linalg.norm(rays, axis=-1)[..., None]
        rays = rays @ rbk.EP2C(sample["truth_quaternion_body_to_eci"])
        position = np.asarray(sample["position_eci_m"])
        projection = rays @ position
        discriminant = projection**2 - (position @ position - EARTH_RADIUS**2)
        distance = -projection - np.sqrt(np.maximum(discriminant, 0))
        valid = (discriminant >= 0) & (distance > 0)
        points = position + distance[..., None]*rays
        fixed = points @ np.asarray([[math.cos(EARTH_RATE*sample["time_s"]), -math.sin(EARTH_RATE*sample["time_s"]), 0],
                                     [math.sin(EARTH_RATE*sample["time_s"]), math.cos(EARTH_RATE*sample["time_s"]), 0], [0, 0, 1]])
        latitude = np.arcsin(np.clip(fixed[..., 2]/EARTH_RADIUS, -1, 1))
        longitude = np.arctan2(fixed[..., 1], fixed[..., 0])
        rgb = self.sample(latitude, longitude)
        illumination = np.maximum((points/EARTH_RADIUS) @ np.asarray(sample["sun_direction_eci"]), 0)
        gray = np.clip((rgb @ np.asarray([0.2126, 0.7152, 0.0722])) * (0.15 + 0.85*illumination), 0, 255)
        gray[~valid] = 0
        corners = [[math.degrees(latitude[i, j]), math.degrees(longitude[i, j])]
                   for i, j in ((0, 0), (0, 255), (255, 255), (255, 0)) if valid[i, j]]
        return gray.astype(np.uint8), {"camera_fov_deg": 35, "footprint_deg": corners,
            "sensor_resolution": [256, 256], "earth_pixels_percent": float(valid.mean()*100)}

    def preview(self, destination, sensor, target, metadata, time_s):
        lat, lon = target["latitude_deg"], target["longitude_deg"]
        north = np.linspace(lat+9, lat-9, 256)
        east = np.linspace(lon-13, lon+13, 360)
        longitude, latitude = np.meshgrid(np.radians(east), np.radians(north))
        context = Image.fromarray(self.sample(latitude, longitude).astype(np.uint8))
        card = Image.new("RGB", (512, 384), "#101727")
        card.paste(context, (12, 46))
        card.paste(Image.fromarray(sensor).resize((112, 112)), (388, 86))
        draw = ImageDraw.Draw(card)
        try:
            font = ImageFont.truetype("DejaVuSans.ttf", 15)
            small = ImageFont.truetype("DejaVuSans.ttf", 12)
        except OSError:
            font = small = ImageFont.load_default()
        draw.text((14, 13), "OSSERVAZIONE TERRESTRE SIMULATA", font=font, fill="#e7edf8")
        def pixel(point):
            relative_lon = (point[1]-lon+180) % 360 - 180
            return (12+(relative_lon+13)/26*359, 46+((lat+9)-point[0])/18*255)
        footprint = [pixel(point) for point in metadata["footprint_deg"]]
        if len(footprint) == 4:
            draw.line(footprint + [footprint[0]], fill="#ee574c", width=2)
        center = pixel([lat, lon])
        draw.ellipse((center[0]-6, center[1]-6, center[0]+6, center[1]+6), outline="white", fill="#d44143", width=2)
        draw.text((center[0]+10, center[1]-7), target.get("name", "Target")[:22], font=font, fill="white", stroke_width=2, stroke_fill="#192541")
        draw.text((388, 62), "SENSOR VIEW", font=small, fill="#8fb4ff")
        draw.text((388, 207), "256 x 256 pixels\nFOV 35 degrees", font=small, fill="#bdcbe3")
        draw.text((14, 316), target.get("name", "Target"), font=font, fill="#e7edf8")
        draw.text((14, 342), f"{abs(lat):.4f} {'N' if lat >= 0 else 'S'} / {abs(lon):.4f} {'E' if lon >= 0 else 'W'}     t = {time_s:.1f} s", font=small, fill="#bdcbe3")
        draw.text((14, 362), "Red: sensor footprint on the Earth's surface", font=small, fill="#bdcbe3")
        card.save(destination, format="PNG")
